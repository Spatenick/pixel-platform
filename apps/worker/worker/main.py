"""Entrypoint: `python -m worker.main`."""

from __future__ import annotations

import json
import logging
import signal
import sys
import threading
import time
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .config import Settings
from .consumer import Consumer

log = logging.getLogger("pixelpipe.worker")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.now(UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if getattr(record, "image_id", None):
            payload["image_id"] = record.image_id
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def serve_health(consumer: Consumer, port: int, stall_seconds: int) -> ThreadingHTTPServer:
    """/healthz (liveness: is the poll loop still turning?) and /metrics."""

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - http.server API
            if self.path == "/metrics":
                body, ctype, code = generate_latest(), CONTENT_TYPE_LATEST, 200
            elif self.path == "/healthz":
                stalled = time.monotonic() - consumer.last_loop > stall_seconds
                code = 503 if stalled else 200
                body, ctype = (b"stalled" if stalled else b"ok"), "text/plain"
            else:
                body, ctype, code = b"not found", "text/plain", 404
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args) -> None:  # silence per-request logs
            return

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)  # noqa: S104 - in-cluster port
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main() -> int:
    settings = Settings()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=settings.log_level.upper(), handlers=[handler], force=True)
    for noisy in ("botocore", "boto3", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    if not settings.sqs_queue_url:
        log.error("SQS_QUEUE_URL is not set")
        return 2

    import boto3

    from .repository import PostgresJobRepository

    s3 = boto3.client("s3", region_name=settings.aws_region)
    sqs = boto3.client("sqs", region_name=settings.aws_region)

    repo = PostgresJobRepository(settings.db_conninfo)
    for attempt in range(1, 11):
        try:
            repo.init_schema()
            break
        except Exception:  # noqa: BLE001
            if attempt == 10:
                raise
            log.warning("database not ready, retrying (%s/10)", attempt)
            time.sleep(3)

    consumer = Consumer(settings, s3, sqs, repo)
    server = serve_health(consumer, settings.health_port, settings.stall_seconds)

    # Kubernetes sends SIGTERM on scale-down/rollout. Finish the current batch,
    # then exit; unfinished messages simply reappear on the queue.
    stopping = threading.Event()

    def request_stop(signum: int, _frame) -> None:
        log.info("received signal %s, finishing current batch", signum)
        stopping.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    log.info("worker started env=%s version=%s", settings.environment, settings.app_version)
    while not stopping.is_set():
        try:
            consumer.poll_once()
        except Exception:  # noqa: BLE001 - e.g. SQS throttling or network blip
            log.exception("poll failed")
            stopping.wait(5)

    server.shutdown()
    repo.close()
    log.info("worker stopped cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
