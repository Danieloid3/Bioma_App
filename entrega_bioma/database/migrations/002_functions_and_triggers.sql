-- 002_functions_and_triggers.sql
SET ROLE bio_owner;

CREATE OR REPLACE VIEW bio_v_visible_sightings WITH (security_invoker = true, security_barrier = true) AS
SELECT s.bio_sighting_id, s.bio_observation_reference, s.bio_researcher_id, r.bio_full_name AS bio_researcher_name,
       s.bio_species_id, sp.bio_common_name AS bio_species_common_name, sp.bio_scientific_name AS bio_species_scientific_name,
       sp.bio_iucn_category, s.bio_site_id, si.bio_site_name, si.bio_region, s.bio_observed_at,
       s.bio_exact_latitude, s.bio_exact_longitude, s.bio_classification_level, s.bio_field_notes,
       s.bio_embedding_status, s.bio_is_voided, s.bio_voided_at, s.bio_created_at, s.bio_updated_at
FROM bio_sightings AS s
JOIN bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
JOIN bio_species AS sp ON sp.bio_species_id = s.bio_species_id
JOIN bio_sites AS si ON si.bio_site_id = s.bio_site_id;

CREATE OR REPLACE VIEW bio_v_my_chat_conversations WITH (security_invoker = true) AS
SELECT c.bio_chat_channel_id AS channel_id, c.bio_channel_type, c.bio_name, c.bio_created_at, c.bio_updated_at,
       count(m.bio_chat_message_id) FILTER (WHERE NOT m.bio_is_deleted) AS message_count, max(m.bio_created_at) AS last_message_at
FROM bio_chat_channels c
JOIN bio_chat_channel_members mine ON mine.bio_chat_channel_id = c.bio_chat_channel_id AND mine.bio_left_at IS NULL
LEFT JOIN bio_chat_messages m ON m.bio_chat_channel_id = c.bio_chat_channel_id
GROUP BY c.bio_chat_channel_id, c.bio_channel_type, c.bio_name, c.bio_created_at, c.bio_updated_at;

GRANT SELECT ON public.bio_v_visible_sightings TO bio_app_user;
GRANT SELECT ON public.bio_v_my_chat_conversations TO bio_app_user;

CREATE OR REPLACE FUNCTION bio_fn_register_sighting(p_observation_reference VARCHAR(30), p_species_id UUID, p_site_id UUID, p_observed_at TIMESTAMPTZ, p_latitude NUMERIC(9, 6), p_longitude NUMERIC(10, 6), p_classification_level SMALLINT, p_field_notes TEXT) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID; v_sighting_id UUID;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001'; END IF;
    IF p_observation_reference !~ '^obs-[A-Za-z0-9-]+$' THEN RAISE EXCEPTION 'invalid observation reference' USING ERRCODE = '22023'; END IF;
    IF p_observed_at IS NULL OR p_latitude IS NULL OR p_longitude IS NULL OR p_classification_level NOT BETWEEN 1 AND 3 OR length(btrim(coalesce(p_field_notes, ''))) = 0 THEN RAISE EXCEPTION 'invalid sighting payload' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.bio_species WHERE bio_species_id = p_species_id) THEN RAISE EXCEPTION 'species not found' USING ERRCODE = 'P0002'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.bio_sites WHERE bio_site_id = p_site_id) THEN RAISE EXCEPTION 'site not found' USING ERRCODE = 'P0003'; END IF;
    INSERT INTO public.bio_sightings (bio_observation_reference, bio_researcher_id, bio_species_id, bio_site_id, bio_observed_at, bio_exact_latitude, bio_exact_longitude, bio_classification_level, bio_field_notes) VALUES (p_observation_reference, v_actor_id, p_species_id, p_site_id, p_observed_at, p_latitude, p_longitude, p_classification_level, p_field_notes) RETURNING bio_sighting_id INTO v_sighting_id;
    RETURN v_sighting_id;
END;
$$;

