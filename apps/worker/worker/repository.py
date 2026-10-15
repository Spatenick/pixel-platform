from __future__ import annotations

import threading
from typing import Protocol
from uuid import UUID

# Same DDL as the API (both services may start first).
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
SCHEMA_LOCK_ID = 7_011_001


class JobRepository(Protocol):
    def mark_processing(self, image_id: UUID) -> None: ...
    def mark_done(self, image_id: UUID, thumbnail_key: str) -> None: ...
    def mark_failed(self, image_id: UUID, error: str) -> None: ...


class InMemoryJobRepository:
    def __init__(self) -> None:
        self.status: dict[UUID, str] = {}
        self.thumbnails: dict[UUID, str] = {}
        self.errors: dict[UUID, str] = {}
        self._lock = threading.Lock()

    def mark_processing(self, image_id: UUID) -> None:
        with self._lock:
            self.status[image_id] = "processing"

    def mark_done(self, image_id: UUID, thumbnail_key: str) -> None:
        with self._lock:
            self.status[image_id] = "done"
            self.thumbnails[image_id] = thumbnail_key

    def mark_failed(self, image_id: UUID, error: str) -> None:
        with self._lock:
            self.status[image_id] = "failed"
            self.errors[image_id] = error


class PostgresJobRepository:
    def __init__(self, conninfo: str) -> None:
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(conninfo, min_size=1, max_size=4, open=True, timeout=10)

    def close(self) -> None:
        self._pool.close()

    def init_schema(self) -> None:
        with self._pool.connection() as conn, conn.transaction():
            conn.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
            conn.execute(SCHEMA_SQL)

    def _update(self, sql: str, params: tuple) -> None:
        with self._pool.connection() as conn:
            conn.execute(sql, params)

    def mark_processing(self, image_id: UUID) -> None:
        # Never move a finished job backwards (SQS is at-least-once delivery).
        self._update(
            "UPDATE images SET status = 'processing', updated_at = now() "
            "WHERE id = %s AND status IN ('pending', 'processing')",
            (image_id,),
        )

    def mark_done(self, image_id: UUID, thumbnail_key: str) -> None:
        self._update(
            "UPDATE images SET status = 'done', thumbnail_key = %s, error = NULL, "
            "updated_at = now() WHERE id = %s",
            (thumbnail_key, image_id),
        )

    def mark_failed(self, image_id: UUID, error: str) -> None:
        self._update(
            "UPDATE images SET status = 'failed', error = %s, updated_at = now() "
            "WHERE id = %s AND status <> 'done'",
            (error[:1000], image_id),
        )
