from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

JOBS = Counter(
    "pixelpipe_jobs_total",
    "Thumbnail jobs handled, by outcome",
    ["result"],  # success | invalid_image | retry | dead_letter
)
JOB_DURATION = Histogram(
    "pixelpipe_job_duration_seconds",
    "Time to process one job (download + resize + upload)",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30),
)
LAST_POLL = Gauge("pixelpipe_worker_last_poll_timestamp_seconds", "Unix time of last SQS poll")
IN_FLIGHT = Gauge("pixelpipe_worker_jobs_in_flight", "Jobs currently being processed")
