"""HTTP API.

Run in production with:  uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8080
"""

from __future__ import annotations

import json
import logging
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any
from uuid import UUID

from fastapi import FastAPI, File, HTTPException, Query, Request, Response, UploadFile, status
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel

from . import metrics
from .config import ALLOWED_CONTENT_TYPES, Settings
from .logging_setup import configure_logging
from .repository import ImageRecord, Repository

log = logging.getLogger("pixelpipe.api")


class ImageOut(BaseModel):
    id: UUID
    filename: str
    content_type: str
    size_bytes: int
    status: str
    error: str | None = None
    thumbnail_url: str | None = None
    created_at: datetime
    updated_at: datetime


def _sniff_image_type(head: bytes) -> str | None:
    """Trust the bytes, not the client's Content-Type header."""
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    return None


def create_app(
    settings: Settings | None = None,
    repo: Repository | None = None,
    s3: Any | None = None,
    sqs: Any | None = None,
) -> FastAPI:
    settings = settings or Settings()
    configure_logging(settings.log_level)

    if s3 is None or sqs is None:
        import boto3

        # AWS_ENDPOINT_URL (LocalStack) is honoured automatically by boto3.
        s3 = s3 or boto3.client("s3", region_name=settings.aws_region)
        sqs = sqs or boto3.client("sqs", region_name=settings.aws_region)

    owns_repo = repo is None

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        nonlocal repo
        if repo is None:
            from .repository import PostgresRepository

            pg = PostgresRepository(settings.db_conninfo)
            _init_schema_with_retry(pg)
            repo = pg
        app.state.repo = repo
        log.info("api started env=%s version=%s", settings.environment, settings.app_version)
        yield
        if owns_repo and hasattr(repo, "close"):
            repo.close()

    app = FastAPI(
        title="pixelpipe API",
        version=settings.app_version,
        lifespan=lifespan,
    )
    if repo is not None:
        app.state.repo = repo

    # ---- middleware: request id, metrics, one structured log line per request
    @app.middleware("http")
    async def observe(request: Request, call_next):  # type: ignore[no-untyped-def]
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        start = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            response.headers["x-request-id"] = request_id
            return response
        finally:
            elapsed = time.perf_counter() - start
            route = request.scope.get("route")
            route_label = getattr(route, "path", "unmatched")
            if route_label not in ("/metrics", "/healthz", "/readyz"):
                metrics.HTTP_REQUESTS.labels(request.method, route_label, str(status_code)).inc()
                metrics.HTTP_LATENCY.labels(request.method, route_label).observe(elapsed)
                log.info(
                    "request",
                    extra={
                        "request_id": request_id,
                        "method": request.method,
                        "path": route_label,
                        "status": status_code,
                        "duration_ms": round(elapsed * 1000, 1),
                    },
                )

    def get_repo(request: Request) -> Repository:
        return request.app.state.repo

    def to_out(rec: ImageRecord) -> ImageOut:
        thumb_url = None
        if rec.status == "done" and rec.thumbnail_key:
            thumb_url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": settings.s3_bucket, "Key": rec.thumbnail_key},
                ExpiresIn=settings.presign_expiry_seconds,
            )
        return ImageOut(
            id=rec.id,
            filename=rec.filename,
            content_type=rec.content_type,
            size_bytes=rec.size_bytes,
            status=rec.status,
            error=rec.error,
            thumbnail_url=thumb_url,
            created_at=rec.created_at,
            updated_at=rec.updated_at,
        )

    # ---- probes & metrics ------------------------------------------------------

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict[str, str]:
        """Liveness: the process is up. Deliberately does NOT check the DB --
        a DB outage shouldn't make Kubernetes restart every API pod."""
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    def readyz(request: Request) -> JSONResponse:
        """Readiness: only receive traffic if we can reach the database."""
        ok = get_repo(request).ping()
        return JSONResponse(
            {"status": "ready" if ok else "not-ready"},
            status_code=status.HTTP_200_OK if ok else status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    @app.get("/metrics", include_in_schema=False)
    def prometheus_metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    # ---- API -------------------------------------------------------------------

    @app.get("/")
    def root() -> dict[str, str]:
        return {
            "service": "pixelpipe-api",
            "version": settings.app_version,
            "environment": settings.environment,
            "docs": "/docs",
        }

    @app.post("/v1/images", status_code=status.HTTP_202_ACCEPTED, response_model=ImageOut)
    async def upload_image(request: Request, file: UploadFile = File(...)) -> ImageOut:
        data = await file.read(settings.max_upload_bytes + 1)
        if len(data) > settings.max_upload_bytes:
            raise HTTPException(
                status.HTTP_413_CONTENT_TOO_LARGE,
                f"File larger than {settings.max_upload_bytes} bytes",
            )
        if not data:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Empty file")

        content_type = _sniff_image_type(data[:16])
        if content_type not in ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                "Only JPEG, PNG, GIF and WebP images are accepted",
            )

        image_id = uuid.uuid4()
        key = f"originals/{image_id}"
        s3.put_object(
            Bucket=settings.s3_bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            Metadata={"filename": (file.filename or "upload")[:200]},
        )

        repo = get_repo(request)
        record = repo.create(
            ImageRecord(
                id=image_id,
                filename=(file.filename or "upload")[:255],
                content_type=content_type,
                size_bytes=len(data),
                original_key=key,
            )
        )

        try:
            sqs.send_message(
                QueueUrl=settings.sqs_queue_url,
                MessageBody=json.dumps({"image_id": str(image_id), "key": key}),
            )
        except Exception as exc:  # noqa: BLE001
            metrics.ENQUEUE_FAILURES.inc()
            log.exception("failed to enqueue job", extra={"image_id": str(image_id)})
            repo.mark_failed(image_id, f"enqueue failed: {exc.__class__.__name__}")
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, "Could not queue the job, try again"
            ) from exc

        metrics.IMAGES_UPLOADED.inc()
        metrics.UPLOAD_BYTES.observe(len(data))
        log.info("image accepted", extra={"image_id": str(image_id)})
        return to_out(record)

    @app.get("/v1/images/{image_id}", response_model=ImageOut)
    def get_image(image_id: UUID, request: Request) -> ImageOut:
        rec = get_repo(request).get(image_id)
        if rec is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Image not found")
        return to_out(rec)

    @app.get("/v1/images", response_model=list[ImageOut])
    def list_images(request: Request, limit: int = Query(20, ge=1, le=100)) -> list[ImageOut]:
        return [to_out(r) for r in get_repo(request).list_recent(limit)]

    return app


def _init_schema_with_retry(pg: Any, attempts: int = 10, delay: float = 3.0) -> None:
    for attempt in range(1, attempts + 1):
        try:
            pg.init_schema()
            return
        except Exception:  # noqa: BLE001
            if attempt == attempts:
                raise
            log.warning("database not ready, retrying (%s/%s)", attempt, attempts)
            time.sleep(delay)
