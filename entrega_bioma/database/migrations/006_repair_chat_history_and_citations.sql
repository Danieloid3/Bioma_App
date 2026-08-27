-- =============================================================================
-- 006_repair_chat_history_and_citations.sql
-- Aligns chat history and copilot citation persistence with the canonical
-- bio_chat_copilot_citations(source_type, source_reference, source_id, rank)
-- schema. The broken consolidated functions referenced removed columns and
-- caused the send transaction to roll back while re-reading its new message.
-- =============================================================================

SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_fn_record_chat_copilot_response(
    p_channel_id UUID,
    p_text TEXT,
    p_sources JSONB DEFAULT '[]'::JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
    v_message_id UUID := gen_random_uuid();
    v_source JSONB;
    v_source_type VARCHAR(12);
    v_source_reference VARCHAR(80);
    v_source_id UUID;
    v_rank SMALLINT := 0;
BEGIN
    IF NOT bio_fn_is_chat_member(p_channel_id) THEN
        RAISE EXCEPTION 'unauthorized to post copilot response in channel'
            USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_text, ''))) = 0 THEN
        RAISE EXCEPTION 'copilot response text is required' USING ERRCODE = '22023';
    END IF;
    IF p_sources IS NULL OR jsonb_typeof(p_sources) <> 'array' THEN
        RAISE EXCEPTION 'copilot sources must be a JSON array' USING ERRCODE = '22023';
    END IF;

    -- Validate every source before writing the response or any citation. The
    -- function is SECURITY DEFINER, so authorization is checked explicitly.
    FOR v_source IN SELECT value FROM jsonb_array_elements(p_sources) AS source(value) LOOP
        v_source_type := v_source->>'type';
        v_source_reference := v_source->>'reference';
        BEGIN
            v_source_id := (v_source->>'id')::UUID;
        EXCEPTION
            WHEN invalid_text_representation THEN
                RAISE EXCEPTION 'copilot source id must be a UUID' USING ERRCODE = '22023';
        END;

        IF v_source_type NOT IN ('message', 'sighting')
           OR length(btrim(coalesce(v_source_reference, ''))) = 0
           OR v_source_id IS NULL THEN
            RAISE EXCEPTION 'invalid copilot source payload' USING ERRCODE = '22023';
        END IF;

        IF v_source_type = 'message' THEN
            IF NOT EXISTS (
                SELECT 1
                FROM public.bio_chat_messages AS source_message
                WHERE source_message.bio_chat_message_id = v_source_id
                  AND source_message.bio_chat_channel_id = p_channel_id
                  AND source_message.bio_is_deleted = false
                  AND v_source_reference = 'msg-' || substring(source_message.bio_chat_message_id::TEXT, 1, 8)
            ) THEN
                RAISE EXCEPTION 'copilot message source is unavailable to this channel'
                    USING ERRCODE = '42501';
            END IF;
        ELSE
            IF NOT EXISTS (
                SELECT 1
                FROM public.bio_sightings AS sighting
                WHERE sighting.bio_sighting_id = v_source_id
                  AND sighting.bio_observation_reference = v_source_reference
                  AND sighting.bio_is_voided = false
                  AND NOT EXISTS (
                      SELECT 1
                      FROM public.bio_chat_channel_members AS member
                      JOIN public.bio_researchers AS researcher
                        ON researcher.bio_researcher_id = member.bio_researcher_id
                      WHERE member.bio_chat_channel_id = p_channel_id
                        AND member.bio_left_at IS NULL
                        AND researcher.bio_is_active
                        AND sighting.bio_classification_level > researcher.bio_accreditation_level
                        AND sighting.bio_researcher_id <> researcher.bio_researcher_id
                  )
            ) THEN
                RAISE EXCEPTION 'copilot sighting source is unavailable to every channel member'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END LOOP;

    INSERT INTO public.bio_chat_messages (
        bio_chat_message_id,
        bio_chat_channel_id,
        bio_author_researcher_id,
        bio_sender_role,
        bio_message_text
    ) VALUES (
        v_message_id,
        p_channel_id,
        NULL,
        'copilot',
        btrim(p_text)
    );

    INSERT INTO public.bio_chat_message_receipts (
        bio_chat_message_id,
        bio_researcher_id,
        bio_read_at
    )
    SELECT v_message_id,
           member.bio_researcher_id,
           CASE WHEN member.bio_researcher_id = v_actor_id THEN now() ELSE NULL END
    FROM public.bio_chat_channel_members AS member
    WHERE member.bio_chat_channel_id = p_channel_id
      AND member.bio_left_at IS NULL;

    FOR v_source IN SELECT value FROM jsonb_array_elements(p_sources) AS source(value) LOOP
        v_rank := v_rank + 1;
        INSERT INTO public.bio_chat_copilot_citations (
            bio_chat_message_id,
            bio_source_type,
            bio_source_reference,
            bio_source_id,
            bio_rank
        ) VALUES (
            v_message_id,
            v_source->>'type',
            v_source->>'reference',
            (v_source->>'id')::UUID,
            v_rank
        );
    END LOOP;

    RETURN v_message_id;
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
    IF p_limit NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'chat history limit must be between 1 and 100'
            USING ERRCODE = '22023';
    END IF;
    IF (p_cursor_created_at IS NULL) <> (p_cursor_message_id IS NULL) THEN
        RAISE EXCEPTION 'chat history cursor must include timestamp and message id'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT message.bio_chat_message_id,
           message.bio_chat_channel_id,
           message.bio_author_researcher_id,
           coalesce(researcher.bio_full_name, 'Copiloto Bioma')::VARCHAR,
           CASE
               WHEN message.bio_is_deleted THEN 'Este mensaje fue eliminado'
               ELSE message.bio_message_text
           END,
           message.bio_sender_role,
           message.bio_is_edited,
           message.bio_is_deleted,
           message.bio_created_at,
           (
               SELECT count(*)::BIGINT
               FROM public.bio_chat_message_receipts AS receipt
               WHERE receipt.bio_chat_message_id = message.bio_chat_message_id
                 AND receipt.bio_read_at IS NOT NULL
           ),
           coalesce(
               (
                   SELECT jsonb_agg(
                       jsonb_build_object(
                           'type', citation.bio_source_type,
                           'reference', citation.bio_source_reference,
                           'id', citation.bio_source_id
                       )
                       ORDER BY citation.bio_rank
                   )
                   FROM public.bio_chat_copilot_citations AS citation
                   WHERE citation.bio_chat_message_id = message.bio_chat_message_id
               ),
               '[]'::JSONB
           )
    FROM public.bio_chat_messages AS message
    LEFT JOIN public.bio_researchers AS researcher
      ON researcher.bio_researcher_id = message.bio_author_researcher_id
    WHERE message.bio_chat_channel_id = p_channel_id
      AND (
          p_cursor_created_at IS NULL
          OR (message.bio_created_at, message.bio_chat_message_id)
             < (p_cursor_created_at, p_cursor_message_id)
      )
    ORDER BY message.bio_created_at DESC, message.bio_chat_message_id DESC
    LIMIT p_limit;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_record_chat_copilot_response(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_record_chat_copilot_response(UUID, TEXT, JSONB) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER) TO bio_app_user;

RESET ROLE;
