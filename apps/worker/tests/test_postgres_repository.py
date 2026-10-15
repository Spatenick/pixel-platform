"""Integration tests against a real PostgreSQL (skipped unless
PIXELPIPE_TEST_DATABASE_URL is set -- CI provides a postgres service)."""

from __future__ import annotations

import os
from uuid import uuid4

import pytest

from worker.repository import PostgresJobRepository

DSN = os.environ.get("PIXELPIPE_TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="PIXELPIPE_TEST_DATABASE_URL not set")


@pytest.fixture
def pg():
    repo = PostgresJobRepository(DSN)
    repo.init_schema()
    yield repo
    repo.close()


def _insert(pg, image_id, status="pending"):
    with pg._pool.connection() as conn:  # noqa: SLF001
        conn.execute(
            "INSERT INTO images (id, filename, content_type, size_bytes, original_key, status) "
            "VALUES (%s, 'a.png', 'image/png', 1, 'originals/a', %s)",
            (image_id, status),
        )


def _status(pg, image_id):
    with pg._pool.connection() as conn:  # noqa: SLF001
        return conn.execute("SELECT status FROM images WHERE id = %s", (image_id,)).fetchone()[0]


def test_lifecycle(pg):
    image_id = uuid4()
    _insert(pg, image_id)
    pg.mark_processing(image_id)
    assert _status(pg, image_id) == "processing"
    pg.mark_done(image_id, "thumbnails/x.jpg")
    assert _status(pg, image_id) == "done"


def test_redelivery_never_moves_done_backwards(pg):
    image_id = uuid4()
    _insert(pg, image_id, status="done")
    pg.mark_processing(image_id)  # duplicate SQS delivery
    pg.mark_failed(image_id, "late failure from a duplicate")
    assert _status(pg, image_id) == "done"
