SET ROLE bio_owner;

CREATE FUNCTION bio_fn_register_sighting(
    p_observation_reference VARCHAR(30),
    p_species_id UUID,
    p_site_id UUID,
    p_observed_at TIMESTAMPTZ,
    p_latitude NUMERIC(9, 6),
    p_longitude NUMERIC(10, 6),
    p_classification_level SMALLINT,
    p_field_notes TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    v_sighting_id UUID;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001';
    END IF;
    IF p_observation_reference !~ '^obs-[A-Za-z0-9-]+$' THEN
        RAISE EXCEPTION 'invalid observation reference' USING ERRCODE = '22023';
    END IF;
    IF p_observed_at IS NULL OR p_latitude IS NULL OR p_longitude IS NULL OR p_classification_level NOT BETWEEN 1 AND 3 OR length(btrim(coalesce(p_field_notes, ''))) = 0 THEN
        RAISE EXCEPTION 'invalid sighting payload' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.bio_species WHERE bio_species_id = p_species_id) THEN
        RAISE EXCEPTION 'species not found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.bio_sites WHERE bio_site_id = p_site_id) THEN
        RAISE EXCEPTION 'site not found' USING ERRCODE = 'P0003';
    END IF;

    INSERT INTO public.bio_sightings (
        bio_observation_reference, bio_researcher_id, bio_species_id, bio_site_id,
        bio_observed_at, bio_exact_latitude, bio_exact_longitude,
        bio_classification_level, bio_field_notes
    ) VALUES (
        p_observation_reference, v_actor_id, p_species_id, p_site_id,
        p_observed_at, p_latitude, p_longitude, p_classification_level, p_field_notes
    ) RETURNING bio_sighting_id INTO v_sighting_id;

    RETURN v_sighting_id;
END;
$$;

