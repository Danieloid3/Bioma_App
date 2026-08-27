#!/bin/sh
set -eu

: "${DATABASE_ADMIN_URL:?DATABASE_ADMIN_URL is required}"
: "${DATABASE_APP_URL:?DATABASE_APP_URL is required}"

cleanup() {
    psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -f /migrations/tests/cleanup_rag_test_data.sql
}
trap cleanup EXIT

psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -f /migrations/tests/prepare_rag_test_data.sql
hidden_sighting_id=$(psql "$DATABASE_ADMIN_URL" -At -v ON_ERROR_STOP=1 -c "SELECT bio_sighting_id FROM bio_sightings WHERE bio_observation_reference = 'obs-5001'")
psql "$DATABASE_APP_URL" -v ON_ERROR_STOP=1 -v "hidden_sighting_id=$hidden_sighting_id" -f /migrations/tests/rls_assertions.sql
echo "RLS and RAG security assertions passed."