CREATE OR REPLACE PROCEDURE bio_sp_edit_sighting(IN p_sighting_id UUID, IN p_field_notes TEXT DEFAULT NULL, IN p_classification_level SMALLINT DEFAULT NULL, IN p_latitude NUMERIC(9, 6) DEFAULT NULL, IN p_longitude NUMERIC(10, 6) DEFAULT NULL, IN p_change_reason TEXT DEFAULT NULL) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001'; END IF;
    IF length(btrim(coalesce(p_change_reason, ''))) = 0 THEN RAISE EXCEPTION 'a change reason is required' USING ERRCODE = '22023'; END IF;
    IF p_classification_level IS NOT NULL AND p_classification_level NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'invalid classification level' USING ERRCODE = '22023'; END IF;
    PERFORM set_config('app.change_reason', p_change_reason, true);
    UPDATE public.bio_sightings SET bio_field_notes = COALESCE(p_field_notes, bio_field_notes), bio_classification_level = COALESCE(p_classification_level, bio_classification_level), bio_exact_latitude = COALESCE(p_latitude, bio_exact_latitude), bio_exact_longitude = COALESCE(p_longitude, bio_exact_longitude) WHERE bio_sighting_id = p_sighting_id AND bio_researcher_id = v_actor_id AND bio_is_voided = false;
    IF NOT FOUND THEN RAISE EXCEPTION 'sighting not found, voided, or not owned by actor' USING ERRCODE = 'P0004'; END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE bio_sp_void_sighting(IN p_sighting_id UUID, IN p_void_reason TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001'; END IF;
    IF length(btrim(coalesce(p_void_reason, ''))) = 0 THEN RAISE EXCEPTION 'a void reason is required' USING ERRCODE = '22023'; END IF;
    PERFORM set_config('app.change_reason', p_void_reason, true);
    UPDATE public.bio_sightings SET bio_is_voided = true, bio_voided_at = now(), bio_voided_by_researcher_id = v_actor_id, bio_void_reason = p_void_reason WHERE bio_sighting_id = p_sighting_id AND bio_researcher_id = v_actor_id AND bio_is_voided = false;
    IF NOT FOUND THEN RAISE EXCEPTION 'sighting not found, already voided, or not owned by actor' USING ERRCODE = 'P0005'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_sighting_history_with_images(p_species_id UUID DEFAULT NULL, p_site_id UUID DEFAULT NULL, p_cursor_observed_at TIMESTAMPTZ DEFAULT NULL, p_cursor_sighting_id UUID DEFAULT NULL, p_page_size INTEGER DEFAULT 20, p_include_voided BOOLEAN DEFAULT false) RETURNS TABLE (sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR, species_common_name VARCHAR, site_name VARCHAR, classification_level SMALLINT, field_notes TEXT, is_voided BOOLEAN, observed_at TIMESTAMPTZ, image_url TEXT, image_alt_text_es VARCHAR) LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
BEGIN
    IF p_page_size NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'page size must be between 1 and 100' USING ERRCODE = '22023'; END IF;
    IF (p_cursor_observed_at IS NULL) <> (p_cursor_sighting_id IS NULL) THEN RAISE EXCEPTION 'both cursor values are required together' USING ERRCODE = '22023'; END IF;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name, sp.bio_common_name, site.bio_site_name, s.bio_classification_level, s.bio_field_notes, s.bio_is_voided, s.bio_observed_at, image.bio_display_url, image.bio_alt_text_es
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS site ON site.bio_site_id = s.bio_site_id
    LEFT JOIN public.bio_species_images AS image ON image.bio_species_id = sp.bio_species_id AND image.bio_is_featured = true AND image.bio_is_active = true
    WHERE (p_species_id IS NULL OR s.bio_species_id = p_species_id) AND (p_site_id IS NULL OR s.bio_site_id = p_site_id) AND (p_include_voided OR s.bio_is_voided = false) AND (p_cursor_observed_at IS NULL OR (s.bio_observed_at, s.bio_sighting_id) < (p_cursor_observed_at, p_cursor_sighting_id))
    ORDER BY s.bio_observed_at DESC, s.bio_sighting_id DESC LIMIT p_page_size;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_get_sighting_detail(p_sighting_id UUID) RETURNS TABLE (sighting_id UUID, observation_reference VARCHAR, researcher_id UUID, researcher_name VARCHAR, species_id UUID, species_common_name VARCHAR, species_scientific_name VARCHAR, species_iucn_category VARCHAR, site_id UUID, site_name VARCHAR, region VARCHAR, observed_at TIMESTAMPTZ, exact_latitude NUMERIC(9, 6), exact_longitude NUMERIC(10, 6), classification_level SMALLINT, field_notes TEXT, is_voided BOOLEAN, voided_at TIMESTAMPTZ, voided_by_researcher_id UUID, void_reason TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, image_url TEXT, image_alt_text_es VARCHAR, image_attribution TEXT, image_license_code VARCHAR, image_license_url TEXT) LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
    SELECT s.bio_sighting_id, s.bio_observation_reference, author.bio_researcher_id, author.bio_full_name, species.bio_species_id, species.bio_common_name, species.bio_scientific_name, species.bio_iucn_category, site.bio_site_id, site.bio_site_name, site.bio_region, s.bio_observed_at, s.bio_exact_latitude, s.bio_exact_longitude, s.bio_classification_level, s.bio_field_notes, s.bio_is_voided, s.bio_voided_at, s.bio_voided_by_researcher_id, s.bio_void_reason, s.bio_created_at, s.bio_updated_at, image.bio_display_url, image.bio_alt_text_es, image.bio_attribution, image.bio_license_code, image.bio_license_url
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS author ON author.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS species ON species.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS site ON site.bio_site_id = s.bio_site_id
    LEFT JOIN public.bio_species_images AS image ON image.bio_species_id = species.bio_species_id AND image.bio_is_featured = true AND image.bio_is_active = true
    WHERE s.bio_sighting_id = p_sighting_id;
$$;

CREATE OR REPLACE FUNCTION bio_fn_search_field_notes(p_search_term TEXT, p_cursor_observed_at TIMESTAMPTZ DEFAULT NULL, p_cursor_sighting_id UUID DEFAULT NULL, p_page_size INTEGER DEFAULT 20) RETURNS TABLE (sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR, species_common_name VARCHAR, site_name VARCHAR, field_notes_highlight TEXT, classification_level SMALLINT, observed_at TIMESTAMPTZ) LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
DECLARE
    v_clean_term TEXT; v_unaccent_term TEXT; v_ilike_term TEXT; v_tsquery_str TEXT; v_query TSQUERY;
BEGIN
    v_clean_term := btrim(coalesce(p_search_term, ''));
    IF length(v_clean_term) = 0 OR p_page_size NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'search term and page size are invalid' USING ERRCODE = '22023'; END IF;
    IF (p_cursor_observed_at IS NULL) <> (p_cursor_sighting_id IS NULL) THEN RAISE EXCEPTION 'both cursor values are required together' USING ERRCODE = '22023'; END IF;
    v_unaccent_term := bio_fn_immutable_unaccent(v_clean_term);
    v_ilike_term := '%' || v_unaccent_term || '%';
    BEGIN
        SELECT string_agg(quote_literal(token) || ':*', ' & ') INTO v_tsquery_str FROM unnest(string_to_array(regexp_replace(v_unaccent_term, '[^\w\s]', ' ', 'g'), ' ')) AS token WHERE length(btrim(token)) > 0;
        IF v_tsquery_str IS NOT NULL AND length(v_tsquery_str) > 0 THEN v_query := to_tsquery('spanish', v_tsquery_str); ELSE v_query := websearch_to_tsquery('spanish', v_clean_term); END IF;
    EXCEPTION WHEN OTHERS THEN
        BEGIN v_query := websearch_to_tsquery('spanish', v_clean_term); EXCEPTION WHEN OTHERS THEN v_query := NULL; END;
    END;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name, sp.bio_common_name, si.bio_site_name, CASE WHEN v_query IS NOT NULL AND to_tsvector('spanish', s.bio_field_notes) @@ v_query THEN ts_headline('spanish', s.bio_field_notes, v_query, 'StartSel=<mark>, StopSel=</mark>, MaxWords=50, MinWords=20') ELSE s.bio_field_notes END AS field_notes_highlight, s.bio_classification_level, s.bio_observed_at
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = s.bio_site_id
    WHERE s.bio_is_voided = false AND ((v_query IS NOT NULL AND (to_tsvector('spanish', coalesce(s.bio_field_notes, '') || ' ' || coalesce(sp.bio_common_name, '') || ' ' || coalesce(sp.bio_scientific_name, '') || ' ' || coalesce(si.bio_site_name, '') || ' ' || coalesce(si.bio_region, '') || ' ' || coalesce(r.bio_full_name, '')) @@ v_query)) OR bio_fn_immutable_unaccent(sp.bio_common_name) ILIKE v_ilike_term OR bio_fn_immutable_unaccent(sp.bio_scientific_name) ILIKE v_ilike_term OR bio_fn_immutable_unaccent(si.bio_site_name) ILIKE v_ilike_term OR bio_fn_immutable_unaccent(si.bio_region) ILIKE v_ilike_term OR s.bio_observation_reference ILIKE v_ilike_term OR bio_fn_immutable_unaccent(r.bio_full_name) ILIKE v_ilike_term OR bio_fn_immutable_unaccent(s.bio_field_notes) ILIKE v_ilike_term) AND (p_cursor_observed_at IS NULL OR (s.bio_observed_at, s.bio_sighting_id) < (p_cursor_observed_at, p_cursor_sighting_id))
    ORDER BY s.bio_observed_at DESC, s.bio_sighting_id DESC LIMIT p_page_size;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_retrieve_copilot_context(p_query_embedding VECTOR(1536), p_limit INTEGER DEFAULT 5) RETURNS TABLE (sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR, species_common_name VARCHAR, species_scientific_name VARCHAR, site_name VARCHAR, region VARCHAR, field_notes TEXT, classification_level SMALLINT, similarity DOUBLE PRECISION) LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
BEGIN
    IF p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'context limit must be between 1 and 20' USING ERRCODE = '22023'; END IF;
    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name, sp.bio_common_name, sp.bio_scientific_name, si.bio_site_name, si.bio_region, s.bio_field_notes, s.bio_classification_level, 1 - (s.bio_field_notes_embedding <=> p_query_embedding)
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS si ON si.bio_site_id = s.bio_site_id
    WHERE s.bio_is_voided = false AND s.bio_field_notes_embedding IS NOT NULL
    ORDER BY s.bio_field_notes_embedding <=> p_query_embedding LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_get_knowledge_catalog() RETURNS TABLE (catalog_type TEXT, common_name TEXT, scientific_name TEXT, iucn_category TEXT, ecosystem TEXT, region TEXT, description TEXT, habitat TEXT, diet TEXT, conservation_status TEXT) LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
    SELECT 'species'::TEXT AS catalog_type, sp.bio_common_name::TEXT AS common_name, sp.bio_scientific_name::TEXT AS scientific_name, sp.bio_iucn_category::TEXT AS iucn_category, NULL::TEXT AS ecosystem, NULL::TEXT AS region, sp.bio_description AS description, sp.bio_habitat AS habitat, sp.bio_diet AS diet, sp.bio_conservation_status AS conservation_status FROM public.bio_species AS sp
    UNION ALL
    SELECT 'site'::TEXT AS catalog_type, si.bio_site_name::TEXT AS common_name, NULL::TEXT AS scientific_name, NULL::TEXT AS iucn_category, si.bio_ecosystem::TEXT AS ecosystem, si.bio_region::TEXT AS region, si.bio_description AS description, NULL::TEXT AS habitat, NULL::TEXT AS diet, NULL::TEXT AS conservation_status FROM public.bio_sites AS si;
$$;

CREATE OR REPLACE FUNCTION bio_fn_claim_embedding_job(p_stale_after INTERVAL DEFAULT INTERVAL '15 minutes') RETURNS TABLE (sighting_id UUID, field_notes TEXT, embedding_attempts INTEGER) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
    RETURN QUERY
    WITH candidate AS (
        SELECT s.bio_sighting_id FROM public.bio_sightings AS s
        WHERE s.bio_is_voided = false AND (s.bio_embedding_status = 'pending' OR (s.bio_embedding_status = 'failed' AND s.bio_embedding_attempts < 5) OR (s.bio_embedding_status = 'processing' AND s.bio_updated_at < now() - p_stale_after))
        ORDER BY s.bio_updated_at, s.bio_sighting_id FOR UPDATE SKIP LOCKED LIMIT 1
    ), updated AS (
        UPDATE public.bio_sightings AS s SET bio_embedding_status = 'processing', bio_embedding_attempts = s.bio_embedding_attempts + 1, bio_embedding_error = NULL, bio_updated_at = now()
        FROM candidate WHERE s.bio_sighting_id = candidate.bio_sighting_id RETURNING s.bio_sighting_id, s.bio_species_id, s.bio_site_id, s.bio_field_notes, s.bio_embedding_attempts
    )
    SELECT u.bio_sighting_id, concat_ws('. ', 'Especie: ' || sp.bio_common_name || ' (' || sp.bio_scientific_name || ')', 'Sitio: ' || si.bio_site_name || ', ' || si.bio_region, 'Notas de campo: ' || u.bio_field_notes) AS field_notes, u.bio_embedding_attempts
    FROM updated AS u JOIN public.bio_species AS sp ON sp.bio_species_id = u.bio_species_id JOIN public.bio_sites AS si ON si.bio_site_id = u.bio_site_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_store_sighting_embedding(p_sighting_id UUID, p_embedding VECTOR(1536), p_embedding_model VARCHAR(100)) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
    IF p_embedding IS NULL OR length(btrim(coalesce(p_embedding_model, ''))) = 0 THEN RAISE EXCEPTION 'embedding and model are required' USING ERRCODE = '22023'; END IF;
    UPDATE public.bio_sightings SET bio_field_notes_embedding = p_embedding, bio_embedding_status = 'ready', bio_embedding_model = p_embedding_model, bio_embedded_at = now() WHERE bio_sighting_id = p_sighting_id AND bio_is_voided = false;
    IF NOT FOUND THEN RAISE EXCEPTION 'sighting not found or not visible to actor' USING ERRCODE = 'P0006'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_mark_embedding_failed(p_sighting_id UUID, p_error TEXT) RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
    UPDATE public.bio_sightings SET bio_embedding_status = 'failed', bio_embedding_error = left(coalesce(p_error, 'unknown embedding error'), 1000), bio_updated_at = now() WHERE bio_sighting_id = p_sighting_id AND bio_is_voided = false AND bio_embedding_status = 'processing';
$$;

CREATE OR REPLACE FUNCTION bio_fn_create_chat_channel(p_channel_type VARCHAR, p_name VARCHAR DEFAULT NULL, p_member_ids UUID[] DEFAULT ARRAY[]::UUID[]) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::uuid; v_channel UUID; v_members UUID[];
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'authentication required' USING ERRCODE='P0001'; END IF;
  IF p_channel_type NOT IN ('direct','group') THEN RAISE EXCEPTION 'invalid channel type' USING ERRCODE='22023'; END IF;
  v_members := ARRAY(SELECT DISTINCT unnest(array_append(coalesce(p_member_ids, ARRAY[]::UUID[]), v_actor)));
  IF cardinality(v_members) < 2 THEN RAISE EXCEPTION 'a channel requires at least two members' USING ERRCODE='22023'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_members) id LEFT JOIN bio_researchers r ON r.bio_researcher_id=id WHERE r.bio_researcher_id IS NULL OR NOT r.bio_is_active) THEN RAISE EXCEPTION 'all members must be active researchers' USING ERRCODE='22023'; END IF;
  IF p_channel_type='direct' AND cardinality(v_members) <> 2 THEN RAISE EXCEPTION 'a direct channel requires exactly two members' USING ERRCODE='22023'; END IF;
  IF p_channel_type='direct' THEN
    SELECT c.bio_chat_channel_id INTO v_channel FROM bio_chat_channels c JOIN bio_chat_channel_members m ON m.bio_chat_channel_id = c.bio_chat_channel_id AND m.bio_left_at IS NULL WHERE c.bio_channel_type = 'direct' AND c.bio_is_active GROUP BY c.bio_chat_channel_id HAVING array_agg(m.bio_researcher_id ORDER BY m.bio_researcher_id) = (SELECT array_agg(id ORDER BY id) FROM unnest(v_members) id);
    IF v_channel IS NOT NULL THEN RETURN v_channel; END IF;
  END IF;
  INSERT INTO bio_chat_channels (bio_created_by_researcher_id,bio_channel_type,bio_name) VALUES(v_actor,p_channel_type,CASE WHEN p_channel_type='group' THEN nullif(btrim(p_name),'') ELSE NULL END) RETURNING bio_chat_channel_id INTO v_channel;
  INSERT INTO bio_chat_channel_members (bio_chat_channel_id,bio_researcher_id,bio_member_role) SELECT v_channel,id,CASE WHEN id=v_actor THEN 'owner' ELSE 'member' END FROM unnest(v_members) id;
  RETURN v_channel;
