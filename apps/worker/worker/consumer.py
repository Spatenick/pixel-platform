"""SQS consumer.

Delivery semantics worth being able to explain in an interview:
  * SQS is at-least-once, so handling a job twice must be harmless. Writing
    thumbnails/<id>.jpg is idempotent and the DB updates never move a "done"
    job backwards.
  * A message is only deleted after the work succeeds. If the pod dies
    mid-job, the message becomes visible again after the visibility timeout.
  * Bad input (not an image) is a *permanent* failure: mark failed, delete,
    don't burn retries on it.
  * Anything else is treated as transient: back off and retry. After
    max_receive_count attempts SQS moves the message to the dead-letter queue,
    and we mark the record failed so users aren't left at "processing".
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any
from uuid import UUID

from . import metrics
from .config import Settings
from .repository import JobRepository
from .thumbnail import InvalidImageError, make_thumbnail

log = logging.getLogger("pixelpipe.worker")


class Consumer:
    def __init__(self, settings: Settings, s3: Any, sqs: Any, repo: JobRepository) -> None:
        self.settings = settings
        self.s3 = s3
        self.sqs = sqs
        self.repo = repo
        self.last_loop = time.monotonic()

    def poll_once(self) -> int:
        """Receive one batch and process it. Returns the number of messages seen."""
        resp = self.sqs.receive_message(
            QueueUrl=self.settings.sqs_queue_url,
            MaxNumberOfMessages=self.settings.batch_size,
            WaitTimeSeconds=self.settings.wait_seconds,
            MessageSystemAttributeNames=["ApproximateReceiveCount"],
        )
        metrics.LAST_POLL.set_to_current_time()
        self.last_loop = time.monotonic()
        messages = resp.get("Messages", [])
        for message in messages:
            self.handle(message)
        return len(messages)

    def handle(self, message: dict) -> str:
        receipt = message["ReceiptHandle"]
        receive_count = int(message.get("Attributes", {}).get("ApproximateReceiveCount", "1"))

        try:
            body = json.loads(message["Body"])
            image_id = UUID(body["image_id"])
            key = str(body["key"])
        except (ValueError, KeyError, TypeError):
            log.error("malformed message, dropping: %s", message.get("Body", "")[:200])
            self._delete(receipt)
            metrics.JOBS.labels("invalid_message").inc()
            return "invalid_message"

        metrics.IN_FLIGHT.inc()
        start = time.perf_counter()
        try:
            self.repo.mark_processing(image_id)
            original = self.s3.get_object(Bucket=self.settings.s3_bucket, Key=key)["Body"].read()
            thumb = make_thumbnail(original, self.settings.thumbnail_max_px)
            thumb_key = f"thumbnails/{image_id}.jpg"
            self.s3.put_object(
                Bucket=self.settings.s3_bucket,
                Key=thumb_key,
                Body=thumb,
                ContentType="image/jpeg",
            )
            self.repo.mark_done(image_id, thumb_key)
            self._delete(receipt)
            result = "success"
            log.info("thumbnail created", extra={"image_id": str(image_id)})
        except InvalidImageError as exc:
            self.repo.mark_failed(image_id, f"invalid image: {exc}")
            self._delete(receipt)
            result = "invalid_image"
            log.warning("invalid image", extra={"image_id": str(image_id)})
        except Exception as exc:  # noqa: BLE001 - anything else is retryable
            if receive_count >= self.settings.max_receive_count:
                # Leave the message: SQS moves it to the DLQ on the next receive.
                self.repo.mark_failed(
                    image_id, f"gave up after {receive_count} attempts: {exc.__class__.__name__}"
                )
                result = "dead_letter"
                log.error("job exhausted retries", extra={"image_id": str(image_id)})
            else:
                backoff = min(5 * 2**receive_count, 300)  # 10s, 20s, 40s ... capped at 5m
                self._change_visibility(receipt, backoff)
                result = "retry"
                log.warning(
                    "job failed, retrying in %ss: %s",
                    backoff,
                    exc,
                    extra={"image_id": str(image_id)},
                )
        finally:
            metrics.IN_FLIGHT.dec()
            metrics.JOB_DURATION.observe(time.perf_counter() - start)

        metrics.JOBS.labels(result).inc()
        return result

    def _delete(self, receipt: str) -> None:
        self.sqs.delete_message(QueueUrl=self.settings.sqs_queue_url, ReceiptHandle=receipt)

    def _change_visibility(self, receipt: str, seconds: int) -> None:
        try:
            self.sqs.change_message_visibility(
                QueueUrl=self.settings.sqs_queue_url,
                ReceiptHandle=receipt,
                VisibilityTimeout=seconds,
            )
        except Exception:  # noqa: BLE001 - falls back to the queue's default timeout
            log.exception("could not change message visibility")
