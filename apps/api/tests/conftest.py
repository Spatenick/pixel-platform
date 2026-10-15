from __future__ import annotations

import io
import json
import os

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws
from PIL import Image

from app.config import Settings
from app.main import create_app
from app.repository import InMemoryRepository

BUCKET = "pixelpipe-test"
REGION = "eu-west-2"


@pytest.fixture(autouse=True)
def aws_env(monkeypatch: pytest.MonkeyPatch) -> None:
    # Never let a test talk to a real AWS account.
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    monkeypatch.delenv("AWS_PROFILE", raising=False)
    monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)


@pytest.fixture
def aws():
    with mock_aws():
        s3 = boto3.client("s3", region_name=REGION)
        s3.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": REGION})
        sqs = boto3.client("sqs", region_name=REGION)
        queue_url = sqs.create_queue(QueueName="jobs")["QueueUrl"]
        yield s3, sqs, queue_url


@pytest.fixture
def repo() -> InMemoryRepository:
    return InMemoryRepository()


@pytest.fixture
def client(aws, repo):
    s3, sqs, queue_url = aws
    os.environ["SQS_QUEUE_URL"] = queue_url
    settings = Settings(s3_bucket=BUCKET, sqs_queue_url=queue_url, aws_region=REGION)
    app = create_app(settings=settings, repo=repo, s3=s3, sqs=sqs)
    with TestClient(app) as c:
        yield c


@pytest.fixture
def png_bytes() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (640, 480), (200, 30, 30)).save(buf, format="PNG")
    return buf.getvalue()


def receive_all(sqs, queue_url: str) -> list[dict]:
    msgs = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=10).get("Messages", [])
    return [json.loads(m["Body"]) for m in msgs]
