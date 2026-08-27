import hashlib
import logging
from pathlib import Path

import asyncpg

logger = logging.getLogger(__name__)

async def run_migrations(connection: asyncpg.Connection) -> None:
    candidates = [
        Path("/app/database/migrations"),
        Path(__file__).resolve().parent.parent.parent.parent / "database" / "migrations",
        Path(__file__).resolve().parent.parent.parent.parent / "backend" / "database" / "migrations",
    ]
    migrations_dir = next((p for p in candidates if p.exists() and p.is_dir()), None)
    if not migrations_dir:
        logger.warning("No database/migrations directory found for automated migration.")
        return

    await connection.execute(
        """
        CREATE TABLE IF NOT EXISTS bio_schema_migrations (
            bio_filename TEXT PRIMARY KEY,
            bio_checksum TEXT NOT NULL,
            bio_applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )

    rows = await connection.fetch("SELECT bio_filename, bio_checksum FROM bio_schema_migrations;")
    applied = {r["bio_filename"]: r["bio_checksum"] for r in rows}

    migration_files = sorted(migrations_dir.glob("[0-9][0-9][0-9]_*.sql"))
    logger.info("Found %d migration files in %s", len(migration_files), migrations_dir)

    for file_path in migration_files:
        filename = file_path.name
        content = file_path.read_text(encoding="utf-8")
        clean_content = content.replace(":'bio_app_password'", "'bio_app_dev_password_change_me'")
        clean_content = clean_content.replace(":bio_app_password", "'bio_app_dev_password_change_me'")
        checksum = hashlib.sha256(content.encode("utf-8")).hexdigest()

        if filename in applied:
            continue

        logger.info("Applying automated migration %s...", filename)
        async with connection.transaction():
            await connection.execute(clean_content)
            await connection.execute(
                "INSERT INTO bio_schema_migrations (bio_filename, bio_checksum) VALUES ($1, $2)",
                filename,
                checksum,
            )
        logger.info("Successfully applied %s", filename)