-- Restore the seed's pending-embedding state after the deterministic RLS/RAG test.
UPDATE bio_sightings
SET bio_field_notes_embedding = NULL,
    bio_embedding_status = 'pending',
    bio_embedding_model = NULL,
    bio_embedded_at = NULL
WHERE bio_embedding_model = 'test-deterministic';

