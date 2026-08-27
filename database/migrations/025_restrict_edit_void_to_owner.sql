-- Bioma Migration 025: Restrict edit and void procedures strictly to the owning researcher
-- Enforces that an actor cannot modify or void sightings created by other researchers.

CREATE OR REPLACE PROCEDURE bio_sp_edit_sighting(
    IN p_sighting_id UUID,
    IN p_field_notes TEXT DEFAULT NULL,
    IN p_classification_level SMALLINT DEFAULT NULL,
    IN p_latitude NUMERIC(9, 6) DEFAULT NULL,
    IN p_longitude NUMERIC(10, 6) DEFAULT NULL,
    IN p_change_reason TEXT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_change_reason, ''))) = 0 THEN
        RAISE EXCEPTION 'a change reason is required' USING ERRCODE = '22023';
    END IF;
    IF p_classification_level IS NOT NULL AND p_classification_level NOT BETWEEN 1 AND 3 THEN
        RAISE EXCEPTION 'invalid classification level' USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('app.change_reason', p_change_reason, true);

    UPDATE public.bio_sightings
    SET bio_field_notes = COALESCE(p_field_notes, bio_field_notes),
        bio_classification_level = COALESCE(p_classification_level, bio_classification_level),
        bio_exact_latitude = COALESCE(p_latitude, bio_exact_latitude),
        bio_exact_longitude = COALESCE(p_longitude, bio_exact_longitude)
    WHERE bio_sighting_id = p_sighting_id
      AND bio_researcher_id = v_actor_id
      AND bio_is_voided = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'sighting not found, voided, or not owned by actor' USING ERRCODE = 'P0004';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE bio_sp_void_sighting(
    IN p_sighting_id UUID,
    IN p_void_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_void_reason, ''))) = 0 THEN
        RAISE EXCEPTION 'a void reason is required' USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('app.change_reason', p_void_reason, true);

    UPDATE public.bio_sightings
    SET bio_is_voided = true,
        bio_voided_at = now(),
        bio_voided_by_researcher_id = v_actor_id,
        bio_void_reason = p_void_reason
    WHERE bio_sighting_id = p_sighting_id
      AND bio_researcher_id = v_actor_id
      AND bio_is_voided = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'sighting not found, already voided, or not owned by actor' USING ERRCODE = 'P0005';
    END IF;
END;
$$;