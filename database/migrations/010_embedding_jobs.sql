SET ROLE bio_owner;

ALTER TABLE bio_sightings
    ADD COLUMN bio_embedding_attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN bio_embedding_error TEXT,
    ADD CONSTRAINT ck_bio_sightings_embedding_attempts CHECK (bio_embedding_attempts >= 0);

CREATE FUNCTION bio_fn_claim_embedding_job(
    p_stale_after INTERVAL DEFAULT INTERVAL '15 minutes'
) RETURNS TABLE (sighting_id UUID, field_notes TEXT, embedding_attempts INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    RETURN QUERY
    WITH candidate AS (
        SELECT s.bio_sighting_id
        FROM public.bio_sightings AS s
        WHERE s.bio_is_voided = false
          AND (
              s.bio_embedding_status = 'pending'
              OR (s.bio_embedding_status = 'failed' AND s.bio_embedding_attempts < 5)
              OR (s.bio_embedding_status = 'processing' AND s.bio_updated_at < now() - p_stale_after)
          )
        ORDER BY s.bio_updated_at, s.bio_sighting_id
        FOR UPDATE SKIP LOCKED
        LIMIT 1
    )
    UPDATE public.bio_sightings AS s
    SET bio_embedding_status = 'processing',
        bio_embedding_attempts = s.bio_embedding_attempts + 1,
        bio_embedding_error = NULL,
        bio_updated_at = now()
    FROM candidate
    WHERE s.bio_sighting_id = candidate.bio_sighting_id
    RETURNING s.bio_sighting_id, s.bio_field_notes, s.bio_embedding_attempts;
END;
$$;

CREATE FUNCTION bio_fn_mark_embedding_failed(
    p_sighting_id UUID,
    p_error TEXT
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    UPDATE public.bio_sightings
    SET bio_embedding_status = 'failed',
        bio_embedding_error = left(coalesce(p_error, 'unknown embedding error'), 1000),
        bio_updated_at = now()
    WHERE bio_sighting_id = p_sighting_id
      AND bio_is_voided = false
      AND bio_embedding_status = 'processing';
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_claim_embedding_job(INTERVAL) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_mark_embedding_failed(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_claim_embedding_job(INTERVAL) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_mark_embedding_failed(UUID, TEXT) TO bio_app_user;

RESET ROLE;
