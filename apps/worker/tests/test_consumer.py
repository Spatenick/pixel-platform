from __future__ import annotations

import io
import json
from uuid import uuid4

import boto3
import pytest
from moto import mock_aws
from PIL import Image

from worker.config import Settings
from worker.consumer import Consumer
from worker.repository import InMemoryJobRepository

REGION = "eu-west-2"
BUCKET = "pixelpipe-test"


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.delenv("AWS_PROFILE", raising=False)
    monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)


@pytest.fixture
def env():
    with mock_aws():
        s3 = boto3.client("s3", region_name=REGION)
        s3.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": REGION})
        sqs = boto3.client("sqs", region_name=REGION)
        url = sqs.create_queue(QueueName="jobs", Attributes={"VisibilityTimeout": "0"})["QueueUrl"]
        settings = Settings(s3_bucket=BUCKET, sqs_queue_url=url, aws_region=REGION, wait_seconds=0)
        repo = InMemoryJobRepository()
        yield Consumer(settings, s3, sqs, repo), s3, sqs, url, repo


def _png() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (800, 600), (0, 200, 0)).save(buf, format="PNG")
    return buf.getvalue()


def _enqueue(sqs, url, image_id, key):
    sqs.send_message(QueueUrl=url, MessageBody=json.dumps({"image_id": str(image_id), "key": key}))


def _queue_depth(sqs, url) -> int:
    attrs = sqs.get_queue_attributes(
        QueueUrl=url,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    return int(attrs["ApproximateNumberOfMessages"]) + int(
        attrs["ApproximateNumberOfMessagesNotVisible"]
    )


def test_happy_path_writes_thumbnail_and_deletes_message(env):
    consumer, s3, sqs, url, repo = env
    image_id = uuid4()
    s3.put_object(Bucket=BUCKET, Key=f"originals/{image_id}", Body=_png())
    _enqueue(sqs, url, image_id, f"originals/{image_id}")

    assert consumer.poll_once() == 1

    assert repo.status[image_id] == "done"
    thumb = s3.get_object(Bucket=BUCKET, Key=f"thumbnails/{image_id}.jpg")["Body"].read()
    assert Image.open(io.BytesIO(thumb)).size == (256, 192)
    assert _queue_depth(sqs, url) == 0


def test_processing_the_same_message_twice_is_harmless(env):
    consumer, s3, sqs, url, repo = env
    image_id = uuid4()
    s3.put_object(Bucket=BUCKET, Key=f"originals/{image_id}", Body=_png())
    _enqueue(sqs, url, image_id, f"originals/{image_id}")
    _enqueue(sqs, url, image_id, f"originals/{image_id}")  # duplicate delivery

    consumer.poll_once()
    consumer.poll_once()

    assert repo.status[image_id] == "done"
    assert _queue_depth(sqs, url) == 0


def test_invalid_image_is_failed_and_not_retried(env):
    consumer, s3, sqs, url, repo = env
    image_id = uuid4()
    s3.put_object(Bucket=BUCKET, Key=f"originals/{image_id}", Body=b"not an image")
    _enqueue(sqs, url, image_id, f"originals/{image_id}")

    consumer.poll_once()

    assert repo.status[image_id] == "failed"
    assert "invalid image" in repo.errors[image_id]
    assert _queue_depth(sqs, url) == 0


def test_transient_error_is_retried_then_marked_failed(env):
    consumer, _s3, sqs, url, repo = env
    image_id = uuid4()
    # original doesn't exist -> NoSuchKey, which we treat as transient
    _enqueue(sqs, url, image_id, f"originals/{image_id}")

    msg = sqs.receive_message(QueueUrl=url, MessageSystemAttributeNames=["ApproximateReceiveCount"])
    first = msg["Messages"][0]
    assert consumer.handle(first) == "retry"
    assert repo.status[image_id] == "processing"

    first["Attributes"]["ApproximateReceiveCount"] = "3"  # simulate the final attempt
    assert consumer.handle(first) == "dead_letter"
    assert repo.status[image_id] == "failed"
    assert "gave up after 3 attempts" in repo.errors[image_id]


def test_malformed_message_is_dropped(env):
    consumer, _s3, sqs, url, _repo = env
    sqs.send_message(QueueUrl=url, MessageBody="{not json")
    consumer.poll_once()
    assert _queue_depth(sqs, url) == 0
