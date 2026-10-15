from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.repository import ImageRecord
from tests.conftest import BUCKET, REGION, receive_all


def test_root_reports_service(client):
    body = client.get("/").json()
    assert body["service"] == "pixelpipe-api"


def test_liveness_does_not_depend_on_db(client, repo):
    repo.healthy = False
    assert client.get("/healthz").status_code == 200


def test_readiness_reflects_db(client, repo):
    assert client.get("/readyz").status_code == 200
    repo.healthy = False
    assert client.get("/readyz").status_code == 503


def test_upload_stores_original_records_and_enqueues(client, aws, repo, png_bytes):
    s3, sqs, queue_url = aws

    resp = client.post("/v1/images", files={"file": ("cat.png", png_bytes, "image/png")})

    assert resp.status_code == 202, resp.text
    body = resp.json()
    assert body["status"] == "pending"
    assert body["content_type"] == "image/png"

    # original stored in S3
    obj = s3.get_object(Bucket=BUCKET, Key=f"originals/{body['id']}")
    assert obj["Body"].read() == png_bytes

    # job queued for the worker
    jobs = receive_all(sqs, queue_url)
    assert jobs == [{"image_id": body["id"], "key": f"originals/{body['id']}"}]

    # record persisted
    assert client.get(f"/v1/images/{body['id']}").json()["status"] == "pending"


def test_rejects_non_images_even_with_image_content_type(client):
    resp = client.post(
        "/v1/images", files={"file": ("evil.png", b"#!/bin/sh\nrm -rf /", "image/png")}
    )
    assert resp.status_code == 415


def test_rejects_empty_upload(client):
    resp = client.post("/v1/images", files={"file": ("e.png", b"", "image/png")})
    assert resp.status_code == 400


def test_rejects_oversized_upload(client, png_bytes):
    big = png_bytes + b"\0" * (5 * 1024 * 1024)
    resp = client.post("/v1/images", files={"file": ("big.png", big, "image/png")})
    assert resp.status_code == 413


def test_enqueue_failure_marks_record_failed(aws, repo, png_bytes):
    s3, _sqs, _queue_url = aws

    class BrokenSqs:
        def send_message(self, **_kwargs):
            raise ConnectionError("sqs unavailable")

    settings = Settings(s3_bucket=BUCKET, sqs_queue_url="unused", aws_region=REGION)
    app = create_app(settings=settings, repo=repo, s3=s3, sqs=BrokenSqs())
    with TestClient(app) as c:
        resp = c.post("/v1/images", files={"file": ("cat.png", png_bytes, "image/png")})

    assert resp.status_code == 503
    [record] = repo.list_recent(10)
    assert record.status == "failed"
    assert "enqueue failed" in record.error


def test_get_unknown_image_404(client):
    assert client.get(f"/v1/images/{uuid4()}").status_code == 404


def test_done_image_has_presigned_thumbnail_url(client, repo):
    rec = repo.create(
        ImageRecord(
            id=uuid4(),
            filename="x.png",
            content_type="image/png",
            size_bytes=10,
            original_key="originals/x",
            status="done",
            thumbnail_key="thumbnails/x.jpg",
        )
    )
    body = client.get(f"/v1/images/{rec.id}").json()
    assert body["thumbnail_url"].startswith("https://")
    assert "thumbnails/x.jpg" in body["thumbnail_url"]


def test_list_is_newest_first_and_limited(client, png_bytes):
    for i in range(3):
        client.post("/v1/images", files={"file": (f"{i}.png", png_bytes, "image/png")})
    items = client.get("/v1/images?limit=2").json()
    assert len(items) == 2
    assert items[0]["created_at"] >= items[1]["created_at"]


def test_metrics_use_route_templates_not_raw_paths(client):
    image_id = uuid4()
    client.get(f"/v1/images/{image_id}")
    text = client.get("/metrics").text
    assert 'route="/v1/images/{image_id}"' in text
    assert str(image_id) not in text


def test_request_id_is_propagated(client):
    resp = client.get("/", headers={"x-request-id": "abc123"})
    assert resp.headers["x-request-id"] == "abc123"
