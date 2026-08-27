SET ROLE bio_owner;

-- Enriched embedding document function: combines species, site and field notes
-- so semantic queries for species names, locations or behavior match accurately.

CREATE OR REPLACE FUNCTION bio_fn_claim_embedding_job(
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
    ),
    updated AS (
        UPDATE public.bio_sightings AS s
        SET bio_embedding_status = 'processing',
            bio_embedding_attempts = s.bio_embedding_attempts + 1,
            bio_embedding_error = NULL,
            bio_updated_at = now()
        FROM candidate
        WHERE s.bio_sighting_id = candidate.bio_sighting_id
        RETURNING s.bio_sighting_id, s.bio_species_id, s.bio_site_id, s.bio_field_notes, s.bio_embedding_attempts
    )
    SELECT u.bio_sighting_id,
           concat_ws('. ',
               'Especie: ' || sp.bio_common_name || ' (' || sp.bio_scientific_name || ')',
               'Sitio: ' || si.bio_site_name || ', ' || si.bio_region,
               'Notas de campo: ' || u.bio_field_notes
           ) AS field_notes,
           u.bio_embedding_attempts
    FROM updated AS u
    JOIN public.bio_species AS sp ON sp.bio_species_id = u.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = u.bio_site_id;
END;
$$;

-- Reset existing sightings to pending so the worker re-indexes all records with enriched context
UPDATE public.bio_sightings
SET bio_embedding_status = 'pending',
    bio_embedding_attempts = 0
WHERE bio_is_voided = false;

RESET ROLE;