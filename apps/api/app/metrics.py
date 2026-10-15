"""Prometheus metrics.

Requests are labelled by *route template* (`/v1/images/{image_id}`), never by
raw path -- otherwise every image ID becomes a new time series and Prometheus
falls over (the classic cardinality explosion).
"""

from __future__ import annotations

from prometheus_client import Counter, Histogram

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests handled",
    ["method", "route", "status"],
)

HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

IMAGES_UPLOADED = Counter("pixelpipe_images_uploaded_total", "Images accepted for processing")
UPLOAD_BYTES = Histogram(
    "pixelpipe_upload_size_bytes",
    "Size of accepted uploads",
    buckets=(10_000, 50_000, 100_000, 500_000, 1_000_000, 2_500_000, 5_000_000),
)
ENQUEUE_FAILURES = Counter(
    "pixelpipe_enqueue_failures_total", "Uploads stored but the SQS job could not be sent"
)
