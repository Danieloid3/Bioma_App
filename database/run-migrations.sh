#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BIO_APP_DB_PASSWORD:?BIO_APP_DB_PASSWORD is required}"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS bio_schema_migrations (
    bio_filename TEXT PRIMARY KEY,
    bio_checksum TEXT NOT NULL,
    bio_applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SQL

for migration_path in /migrations/migrations/[0-9][0-9][0-9]_*.sql; do
    migration_filename=$(basename "$migration_path")
    migration_checksum=$(sha256sum "$migration_path" | awk '{print $1}')
    applied_checksum=$(psql "$DATABASE_URL" -Atq \
        -v migration_filename="$migration_filename" <<'SQL'
SELECT bio_checksum
FROM bio_schema_migrations
WHERE bio_filename = :'migration_filename';
SQL
    )

    if [ -n "$applied_checksum" ]; then
        if [ "$applied_checksum" != "$migration_checksum" ]; then
            echo "Checksum changed for an applied migration: $migration_filename" >&2
            exit 1
        fi
        continue
    fi

    echo "Applying $migration_filename"
    psql "$DATABASE_URL" \
        -v ON_ERROR_STOP=1 \
        -v bio_app_password="$BIO_APP_DB_PASSWORD" \
        -v migration_path="$migration_path" \
        -v migration_filename="$migration_filename" \
        -v migration_checksum="$migration_checksum" <<'SQL'
BEGIN;
\i :migration_path
INSERT INTO bio_schema_migrations (bio_filename, bio_checksum)
VALUES (:'migration_filename', :'migration_checksum');
COMMIT;
SQL
done
