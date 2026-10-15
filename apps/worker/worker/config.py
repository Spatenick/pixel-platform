from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


@dataclass(frozen=True)
class Settings:
    environment: str = field(default_factory=lambda: _env("ENVIRONMENT", "local"))
    app_version: str = field(default_factory=lambda: _env("APP_VERSION", "dev"))
    aws_region: str = field(default_factory=lambda: _env("AWS_REGION", "eu-west-2"))
    s3_bucket: str = field(default_factory=lambda: _env("S3_BUCKET", "pixelpipe-local"))
    sqs_queue_url: str = field(default_factory=lambda: _env("SQS_QUEUE_URL", ""))
    log_level: str = field(default_factory=lambda: _env("LOG_LEVEL", "INFO"))

    thumbnail_max_px: int = field(default_factory=lambda: int(_env("THUMBNAIL_MAX_PX", "256")))
    batch_size: int = field(default_factory=lambda: int(_env("SQS_BATCH_SIZE", "5")))
    wait_seconds: int = field(default_factory=lambda: int(_env("SQS_WAIT_SECONDS", "20")))
    # Must match the queue's redrive maxReceiveCount (infra/modules/app-resources).
    max_receive_count: int = field(default_factory=lambda: int(_env("SQS_MAX_RECEIVES", "3")))
    health_port: int = field(default_factory=lambda: int(_env("HEALTH_PORT", "9100")))
    # Liveness fails if the poll loop hasn't completed an iteration in this long.
    stall_seconds: int = field(default_factory=lambda: int(_env("STALL_SECONDS", "120")))

    db_host: str = field(default_factory=lambda: _env("DB_HOST", "localhost"))
    db_port: int = field(default_factory=lambda: int(_env("DB_PORT", "5432")))
    db_name: str = field(default_factory=lambda: _env("DB_NAME", "pixelpipe"))
    db_user: str = field(default_factory=lambda: _env("DB_USER", "pixelpipe"))
    db_password: str = field(default_factory=lambda: _env("DB_PASSWORD", "pixelpipe"))
    db_sslmode: str = field(default_factory=lambda: _env("DB_SSLMODE", "prefer"))

    @property
    def db_conninfo(self) -> str:
        from psycopg.conninfo import make_conninfo

        return make_conninfo(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password,
            sslmode=self.db_sslmode,
            connect_timeout=5,
            application_name="pixelpipe-worker",
        )