CREATE PROCEDURE bio_sp_list_researchers(
    INOUT p_cursor REFCURSOR,
    IN p_accreditation_level SMALLINT DEFAULT NULL,
    IN p_is_active BOOLEAN DEFAULT true,
    IN p_search_term TEXT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    OPEN p_cursor FOR
        SELECT bio_researcher_id, bio_full_name, bio_email, bio_role_title,
               bio_accreditation_level, bio_is_active, bio_created_at
        FROM public.bio_researchers
        WHERE (p_accreditation_level IS NULL OR bio_accreditation_level = p_accreditation_level)
          AND (p_is_active IS NULL OR bio_is_active = p_is_active)
          AND (p_search_term IS NULL OR bio_full_name ILIKE '%' || p_search_term || '%' OR bio_email ILIKE '%' || p_search_term || '%')
        ORDER BY bio_full_name, bio_researcher_id;
END;
$$;

CREATE PROCEDURE bio_sp_edit_sighting(
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
BEGIN
    IF NULLIF(current_setting('app.current_user_id', true), '') IS NULL THEN
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
      AND bio_is_voided = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sighting not found, voided, or not owned by actor' USING ERRCODE = 'P0004';
    END IF;
END;
$$;

CREATE PROCEDURE bio_sp_void_sighting(
    IN p_sighting_id UUID,
    IN p_void_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NULLIF(current_setting('app.current_user_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_void_reason, ''))) = 0 THEN
        RAISE EXCEPTION 'a void reason is required' USING ERRCODE = '22023';
    END IF;
    PERFORM set_config('app.change_reason', p_void_reason, true);
    UPDATE public.bio_sightings
    SET bio_is_voided = true,
        bio_voided_at = now(),
        bio_voided_by_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID,
        bio_void_reason = p_void_reason
    WHERE bio_sighting_id = p_sighting_id
      AND bio_is_voided = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sighting not found, already voided, or not owned by actor' USING ERRCODE = 'P0005';
    END IF;
END;
$$;

CREATE FUNCTION bio_fn_sighting_history(
    p_species_id UUID DEFAULT NULL,
    p_site_id UUID DEFAULT NULL,
    p_cursor_observed_at TIMESTAMPTZ DEFAULT NULL,
    p_cursor_sighting_id UUID DEFAULT NULL,
    p_page_size INTEGER DEFAULT 20,
    p_include_voided BOOLEAN DEFAULT false
) RETURNS TABLE (
    sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR,
    species_common_name VARCHAR, species_scientific_name VARCHAR,
    site_name VARCHAR, region VARCHAR, classification_level SMALLINT,
    field_notes TEXT, is_voided BOOLEAN, observed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_page_size NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'page size must be between 1 and 100' USING ERRCODE = '22023';
    END IF;
    IF (p_cursor_observed_at IS NULL) <> (p_cursor_sighting_id IS NULL) THEN
        RAISE EXCEPTION 'both cursor values are required together' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name,
           sp.bio_common_name, sp.bio_scientific_name, si.bio_site_name, si.bio_region,
           s.bio_classification_level, s.bio_field_notes, s.bio_is_voided,
           s.bio_observed_at, s.bio_created_at, s.bio_updated_at
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = s.bio_site_id
    WHERE (p_species_id IS NULL OR s.bio_species_id = p_species_id)
      AND (p_site_id IS NULL OR s.bio_site_id = p_site_id)
      AND (p_include_voided OR s.bio_is_voided = false)
      AND (p_cursor_observed_at IS NULL OR (s.bio_observed_at, s.bio_sighting_id) < (p_cursor_observed_at, p_cursor_sighting_id))
    ORDER BY s.bio_observed_at DESC, s.bio_sighting_id DESC
    LIMIT p_page_size;
END;
$$;

CREATE FUNCTION bio_fn_search_field_notes(
    p_search_term TEXT,
    p_cursor_observed_at TIMESTAMPTZ DEFAULT NULL,
    p_cursor_sighting_id UUID DEFAULT NULL,
    p_page_size INTEGER DEFAULT 20
) RETURNS TABLE (
    sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR,
    species_common_name VARCHAR, site_name VARCHAR, field_notes_highlight TEXT,
    classification_level SMALLINT, observed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF length(btrim(coalesce(p_search_term, ''))) = 0 OR p_page_size NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'search term and page size are invalid' USING ERRCODE = '22023';
    END IF;
    IF (p_cursor_observed_at IS NULL) <> (p_cursor_sighting_id IS NULL) THEN
        RAISE EXCEPTION 'both cursor values are required together' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name,
           sp.bio_common_name, si.bio_site_name,
           ts_headline('spanish', s.bio_field_notes, websearch_to_tsquery('spanish', p_search_term),
               'StartSel=<mark>, StopSel=</mark>, MaxWords=50, MinWords=20'),
           s.bio_classification_level, s.bio_observed_at
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = s.bio_site_id
    WHERE s.bio_is_voided = false
      AND to_tsvector('spanish', s.bio_field_notes) @@ websearch_to_tsquery('spanish', p_search_term)
      AND (p_cursor_observed_at IS NULL OR (s.bio_observed_at, s.bio_sighting_id) < (p_cursor_observed_at, p_cursor_sighting_id))
    ORDER BY s.bio_observed_at DESC, s.bio_sighting_id DESC
    LIMIT p_page_size;
END;
$$;

CREATE FUNCTION bio_fn_retrieve_copilot_context(
    p_query_embedding VECTOR(1536),
    p_limit INTEGER DEFAULT 5
) RETURNS TABLE (
    sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR,
    species_common_name VARCHAR, species_scientific_name VARCHAR,
    site_name VARCHAR, region VARCHAR, field_notes TEXT,
    classification_level SMALLINT, similarity DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_limit NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION 'context limit must be between 1 and 20' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name,
           sp.bio_common_name, sp.bio_scientific_name, si.bio_site_name, si.bio_region,
           s.bio_field_notes, s.bio_classification_level,
           1 - (s.bio_field_notes_embedding <=> p_query_embedding)
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = s.bio_site_id
    WHERE s.bio_is_voided = false
      AND s.bio_field_notes_embedding IS NOT NULL
    ORDER BY s.bio_field_notes_embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$;

CREATE FUNCTION bio_fn_store_sighting_embedding(
    p_sighting_id UUID,
    p_embedding VECTOR(1536),
    p_embedding_model VARCHAR(100)
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_embedding IS NULL OR length(btrim(coalesce(p_embedding_model, ''))) = 0 THEN
        RAISE EXCEPTION 'embedding and model are required' USING ERRCODE = '22023';
    END IF;
    UPDATE public.bio_sightings
    SET bio_field_notes_embedding = p_embedding,
        bio_embedding_status = 'ready',
        bio_embedding_model = p_embedding_model,
        bio_embedded_at = now()
    WHERE bio_sighting_id = p_sighting_id
      AND bio_is_voided = false;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sighting not found or not visible to actor' USING ERRCODE = 'P0006';
    END IF;
END;
$$;

CREATE FUNCTION bio_fn_get_researcher_for_login(p_email CITEXT)
RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, email CITEXT, password_hash VARCHAR,
    role_title VARCHAR, accreditation_level SMALLINT, is_active BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_email, r.bio_password_hash,
           r.bio_role_title, r.bio_accreditation_level, r.bio_is_active
    FROM public.bio_researchers AS r
    WHERE r.bio_email = p_email;
$$;

CREATE FUNCTION bio_fn_create_refresh_token(
    p_researcher_id UUID,
    p_token_hash VARCHAR(255),
    p_token_family_id UUID,
    p_expires_at TIMESTAMPTZ,
    p_parent_refresh_token_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_refresh_token_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.bio_researchers WHERE bio_researcher_id = p_researcher_id AND bio_is_active) THEN
        RAISE EXCEPTION 'active researcher not found' USING ERRCODE = 'P0007';
    END IF;
    INSERT INTO public.bio_refresh_tokens (
        bio_researcher_id, bio_token_hash, bio_token_family_id,
        bio_expires_at, bio_parent_refresh_token_id
    ) VALUES (
        p_researcher_id, p_token_hash, p_token_family_id,
        p_expires_at, p_parent_refresh_token_id
    ) RETURNING bio_refresh_token_id INTO v_refresh_token_id;
    RETURN v_refresh_token_id;
END;
$$;

CREATE FUNCTION bio_fn_rotate_refresh_token(
    p_current_token_hash VARCHAR(255),
    p_next_token_hash VARCHAR(255),
    p_next_expires_at TIMESTAMPTZ
) RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, role_title VARCHAR, accreditation_level SMALLINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_token public.bio_refresh_tokens%ROWTYPE;
BEGIN
    SELECT * INTO v_token
    FROM public.bio_refresh_tokens
    WHERE bio_token_hash = p_current_token_hash
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'refresh token is invalid' USING ERRCODE = 'P0008';
    END IF;
    IF v_token.bio_used_at IS NOT NULL OR v_token.bio_revoked_at IS NOT NULL OR v_token.bio_expires_at <= now() THEN
        UPDATE public.bio_refresh_tokens
        SET bio_revoked_at = COALESCE(bio_revoked_at, now()),
            bio_revocation_reason = COALESCE(bio_revocation_reason, 'reuse_detected')
        WHERE bio_token_family_id = v_token.bio_token_family_id
          AND bio_revoked_at IS NULL;
        RAISE EXCEPTION 'refresh token reuse or expiry detected' USING ERRCODE = 'P0009';
    END IF;
    UPDATE public.bio_refresh_tokens
    SET bio_used_at = now(), bio_revoked_at = now(), bio_revocation_reason = 'rotated'
    WHERE bio_refresh_token_id = v_token.bio_refresh_token_id;
    PERFORM public.bio_fn_create_refresh_token(
        v_token.bio_researcher_id, p_next_token_hash, v_token.bio_token_family_id,
        p_next_expires_at, v_token.bio_refresh_token_id
    );
    RETURN QUERY
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title, r.bio_accreditation_level
    FROM public.bio_researchers AS r
    WHERE r.bio_researcher_id = v_token.bio_researcher_id AND r.bio_is_active;
END;
$$;

CREATE FUNCTION bio_fn_revoke_refresh_token_family(
    p_token_hash VARCHAR(255),
    p_reason VARCHAR(40) DEFAULT 'logout'
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    UPDATE public.bio_refresh_tokens
    SET bio_revoked_at = now(), bio_revocation_reason = p_reason
    WHERE bio_token_family_id = (
        SELECT bio_token_family_id FROM public.bio_refresh_tokens WHERE bio_token_hash = p_token_hash
    )
      AND bio_revoked_at IS NULL;
END;
$$;

CREATE FUNCTION bio_fn_log_copilot_usage(
    p_prompt_text TEXT,
    p_response_text TEXT,
    p_system_prompt_version VARCHAR(40),
    p_model_name VARCHAR(100),
    p_input_tokens INTEGER,
    p_output_tokens INTEGER,
    p_sighting_ids UUID[] DEFAULT ARRAY[]::UUID[],
    p_similarities NUMERIC[] DEFAULT ARRAY[]::NUMERIC[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    v_usage_id UUID;
    v_index INTEGER;
BEGIN
    IF v_actor_id IS NULL OR cardinality(p_sighting_ids) <> cardinality(p_similarities) THEN
        RAISE EXCEPTION 'invalid copilot audit payload' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(p_sighting_ids) AS requested(bio_sighting_id)
        LEFT JOIN public.bio_sightings AS visible_sighting ON visible_sighting.bio_sighting_id = requested.bio_sighting_id
        WHERE visible_sighting.bio_sighting_id IS NULL
    ) THEN
        RAISE EXCEPTION 'copilot citations contain a sighting unavailable to actor' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.bio_copilot_usage (
        bio_researcher_id, bio_prompt_text, bio_response_text, bio_system_prompt_version,
        bio_model_name, bio_input_tokens, bio_output_tokens
    ) VALUES (
        v_actor_id, p_prompt_text, p_response_text, p_system_prompt_version,
        p_model_name, p_input_tokens, p_output_tokens
    ) RETURNING bio_copilot_usage_id INTO v_usage_id;
    FOR v_index IN 1..COALESCE(cardinality(p_sighting_ids), 0) LOOP
        INSERT INTO public.bio_copilot_citations (
            bio_copilot_usage_id, bio_sighting_id, bio_rank, bio_similarity
        ) VALUES (v_usage_id, p_sighting_ids[v_index], v_index, p_similarities[v_index]);
    END LOOP;
    RETURN v_usage_id;
END;
$$;

CREATE FUNCTION bio_fn_copilot_usage_summary()
RETURNS TABLE (researcher_id UUID, total_queries BIGINT, total_tokens BIGINT, last_query_at TIMESTAMPTZ)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT cu.bio_researcher_id,
           COUNT(*)::BIGINT,
           SUM(cu.bio_input_tokens + cu.bio_output_tokens)::BIGINT,
           MAX(cu.bio_created_at)
    FROM public.bio_copilot_usage AS cu
    GROUP BY cu.bio_researcher_id;
$$;

REVOKE ALL ON TABLE public.bio_researchers, public.bio_species, public.bio_sites,
    public.bio_sightings, public.bio_sighting_revisions, public.bio_refresh_tokens,
    public.bio_copilot_usage, public.bio_copilot_citations FROM bio_app_user;
GRANT SELECT ON public.bio_sightings, public.bio_species, public.bio_sites, public.bio_copilot_usage TO bio_app_user;
GRANT SELECT (bio_researcher_id, bio_full_name, bio_email, bio_role_title, bio_accreditation_level, bio_is_active, bio_created_at, bio_updated_at)
    ON public.bio_researchers TO bio_app_user;
GRANT SELECT ON public.bio_v_visible_sightings TO bio_app_user;

REVOKE EXECUTE ON FUNCTION bio_fn_register_sighting(VARCHAR, UUID, UUID, TIMESTAMPTZ, NUMERIC, NUMERIC, SMALLINT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_sighting_history(UUID, UUID, TIMESTAMPTZ, UUID, INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_search_field_notes(TEXT, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_retrieve_copilot_context(VECTOR, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_store_sighting_embedding(UUID, VECTOR, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_get_researcher_for_login(CITEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_create_refresh_token(UUID, VARCHAR, UUID, TIMESTAMPTZ, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_revoke_refresh_token_family(VARCHAR, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_log_copilot_usage(TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_copilot_usage_summary() FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE bio_sp_list_researchers(REFCURSOR, SMALLINT, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE bio_sp_edit_sighting(UUID, TEXT, SMALLINT, NUMERIC, NUMERIC, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE bio_sp_void_sighting(UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION bio_fn_register_sighting(VARCHAR, UUID, UUID, TIMESTAMPTZ, NUMERIC, NUMERIC, SMALLINT, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_sighting_history(UUID, UUID, TIMESTAMPTZ, UUID, INTEGER, BOOLEAN) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_search_field_notes(TEXT, TIMESTAMPTZ, UUID, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_retrieve_copilot_context(VECTOR, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_store_sighting_embedding(UUID, VECTOR, VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_researcher_for_login(CITEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_refresh_token(UUID, VARCHAR, UUID, TIMESTAMPTZ, UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_revoke_refresh_token_family(VARCHAR, VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_log_copilot_usage(TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_copilot_usage_summary() TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_list_researchers(REFCURSOR, SMALLINT, BOOLEAN, TEXT) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_edit_sighting(UUID, TEXT, SMALLINT, NUMERIC, NUMERIC, TEXT) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_void_sighting(UUID, TEXT) TO bio_app_user;

RESET ROLE;