END; $$;

CREATE OR REPLACE FUNCTION bio_fn_send_chat_message(p_channel_id UUID, p_message_text TEXT) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::uuid; v_message UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM bio_chat_channel_members WHERE bio_chat_channel_id=p_channel_id AND bio_researcher_id=v_actor AND bio_left_at IS NULL) THEN RAISE EXCEPTION 'channel not found' USING ERRCODE='P0004'; END IF;
  INSERT INTO bio_chat_messages(bio_chat_channel_id,bio_author_researcher_id,bio_message_text) VALUES(p_channel_id,v_actor,btrim(p_message_text)) RETURNING bio_chat_message_id INTO v_message;
  INSERT INTO bio_chat_message_receipts(bio_chat_message_id,bio_researcher_id,bio_read_at) SELECT v_message,bio_researcher_id,CASE WHEN bio_researcher_id=v_actor THEN now() ELSE NULL END FROM bio_chat_channel_members WHERE bio_chat_channel_id=p_channel_id AND bio_left_at IS NULL;
  RETURN v_message;
END; $$;

CREATE OR REPLACE FUNCTION bio_fn_edit_chat_message(p_message_id UUID, p_message_text TEXT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::uuid; BEGIN UPDATE bio_chat_messages SET bio_message_text=btrim(p_message_text),bio_is_edited=true WHERE bio_chat_message_id=p_message_id AND bio_author_researcher_id=v_actor AND NOT bio_is_deleted; IF NOT FOUND THEN RAISE EXCEPTION 'message not found or cannot be edited' USING ERRCODE='P0004'; END IF; END; $$;

CREATE OR REPLACE FUNCTION bio_fn_delete_chat_message(p_message_id UUID) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::uuid; BEGIN UPDATE bio_chat_messages SET bio_is_deleted=true,bio_deleted_at=now(),bio_deleted_by_researcher_id=v_actor WHERE bio_chat_message_id=p_message_id AND bio_author_researcher_id=v_actor AND NOT bio_is_deleted; IF NOT FOUND THEN RAISE EXCEPTION 'message not found or cannot be deleted' USING ERRCODE='P0004'; END IF; END; $$;

CREATE OR REPLACE FUNCTION bio_fn_retrieve_chat_shared_sighting_context(p_channel_id UUID, p_query_embedding VECTOR(1536), p_limit INTEGER DEFAULT 5) RETURNS TABLE (sighting_id UUID, observation_reference VARCHAR, species_common_name VARCHAR, field_notes TEXT, site_name VARCHAR, region VARCHAR, similarity NUMERIC) LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
    SELECT s.bio_sighting_id, s.bio_observation_reference, sp.bio_common_name, s.bio_field_notes, si.bio_site_name, si.bio_region, (1 - (s.bio_field_notes_embedding <=> p_query_embedding))::NUMERIC
    FROM public.bio_sightings s
    JOIN public.bio_species sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites si ON si.bio_site_id = s.bio_site_id
    WHERE s.bio_is_voided = false AND s.bio_field_notes_embedding IS NOT NULL AND bio_fn_is_chat_member(p_channel_id) AND NOT EXISTS (SELECT 1 FROM public.bio_chat_channel_members member JOIN public.bio_researchers researcher ON researcher.bio_researcher_id = member.bio_researcher_id WHERE member.bio_chat_channel_id = p_channel_id AND member.bio_left_at IS NULL AND researcher.bio_is_active AND s.bio_classification_level > researcher.bio_accreditation_level AND s.bio_researcher_id <> researcher.bio_researcher_id)
    ORDER BY s.bio_field_notes_embedding <=> p_query_embedding LIMIT greatest(1, least(p_limit, 10));
$$;

CREATE OR REPLACE FUNCTION bio_fn_retrieve_chat_message_context(
    p_channel_id UUID,
    p_query_embedding VECTOR(1536),
    p_limit INTEGER DEFAULT 5
) RETURNS TABLE (
    message_id UUID,
    source_reference VARCHAR(40),
    author_name VARCHAR(150),
    message_text TEXT,
    similarity NUMERIC
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT bio_fn_is_chat_member(p_channel_id) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT m.bio_chat_message_id,
           ('msg-' || substring(m.bio_chat_message_id::text, 1, 8))::VARCHAR,
           r.bio_full_name,
           m.bio_message_text,
           round((1 - (m.bio_message_embedding <=> p_query_embedding))::NUMERIC, 5) AS similarity
    FROM public.bio_chat_messages AS m
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = m.bio_author_researcher_id
    WHERE m.bio_chat_channel_id = p_channel_id
      AND m.bio_is_deleted = false
      AND m.bio_message_embedding IS NOT NULL
      AND (1 - (m.bio_message_embedding <=> p_query_embedding)) > 0.40
    ORDER BY m.bio_message_embedding <=> p_query_embedding
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_record_chat_copilot_response(
    p_channel_id UUID,
    p_text TEXT,
    p_sources JSONB DEFAULT '[]'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_msg_id UUID := gen_random_uuid();
    v_src JSONB;
BEGIN
    IF NOT bio_fn_is_chat_member(p_channel_id) THEN
        RAISE EXCEPTION 'unauthorized to post copilot response in channel' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.bio_chat_messages (
        bio_chat_message_id, bio_chat_channel_id, bio_author_researcher_id,
        bio_sender_role, bio_message_text
    ) VALUES (
        v_msg_id, p_channel_id, NULL, 'copilot', p_text
    );
    IF p_sources IS NOT NULL AND jsonb_array_length(p_sources) > 0 THEN
        FOR v_src IN SELECT * FROM jsonb_array_elements(p_sources) LOOP
            IF (v_src->>'sighting_id') IS NOT NULL THEN
                INSERT INTO public.bio_chat_copilot_citations (
                    bio_chat_message_id, bio_sighting_id, bio_similarity
                ) VALUES (
                    v_msg_id, (v_src->>'sighting_id')::UUID, (v_src->>'similarity')::NUMERIC
                );
            END IF;
        END LOOP;
    END IF;
    RETURN v_msg_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_chat_history(
    p_channel_id UUID,
    p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
    p_cursor_message_id UUID DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
    message_id UUID,
    channel_id UUID,
    author_id UUID,
    author_name VARCHAR,
    message_text TEXT,
    sender_role VARCHAR,
    is_edited BOOLEAN,
    is_deleted BOOLEAN,
    created_at TIMESTAMPTZ,
    read_count BIGINT,
    citations JSONB
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT bio_fn_is_chat_member(p_channel_id) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT m.bio_chat_message_id,
           m.bio_chat_channel_id,
           m.bio_author_researcher_id,
           COALESCE(r.bio_full_name, 'Copiloto Bioma')::VARCHAR,
           CASE WHEN m.bio_is_deleted THEN 'Este mensaje fue eliminado' ELSE m.bio_message_text END,
           m.bio_sender_role,
           m.bio_is_edited,
           m.bio_is_deleted,
           m.bio_created_at,
           (SELECT count(*)::BIGINT FROM bio_chat_message_receipts rec WHERE rec.bio_chat_message_id = m.bio_chat_message_id),
           COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                   'sighting_id', s.bio_sighting_id,
                   'observation_reference', s.bio_observation_reference,
                   'species_common_name', sp.bio_common_name,
                   'similarity', cit.bio_similarity
               ))
               FROM bio_chat_copilot_citations cit
               JOIN bio_sightings s ON s.bio_sighting_id = cit.bio_sighting_id
               JOIN bio_species sp ON sp.bio_species_id = s.bio_species_id
               WHERE cit.bio_chat_message_id = m.bio_chat_message_id
           ), '[]'::jsonb)
    FROM public.bio_chat_messages m
    LEFT JOIN public.bio_researchers r ON r.bio_researcher_id = m.bio_author_researcher_id
    WHERE m.bio_chat_channel_id = p_channel_id
      AND (p_cursor_created_at IS NULL OR (m.bio_created_at, m.bio_chat_message_id) < (p_cursor_created_at, p_cursor_message_id))
    ORDER BY m.bio_created_at DESC, m.bio_chat_message_id DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_claim_chat_embedding_job(
    p_stale_after INTERVAL DEFAULT INTERVAL '15 minutes'
) RETURNS TABLE (message_id UUID, message_text TEXT, embedding_attempts INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    RETURN QUERY
    WITH candidate AS (
        SELECT m.bio_chat_message_id
        FROM public.bio_chat_messages AS m
        WHERE m.bio_is_deleted = false
          AND (
              m.bio_embedding_status = 'pending'
              OR (m.bio_embedding_status = 'failed' AND m.bio_embedding_attempts < 5)
              OR (m.bio_embedding_status = 'processing' AND m.bio_updated_at < now() - p_stale_after)
          )
        ORDER BY m.bio_updated_at, m.bio_chat_message_id
        FOR UPDATE SKIP LOCKED
        LIMIT 1
    ),
    updated AS (
        UPDATE public.bio_chat_messages AS m
        SET bio_embedding_status = 'processing',
            bio_embedding_attempts = m.bio_embedding_attempts + 1,
            bio_updated_at = now()
        FROM candidate
        WHERE m.bio_chat_message_id = candidate.bio_chat_message_id
        RETURNING m.bio_chat_message_id, m.bio_message_text, m.bio_embedding_attempts
    )
    SELECT updated.bio_chat_message_id, updated.bio_message_text, updated.bio_embedding_attempts
    FROM updated;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_store_chat_message_embedding(
    p_message_id UUID,
    p_embedding VECTOR(1536),
    p_embedding_model VARCHAR(100)
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    UPDATE public.bio_chat_messages
    SET bio_message_embedding = p_embedding,
        bio_embedding_model = p_embedding_model,
        bio_embedding_status = 'ready',
        bio_embedded_at = now()
    WHERE bio_chat_message_id = p_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_mark_chat_embedding_failed(
    p_message_id UUID,
    p_error TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    UPDATE public.bio_chat_messages
    SET bio_embedding_status = 'failed'
    WHERE bio_chat_message_id = p_message_id;
END;
$$;

ALTER FUNCTION public.bio_fn_claim_chat_embedding_job(interval) SET row_security = off;
ALTER FUNCTION public.bio_fn_store_chat_message_embedding(uuid, vector, character varying) SET row_security = off;
ALTER FUNCTION public.bio_fn_mark_chat_embedding_failed(uuid, text) SET row_security = off;


CREATE OR REPLACE PROCEDURE bio_sp_get_active_researchers(INOUT p_cursor REFCURSOR = 'cur_researchers') LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN OPEN p_cursor FOR SELECT bio_researcher_id, bio_full_name, bio_email, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_is_active, bio_created_at FROM bio_researchers ORDER BY bio_full_name ASC; END; $$;

CREATE OR REPLACE PROCEDURE bio_sp_manage_researcher(p_researcher_id UUID, p_full_name VARCHAR DEFAULT NULL, p_role_title VARCHAR DEFAULT NULL, p_is_active BOOLEAN DEFAULT NULL, p_accreditation_level INTEGER DEFAULT NULL) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::uuid; v_current_accreditation INTEGER;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'authentication required to manage researchers' USING ERRCODE = 'P0001'; END IF;
    SELECT bio_accreditation_level INTO v_current_accreditation FROM bio_researchers WHERE bio_researcher_id = v_actor_id AND bio_is_active;
    IF v_current_accreditation IS NULL OR v_current_accreditation < 3 THEN RAISE EXCEPTION 'permission denied: level 3 accreditation required' USING ERRCODE = '42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM bio_researchers WHERE bio_researcher_id = p_researcher_id) THEN RAISE EXCEPTION 'researcher not found' USING ERRCODE = 'P0004'; END IF;
    IF p_accreditation_level IS NOT NULL AND (p_accreditation_level < 1 OR p_accreditation_level > 3) THEN RAISE EXCEPTION 'invalid accreditation level: must be between 1 and 3' USING ERRCODE = '22023'; END IF;
    UPDATE bio_researchers SET bio_full_name = coalesce(nullif(btrim(p_full_name), ''), bio_full_name), bio_role_title = coalesce(nullif(btrim(p_role_title), ''), bio_role_title), bio_is_active = coalesce(p_is_active, bio_is_active), bio_accreditation_level = coalesce(p_accreditation_level, bio_accreditation_level) WHERE bio_researcher_id = p_researcher_id;
END;
$$;


CREATE OR REPLACE FUNCTION bio_trg_fn_set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF current_setting('app.preserve_updated_at', true) IS DISTINCT FROM 'true' THEN
        NEW.bio_updated_at := now();
    END IF;
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_protect_sighting_identity() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF NEW.bio_observation_reference IS DISTINCT FROM OLD.bio_observation_reference OR NEW.bio_researcher_id IS DISTINCT FROM OLD.bio_researcher_id OR NEW.bio_species_id IS DISTINCT FROM OLD.bio_species_id OR NEW.bio_site_id IS DISTINCT FROM OLD.bio_site_id OR NEW.bio_observed_at IS DISTINCT FROM OLD.bio_observed_at THEN
        RAISE EXCEPTION 'sighting identity fields are immutable' USING ERRCODE = '55000';
    END IF; RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_archive_sighting_revision() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF OLD.bio_field_notes IS NOT DISTINCT FROM NEW.bio_field_notes AND OLD.bio_classification_level IS NOT DISTINCT FROM NEW.bio_classification_level AND OLD.bio_exact_latitude IS NOT DISTINCT FROM NEW.bio_exact_latitude AND OLD.bio_exact_longitude IS NOT DISTINCT FROM NEW.bio_exact_longitude AND OLD.bio_is_voided IS NOT DISTINCT FROM NEW.bio_is_voided THEN RETURN NEW; END IF;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'an actor is required to revise a sighting' USING ERRCODE = 'P0001'; END IF;
    INSERT INTO public.bio_sighting_revisions (bio_sighting_id, bio_revision_number, bio_changed_by_researcher_id, bio_change_type, bio_previous_classification_level, bio_previous_exact_latitude, bio_previous_exact_longitude, bio_previous_field_notes, bio_change_reason) VALUES (OLD.bio_sighting_id, (SELECT COALESCE(MAX(bio_revision_number), 0) + 1 FROM public.bio_sighting_revisions WHERE bio_sighting_id = OLD.bio_sighting_id), v_actor_id, CASE WHEN NEW.bio_is_voided AND NOT OLD.bio_is_voided THEN 'voided' ELSE 'edited' END, OLD.bio_classification_level, OLD.bio_exact_latitude, OLD.bio_exact_longitude, OLD.bio_field_notes, NULLIF(current_setting('app.change_reason', true), ''));
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_invalidate_embedding() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.bio_field_notes IS DISTINCT FROM OLD.bio_field_notes THEN NEW.bio_field_notes_embedding := NULL; NEW.bio_embedding_status := 'pending'; NEW.bio_embedding_model := NULL; NEW.bio_embedded_at := NULL; END IF;
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_forbid_sighting_delete() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN RAISE EXCEPTION 'physical deletion of scientific evidence is prohibited' USING ERRCODE = '55000'; END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_notify_sighting_change() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN PERFORM pg_notify('bio_sighting_changed', NEW.bio_sighting_id::TEXT); RETURN NEW; END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_archive_chat_message_version() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::uuid;
BEGIN
    IF OLD.bio_message_text IS NOT DISTINCT FROM NEW.bio_message_text AND OLD.bio_is_deleted IS NOT DISTINCT FROM NEW.bio_is_deleted THEN RETURN NEW; END IF;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'an actor is required to change a message' USING ERRCODE = 'P0001'; END IF;
    INSERT INTO bio_chat_message_versions (bio_chat_message_id, bio_version_number, bio_message_text, bio_change_type, bio_changed_by_researcher_id) VALUES (OLD.bio_chat_message_id, (SELECT coalesce(max(bio_version_number), 0) + 1 FROM bio_chat_message_versions WHERE bio_chat_message_id = OLD.bio_chat_message_id), OLD.bio_message_text, CASE WHEN NEW.bio_is_deleted THEN 'deleted' ELSE 'edited' END, v_actor_id);
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_invalidate_chat_embedding() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.bio_message_text IS DISTINCT FROM OLD.bio_message_text OR NEW.bio_is_deleted IS DISTINCT FROM OLD.bio_is_deleted THEN NEW.bio_message_embedding := NULL; NEW.bio_embedding_status := CASE WHEN NEW.bio_is_deleted THEN 'failed' ELSE 'pending' END; NEW.bio_embedding_model := NULL; NEW.bio_embedded_at := NULL; END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_forbid_chat_message_delete() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'physical deletion of chat messages is prohibited' USING ERRCODE = '55000'; END; $$;

CREATE OR REPLACE FUNCTION bio_trg_fn_notify_chat_message() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$ BEGIN PERFORM pg_notify('bio_chat_changed', NEW.bio_chat_channel_id::text); RETURN NEW; END; $$;

-- Table triggers
CREATE TRIGGER trg_bio_researchers_30_touch BEFORE UPDATE ON bio_researchers FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_species_30_touch BEFORE UPDATE ON bio_species FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_sites_30_touch BEFORE UPDATE ON bio_sites FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_sightings_10_archive_revision BEFORE UPDATE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_archive_sighting_revision();
CREATE TRIGGER trg_bio_sightings_15_protect_identity BEFORE UPDATE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_protect_sighting_identity();
CREATE TRIGGER trg_bio_sightings_20_invalidate_embedding BEFORE INSERT OR UPDATE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_invalidate_embedding();
CREATE TRIGGER trg_bio_sightings_30_touch BEFORE UPDATE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_sightings_40_forbid_delete BEFORE DELETE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_forbid_sighting_delete();
CREATE TRIGGER trg_bio_sightings_50_notify_change AFTER INSERT OR UPDATE ON bio_sightings FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_notify_sighting_change();
CREATE TRIGGER bio_species_images_set_updated_at BEFORE UPDATE ON bio_species_images FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER bio_site_images_set_updated_at BEFORE UPDATE ON bio_site_images FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_chat_channels_touch BEFORE UPDATE ON bio_chat_channels FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_chat_messages_10_archive BEFORE UPDATE ON bio_chat_messages FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_archive_chat_message_version();
CREATE TRIGGER trg_bio_chat_messages_20_embedding BEFORE INSERT OR UPDATE ON bio_chat_messages FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_invalidate_chat_embedding();
CREATE TRIGGER trg_bio_chat_messages_30_touch BEFORE UPDATE ON bio_chat_messages FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_chat_messages_40_no_delete BEFORE DELETE ON bio_chat_messages FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_forbid_chat_message_delete();
CREATE TRIGGER trg_bio_chat_messages_50_notify AFTER INSERT OR UPDATE ON bio_chat_messages FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_notify_chat_message();

-- Worker bypass RLS
ALTER FUNCTION public.bio_fn_claim_embedding_job(interval) SET row_security = off;
ALTER FUNCTION public.bio_fn_mark_embedding_failed(uuid, text) SET row_security = off;
ALTER FUNCTION public.bio_fn_store_sighting_embedding(uuid, vector, character varying) SET row_security = off;
ALTER TABLE public.bio_sightings NO FORCE ROW LEVEL SECURITY;

GRANT EXECUTE ON FUNCTION bio_fn_register_sighting(VARCHAR, UUID, UUID, TIMESTAMPTZ, NUMERIC, NUMERIC, SMALLINT, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_sighting_history_with_images(UUID, UUID, TIMESTAMPTZ, UUID, INTEGER, BOOLEAN) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_sighting_detail(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_search_field_notes(TEXT, TIMESTAMPTZ, UUID, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_retrieve_copilot_context(VECTOR, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_store_sighting_embedding(UUID, VECTOR, VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_claim_embedding_job(INTERVAL) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_mark_embedding_failed(UUID, TEXT) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_edit_sighting(UUID, TEXT, SMALLINT, NUMERIC, NUMERIC, TEXT) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_void_sighting(UUID, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_knowledge_catalog() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_chat_channel(VARCHAR, VARCHAR, UUID[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_send_chat_message(UUID, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_edit_chat_message(UUID, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_delete_chat_message(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_retrieve_chat_shared_sighting_context(UUID, VECTOR, INTEGER) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_get_active_researchers(REFCURSOR) TO bio_app_user;
GRANT EXECUTE ON PROCEDURE bio_sp_manage_researcher(UUID, VARCHAR, VARCHAR, BOOLEAN, INTEGER) TO bio_app_user;

-- Dashboard aggregates always start from bio_sightings, therefore the invoker's
  -- RLS policy filters every number before it reaches the API.
  CREATE FUNCTION bio_fn_dashboard_summary()
  RETURNS TABLE (
      visible_sightings BIGINT,
      registered_species BIGINT,
      monitored_sites BIGINT,
      field_notes BIGINT
  )
  LANGUAGE sql
  SECURITY INVOKER
  SET search_path = pg_catalog, public
  AS $$
      SELECT COUNT(*)::BIGINT,
             COUNT(DISTINCT s.bio_species_id)::BIGINT,
             COUNT(DISTINCT s.bio_site_id)::BIGINT,
             COUNT(*)::BIGINT
      FROM public.bio_sightings AS s
      WHERE s.bio_is_voided = false;
  $$;
  
  CREATE FUNCTION bio_fn_dashboard_classification()
  RETURNS TABLE (classification_level SMALLINT, total BIGINT)
  LANGUAGE sql
  SECURITY INVOKER
  SET search_path = pg_catalog, public
  AS $$
      SELECT s.bio_classification_level, COUNT(*)::BIGINT
      FROM public.bio_sightings AS s
      WHERE s.bio_is_voided = false
      GROUP BY s.bio_classification_level
      ORDER BY s.bio_classification_level;
  $$;
  
  CREATE FUNCTION bio_fn_dashboard_activity(p_limit INTEGER DEFAULT 6)
  RETURNS TABLE (
      activity_type VARCHAR,
      researcher_name VARCHAR,
      observation_reference VARCHAR,
      species_common_name VARCHAR,
      occurred_at TIMESTAMPTZ
  )
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path = pg_catalog, public
  AS $$
  BEGIN
      IF p_limit NOT BETWEEN 1 AND 20 THEN
          RAISE EXCEPTION 'activity limit must be between 1 and 20' USING ERRCODE = '22023';
      END IF;
      RETURN QUERY
      SELECT * FROM (
          SELECT 'created'::VARCHAR, author.bio_full_name, s.bio_observation_reference,
                 sp.bio_common_name, s.bio_created_at
          FROM public.bio_sightings AS s
          JOIN public.bio_researchers AS author ON author.bio_researcher_id = s.bio_researcher_id
          JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
          UNION ALL
          SELECT r.bio_change_type, editor.bio_full_name, s.bio_observation_reference,
                 sp.bio_common_name, r.bio_created_at
          FROM public.bio_sighting_revisions AS r
          JOIN public.bio_sightings AS s ON s.bio_sighting_id = r.bio_sighting_id
          JOIN public.bio_researchers AS editor ON editor.bio_researcher_id = r.bio_changed_by_researcher_id
          JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
      ) AS activity
      ORDER BY occurred_at DESC
      LIMIT p_limit;
  END;
  $$;
  
CREATE OR REPLACE FUNCTION bio_fn_researcher_directory()
RETURNS TABLE (researcher_id UUID, full_name VARCHAR, role_title VARCHAR, accreditation_level SMALLINT, avatar_key VARCHAR)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title, r.bio_accreditation_level, r.bio_avatar_key
    FROM public.bio_researchers AS r
    WHERE r.bio_is_active = true
    ORDER BY r.bio_full_name, r.bio_researcher_id;
$$;

-- Authentication & Token management functions (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION bio_fn_get_researcher_for_login(p_email CITEXT)
RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, email CITEXT, password_hash VARCHAR,
    role_title VARCHAR, accreditation_level SMALLINT, avatar_key VARCHAR, is_active BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_email, r.bio_password_hash,
           r.bio_role_title, r.bio_accreditation_level, r.bio_avatar_key, r.bio_is_active
    FROM public.bio_researchers AS r
    WHERE r.bio_email = p_email AND r.bio_is_active = true;
$$;

CREATE OR REPLACE FUNCTION bio_fn_create_refresh_token(
    p_researcher_id UUID,
    p_token_hash VARCHAR(64),
    p_family_id UUID,
    p_expires_at TIMESTAMPTZ,
    p_replaced_by UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    INSERT INTO public.bio_refresh_tokens (
        bio_researcher_id, bio_token_hash, bio_token_family_id, bio_expires_at, bio_parent_refresh_token_id
    ) VALUES (
        p_researcher_id, p_token_hash, p_family_id, p_expires_at, p_replaced_by
    ) RETURNING bio_refresh_token_id;
$$;

CREATE OR REPLACE FUNCTION bio_fn_rotate_refresh_token(
    p_current_token_hash VARCHAR(64),
    p_new_token_hash VARCHAR(64),
    p_new_expires_at TIMESTAMPTZ
) RETURNS TABLE (
    researcher_id UUID, family_id UUID, new_token_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_token RECORD;
    v_new_id UUID := gen_random_uuid();
BEGIN
    SELECT * INTO v_token
    FROM public.bio_refresh_tokens
    WHERE bio_token_hash = p_current_token_hash
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'refresh token was not found' USING ERRCODE = '28000';
    END IF;
    IF v_token.bio_revoked_at IS NOT NULL OR v_token.bio_expires_at < now() THEN
        UPDATE public.bio_refresh_tokens
        SET bio_revoked_at = COALESCE(bio_revoked_at, now()),
            bio_revocation_reason = COALESCE(bio_revocation_reason, 'reused_or_expired')
        WHERE bio_token_family_id = v_token.bio_token_family_id;
        RAISE EXCEPTION 'refresh token is invalid' USING ERRCODE = '28000';
    END IF;

    INSERT INTO public.bio_refresh_tokens (
        bio_refresh_token_id, bio_researcher_id, bio_token_hash, bio_token_family_id, bio_expires_at
    ) VALUES (
        v_new_id, v_token.bio_researcher_id, p_new_token_hash, v_token.bio_token_family_id, p_new_expires_at
    );

    UPDATE public.bio_refresh_tokens
    SET bio_revoked_at = now(),
        bio_revocation_reason = 'rotated',
        bio_parent_refresh_token_id = v_new_id
    WHERE bio_refresh_token_id = v_token.bio_refresh_token_id;

    RETURN QUERY SELECT v_token.bio_researcher_id, v_token.bio_token_family_id, v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_revoke_refresh_token_family(
    p_token_hash VARCHAR(64),
    p_reason VARCHAR(100) DEFAULT 'user_logout'
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    UPDATE public.bio_refresh_tokens
    SET bio_revoked_at = now(),
        bio_revocation_reason = p_reason
    WHERE bio_token_family_id = (
        SELECT bio_token_family_id FROM public.bio_refresh_tokens WHERE bio_token_hash = p_token_hash
    ) AND bio_revoked_at IS NULL;
$$;

-- Copilot Conversations & Usage Functions
CREATE OR REPLACE FUNCTION bio_fn_log_copilot_usage(
    p_prompt TEXT, p_answer TEXT, p_system_prompt_version VARCHAR, p_model_name VARCHAR,
    p_input_tokens INTEGER, p_output_tokens INTEGER, p_source_sighting_ids UUID[], p_source_similarities NUMERIC[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_usage_id UUID := gen_random_uuid();
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    v_idx INTEGER;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'an actor is required' USING ERRCODE = 'P0001'; END IF;
    INSERT INTO public.bio_copilot_usage (
        bio_copilot_usage_id, bio_researcher_id, bio_prompt_text, bio_response_text, bio_system_prompt_version,
        bio_model_name, bio_input_tokens, bio_output_tokens
    ) VALUES (
        v_usage_id, v_actor_id, p_prompt, p_answer, p_system_prompt_version,
        p_model_name, p_input_tokens, p_output_tokens
    );
    IF p_source_sighting_ids IS NOT NULL THEN
        FOR v_idx IN 1..array_length(p_source_sighting_ids, 1) LOOP
            INSERT INTO public.bio_copilot_citations (
                bio_copilot_usage_id, bio_sighting_id, bio_rank, bio_similarity
            ) VALUES (
                v_usage_id, p_source_sighting_ids[v_idx], v_idx, p_source_similarities[v_idx]
            );
        END LOOP;
    END IF;
    RETURN v_usage_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_create_copilot_conversation(p_title VARCHAR(120) DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_conv_id UUID := gen_random_uuid();
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'an actor is required' USING ERRCODE = 'P0001'; END IF;
    INSERT INTO public.bio_copilot_conversations (
        bio_conversation_id, bio_researcher_id, bio_title
    ) VALUES (
        v_conv_id, v_actor_id, COALESCE(p_title, 'Nueva consulta')
    );
    RETURN v_conv_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_list_copilot_conversations(p_limit INTEGER DEFAULT 30)
RETURNS TABLE (
    conversation_id UUID, title VARCHAR(120), created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ, message_count BIGINT
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT c.bio_conversation_id, c.bio_title, c.bio_created_at, c.bio_updated_at,
           COUNT(m.bio_message_id)::BIGINT AS message_count
    FROM public.bio_copilot_conversations c
    LEFT JOIN public.bio_copilot_messages m ON m.bio_conversation_id = c.bio_conversation_id
    WHERE c.bio_is_active = true
    GROUP BY c.bio_conversation_id, c.bio_title, c.bio_created_at, c.bio_updated_at
    ORDER BY c.bio_updated_at DESC
    LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION bio_fn_get_copilot_conversation_messages(p_conversation_id UUID)
RETURNS TABLE (
    message_id UUID, conversation_id UUID, sender_role VARCHAR(20),
    message_text TEXT, model_name VARCHAR(100), created_at TIMESTAMPTZ, citations JSONB
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT m.bio_message_id, m.bio_conversation_id, m.bio_sender_role,
           m.bio_message_text, m.bio_model_name, m.bio_created_at,
           COALESCE(
               (SELECT jsonb_agg(jsonb_build_object(
                   'sighting_id', s.bio_sighting_id,
                   'observation_reference', s.bio_observation_reference,
                   'species_common_name', sp.bio_common_name,
                   'field_notes', s.bio_field_notes,
                   'similarity', cit.bio_similarity
               ) ORDER BY cit.bio_rank)
               FROM public.bio_copilot_citations cit
               JOIN public.bio_sightings s ON s.bio_sighting_id = cit.bio_sighting_id
               JOIN public.bio_species sp ON sp.bio_species_id = s.bio_species_id
               WHERE cit.bio_copilot_usage_id = m.bio_copilot_usage_id),
               '[]'::jsonb
           ) AS citations
    FROM public.bio_copilot_messages m
    WHERE m.bio_conversation_id = p_conversation_id
    ORDER BY m.bio_created_at ASC;
$$;


CREATE OR REPLACE FUNCTION bio_fn_record_copilot_turn(
    p_conversation_id UUID, p_prompt TEXT, p_answer TEXT, p_system_prompt_version VARCHAR,
    p_model_name VARCHAR, p_input_tokens INTEGER, p_output_tokens INTEGER,
    p_source_sighting_ids UUID[], p_source_similarities NUMERIC[]
) RETURNS TABLE (
    usage_id UUID, user_message_id UUID, assistant_message_id UUID
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_usage_id UUID;
    v_user_msg_id UUID := gen_random_uuid();
    v_asst_msg_id UUID := gen_random_uuid();
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'an actor is required' USING ERRCODE = 'P0001'; END IF;
    
    v_usage_id := bio_fn_log_copilot_usage(
        p_prompt, p_answer, p_system_prompt_version, p_model_name,
        p_input_tokens, p_output_tokens, p_source_sighting_ids, p_source_similarities
    );

    INSERT INTO public.bio_copilot_messages (
        bio_message_id, bio_conversation_id, bio_researcher_id, bio_sender_role, bio_message_text
    ) VALUES (
        v_user_msg_id, p_conversation_id, v_actor_id, 'user', p_prompt
    );

    INSERT INTO public.bio_copilot_messages (
        bio_message_id, bio_conversation_id, bio_researcher_id, bio_sender_role, bio_message_text,
        bio_model_name, bio_usage_id
    ) VALUES (
        v_asst_msg_id, p_conversation_id, v_actor_id, 'assistant', p_answer,
        p_model_name, v_usage_id
    );

    UPDATE public.bio_copilot_conversations
    SET bio_updated_at = now(),
        bio_title = CASE WHEN bio_title = 'Nueva consulta' THEN LEFT(p_prompt, 80) ELSE bio_title END
    WHERE bio_conversation_id = p_conversation_id;

    RETURN QUERY SELECT v_usage_id, v_user_msg_id, v_asst_msg_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_delete_copilot_conversation(p_conversation_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    UPDATE public.bio_copilot_conversations
    SET bio_is_active = false, bio_archived_at = now()
    WHERE bio_conversation_id = p_conversation_id;
$$;

-- Grants
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_summary() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_classification() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_activity(INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_researcher_directory() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_researcher_for_login(CITEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_refresh_token(UUID, VARCHAR, UUID, TIMESTAMPTZ, UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_revoke_refresh_token_family(VARCHAR, VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_log_copilot_usage(TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_copilot_conversation(VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_list_copilot_conversations(INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_copilot_conversation_messages(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_record_copilot_turn(UUID, TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_retrieve_chat_message_context(UUID, VECTOR, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_record_chat_copilot_response(UUID, TEXT, JSONB) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_claim_chat_embedding_job(INTERVAL) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_store_chat_message_embedding(UUID, VECTOR, VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_mark_chat_embedding_failed(UUID, TEXT) TO bio_app_user;

RESET ROLE;



