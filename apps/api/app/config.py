"""Configuration, read once from environment variables.

In Kubernetes these come from two places (see charts/service + platform-glue):
  * the `pixelpipe-infra` ConfigMap Terraform writes (bucket, queue, DB host...)
  * the `pixelpipe-db` Secret External Secrets syncs from AWS Secrets Manager
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None:
        raise RuntimeError(f"Missing required environment variable {name}")
    return value


@dataclass(frozen=True)
class Settings:
    environment: str = field(default_factory=lambda: _env("ENVIRONMENT", "local"))
    app_version: str = field(default_factory=lambda: _env("APP_VERSION", "dev"))
    aws_region: str = field(default_factory=lambda: _env("AWS_REGION", "eu-west-2"))
    s3_bucket: str = field(default_factory=lambda: _env("S3_BUCKET", "pixelpipe-local"))
    sqs_queue_url: str = field(default_factory=lambda: _env("SQS_QUEUE_URL", ""))
    max_upload_bytes: int = field(
        default_factory=lambda: int(_env("MAX_UPLOAD_BYTES", str(5 * 1024 * 1024)))
    )
    presign_expiry_seconds: int = field(
        default_factory=lambda: int(_env("PRESIGN_EXPIRY_SECONDS", "900"))
    )
    log_level: str = field(default_factory=lambda: _env("LOG_LEVEL", "INFO"))

    # Database
    db_host: str = field(default_factory=lambda: _env("DB_HOST", "localhost"))
    db_port: int = field(default_factory=lambda: int(_env("DB_PORT", "5432")))
    db_name: str = field(default_factory=lambda: _env("DB_NAME", "pixelpipe"))
    db_user: str = field(default_factory=lambda: _env("DB_USER", "pixelpipe"))
    db_password: str = field(default_factory=lambda: _env("DB_PASSWORD", "pixelpipe"))
    db_sslmode: str = field(default_factory=lambda: _env("DB_SSLMODE", "prefer"))

    @property
    def db_conninfo(self) -> str:
        # make_conninfo quotes/escapes values properly -- RDS-generated
        # passwords can contain characters that would break a hand-built string.
        from psycopg.conninfo import make_conninfo

        return make_conninfo(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password,
            sslmode=self.db_sslmode,
            connect_timeout=5,
            application_name="pixelpipe-api",
        )


ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
