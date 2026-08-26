-- Test-only deterministic vectors. The test runner connects as the database administrator.
UPDATE bio_sightings
SET bio_field_notes_embedding = (
        '[' || array_to_string(array_fill(0::REAL, ARRAY[1536]), ',') || ']'
    )::VECTOR,
    bio_embedding_status = 'ready',
    bio_embedding_model = 'test-deterministic',
    bio_embedded_at = now()
WHERE bio_is_voided = false;

