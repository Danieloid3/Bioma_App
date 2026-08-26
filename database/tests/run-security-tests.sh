#!/bin/sh
set -eu

: "${DATABASE_ADMIN_URL:?DATABASE_ADMIN_URL is required}"
: "${DATABASE_APP_URL:?DATABASE_APP_URL is required}"

cleanup() {
    psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -f /migrations/tests/cleanup_rag_test_data.sql
}
trap cleanup EXIT

psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -f /migrations/tests/prepare_rag_test_data.sql
psql "$DATABASE_APP_URL" -v ON_ERROR_STOP=1 -f /migrations/tests/rls_assertions.sql
echo "RLS and RAG security assertions passed."
