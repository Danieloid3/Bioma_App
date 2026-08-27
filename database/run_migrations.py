import asyncio
import hashlib
import os
import sys
from pathlib import Path
import asyncpg

MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations"

async def run():
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        print("DATABASE_URL is not set", file=sys.stderr)
        sys.exit(1)

    print(f"Connecting to database...")
    # asyncpg might need postgresql:// instead of postgres://
    normalized_url = database_url.replace("postgres://", "postgresql://", 1)
    
    conn = await asyncpg.connect(normalized_url)
    try:
        # 1. Ensure migrations table exists
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS bio_schema_migrations (
                bio_filename TEXT PRIMARY KEY,
                bio_checksum TEXT NOT NULL,
                bio_applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            );
        """)

        # 2. Get applied migrations
        rows = await conn.fetch("SELECT bio_filename, bio_checksum FROM bio_schema_migrations;")
        applied = {r["bio_filename"]: r["bio_checksum"] for r in rows}

        # 3. Find and sort migration files
        migration_files = sorted(MIGRATIONS_DIR.glob("[0-9][0-9][0-9]_*.sql"))
        print(f"Found {len(migration_files)} migration files in {MIGRATIONS_DIR}")

        bio_app_pwd = os.environ.get("BIO_APP_DB_PASSWORD", "bio_app_dev_password_change_me")

        for file_path in migration_files:
            filename = file_path.name
            content = file_path.read_text(encoding="utf-8")
            # substitute :bio_app_password if present
            clean_content = content.replace(":'bio_app_password'", f"'{bio_app_pwd}'")
            clean_content = clean_content.replace(":bio_app_password", f"'{bio_app_pwd}'")
            
            checksum = hashlib.sha256(content.encode("utf-8")).hexdigest()

            if filename in applied:
                print(f"  [OK] {filename} (already applied)")
                continue

            print(f"  --> Applying {filename}...")
            async with conn.transaction():
                # Execute migration script
                await conn.execute(clean_content)
                await conn.execute(
                    "INSERT INTO bio_schema_migrations (bio_filename, bio_checksum) VALUES ($1, $2)",
                    filename, checksum
                )
            print(f"  [DONE] Applied {filename}")

        print("\nAll database migrations executed successfully!")
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(run())