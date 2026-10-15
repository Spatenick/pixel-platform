"""Persistence for image records.

`Repository` is a small protocol so the API can run against PostgreSQL in
production and an in-memory fake in unit tests.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS images (
    id             UUID PRIMARY KEY,
    filename       TEXT        NOT NULL,
    content_type   TEXT        NOT NULL,
    size_bytes     INTEGER     NOT NULL,
    original_key   TEXT        NOT NULL,
    thumbnail_key  TEXT,
    status         TEXT        NOT NULL
                   CHECK (status IN ('pending', 'processing', 'done', 'failed')),
    error          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS images_created_at_idx ON images (created_at DESC);
"""

# Arbitrary constant: every replica takes this advisory lock before running
# the DDL so concurrent pod starts don't race each other.
SCHEMA_LOCK_ID = 7_011_001


@dataclass(frozen=True)
class ImageRecord:
    id: UUID
    filename: str
    content_type: str
    size_bytes: int
    original_key: str
    status: str = "pending"
    thumbnail_key: str | None = None
    error: str | None = None
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = field(default_factory=lambda: datetime.now(UTC))


class Repository(Protocol):
    def ping(self) -> bool: ...
    def create(self, record: ImageRecord) -> ImageRecord: ...
    def get(self, image_id: UUID) -> ImageRecord | None: ...
    def list_recent(self, limit: int) -> list[ImageRecord]: ...
    def mark_failed(self, image_id: UUID, error: str) -> None: ...


class InMemoryRepository:
    """Thread-safe fake used by tests and `PIXELPIPE_FAKE_DB=1` local runs."""

    def __init__(self) -> None:
        self._rows: dict[UUID, ImageRecord] = {}
        self._lock = threading.Lock()
        self.healthy = True

    def ping(self) -> bool:
        return self.healthy

    def create(self, record: ImageRecord) -> ImageRecord:
        with self._lock:
            self._rows[record.id] = record
        return record

    def get(self, image_id: UUID) -> ImageRecord | None:
        return self._rows.get(image_id)

    def list_recent(self, limit: int) -> list[ImageRecord]:
        rows = sorted(self._rows.values(), key=lambda r: r.created_at, reverse=True)
        return rows[:limit]

    def mark_failed(self, image_id: UUID, error: str) -> None:
        with self._lock:
            if image_id in self._rows:
                self._rows[image_id] = replace(self._rows[image_id], status="failed", error=error)


class PostgresRepository:
    def __init__(self, conninfo: str, min_size: int = 1, max_size: int = 10) -> None:
        # Imported lazily so unit tests don't need libpq.
        from psycopg.rows import dict_row
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(
            conninfo,
            min_size=min_size,
            max_size=max_size,
            kwargs={"row_factory": dict_row},
            open=True,
            timeout=10,
        )

    def close(self) -> None:
        self._pool.close()

    def init_schema(self) -> None:
        with self._pool.connection() as conn, conn.transaction():
            conn.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
            conn.execute(SCHEMA_SQL)

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=2) as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:  # noqa: BLE001 - any failure means "not ready"
            return False

    def create(self, record: ImageRecord) -> ImageRecord:
        with self._pool.connection() as conn:
            row = conn.execute(
                """
                INSERT INTO images (id, filename, content_type, size_bytes, original_key, status)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING *
                """,
                (
                    record.id,
                    record.filename,
                    record.content_type,
                    record.size_bytes,
                    record.original_key,
                    record.status,
                ),
            ).fetchone()
        return _to_record(row)

    def get(self, image_id: UUID) -> ImageRecord | None:
        with self._pool.connection() as conn:
            row = conn.execute("SELECT * FROM images WHERE id = %s", (image_id,)).fetchone()
        return _to_record(row) if row else None

    def list_recent(self, limit: int) -> list[ImageRecord]:
        with self._pool.connection() as conn:
            rows = conn.execute(
                "SELECT * FROM images ORDER BY created_at DESC LIMIT %s", (limit,)
            ).fetchall()
        return [_to_record(r) for r in rows]

    def mark_failed(self, image_id: UUID, error: str) -> None:
        with self._pool.connection() as conn:
            conn.execute(
                "UPDATE images SET status = 'failed', error = %s, updated_at = now() WHERE id = %s",
                (error[:1000], image_id),
            )


def _to_record(row: dict) -> ImageRecord:
    return ImageRecord(
        id=row["id"],
        filename=row["filename"],
        content_type=row["content_type"],
        size_bytes=row["size_bytes"],
        original_key=row["original_key"],
        status=row["status"],
        thumbnail_key=row["thumbnail_key"],
        error=row["error"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )
