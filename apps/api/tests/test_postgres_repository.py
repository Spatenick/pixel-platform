"""Integration tests against a real PostgreSQL.

Skipped unless PIXELPIPE_TEST_DATABASE_URL is set. CI starts a postgres
service container and sets it; locally: `make test-integration` (docker compose).
"""

from __future__ import annotations

import os
import threading
from uuid import uuid4

import pytest

from app.repository import ImageRecord, PostgresRepository

DSN = os.environ.get("PIXELPIPE_TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="PIXELPIPE_TEST_DATABASE_URL not set")


@pytest.fixture
def pg():
    repo = PostgresRepository(DSN, min_size=1, max_size=4)
    repo.init_schema()
    with repo._pool.connection() as conn:  # noqa: SLF001 - test cleanup
        conn.execute("TRUNCATE images")
    yield repo
    repo.close()


def _record(**kw) -> ImageRecord:
    defaults = dict(
        id=uuid4(),
        filename="a.png",
        content_type="image/png",
        size_bytes=123,
        original_key="originals/a",
    )
    defaults.update(kw)
    return ImageRecord(**defaults)


def test_schema_init_is_idempotent_and_safe_concurrently(pg):
    errors: list[Exception] = []

    def init():
        try:
            pg.init_schema()
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=init) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []


def test_create_get_list_and_fail(pg):
    rec = pg.create(_record())
    assert pg.ping() is True

    fetched = pg.get(rec.id)
    assert fetched is not None and fetched.status == "pending"

    pg.create(_record(filename="b.png"))
    assert len(pg.list_recent(10)) == 2

    pg.mark_failed(rec.id, "boom")
    assert pg.get(rec.id).status == "failed"
    assert pg.get(rec.id).error == "boom"


def test_status_check_constraint(pg):
    with pytest.raises(Exception):  # noqa: B017 - psycopg CheckViolation
        pg.create(_record(status="exploded"))
