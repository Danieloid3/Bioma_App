-- Preserve the one edit timestamp explicitly present in the original corpus.
SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_trg_fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF current_setting('app.preserve_updated_at', true) IS DISTINCT FROM 'true' THEN
        NEW.bio_updated_at := now();
    END IF;
    RETURN NEW;
END;
$$;

RESET ROLE;

SELECT set_config('app.preserve_updated_at', 'true', true);
UPDATE bio_sightings
SET bio_updated_at = '2026-01-10T16:00:00Z'
WHERE bio_observation_reference = 'obs-5003';
