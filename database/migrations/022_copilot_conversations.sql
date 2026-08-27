SET ROLE bio_owner;

-- Copilot conversations and messages with full RLS security isolation

CREATE TABLE IF NOT EXISTS bio_copilot_conversations (
    bio_conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_title VARCHAR(120) NOT NULL DEFAULT 'Nueva consulta',
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bio_copilot_messages (
    bio_message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_conversation_id UUID NOT NULL REFERENCES bio_copilot_conversations (bio_conversation_id) ON DELETE CASCADE,
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_sender_role VARCHAR(16) NOT NULL CHECK (bio_sender_role IN ('user', 'assistant')),
    bio_message_text TEXT NOT NULL,
    bio_model_name VARCHAR(100),
    bio_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_input_tokens >= 0),
    bio_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_output_tokens >= 0),
    bio_copilot_usage_id UUID REFERENCES bio_copilot_usage (bio_copilot_usage_id) ON DELETE SET NULL,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_bio_copilot_conversations_researcher
    ON bio_copilot_conversations (bio_researcher_id, bio_updated_at DESC);

CREATE INDEX IF NOT EXISTS ix_bio_copilot_messages_conversation
    ON bio_copilot_messages (bio_conversation_id, bio_created_at ASC);

ALTER TABLE bio_copilot_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_conversations FORCE ROW LEVEL SECURITY;

ALTER TABLE bio_copilot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_messages FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bio_copilot_conversations_policy ON bio_copilot_conversations;
CREATE POLICY bio_copilot_conversations_policy ON bio_copilot_conversations
    FOR ALL
    TO bio_app_user
    USING (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

DROP POLICY IF EXISTS bio_copilot_messages_policy ON bio_copilot_messages;
CREATE POLICY bio_copilot_messages_policy ON bio_copilot_messages
    FOR ALL
    TO bio_app_user
    USING (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE OR REPLACE FUNCTION bio_fn_create_copilot_conversation(
    p_title VARCHAR DEFAULT 'Nueva consulta'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_conversation_id UUID;
    v_clean_title VARCHAR;
BEGIN
    v_actor_id := nullif(current_setting('app.current_user_id', true), '')::uuid;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0001';
    END IF;

    v_clean_title := coalesce(nullif(trim(p_title), ''), 'Nueva consulta');
    IF length(v_clean_title) > 120 THEN
        v_clean_title := left(v_clean_title, 117) || '...';
    END IF;

    INSERT INTO public.bio_copilot_conversations (
        bio_researcher_id, bio_title, bio_created_at, bio_updated_at
    ) VALUES (
        v_actor_id, v_clean_title, now(), now()
    ) RETURNING bio_conversation_id INTO v_conversation_id;

    RETURN v_conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_list_copilot_conversations(
    p_limit INTEGER DEFAULT 30
) RETURNS TABLE (
    conversation_id UUID,
    title VARCHAR,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    message_count BIGINT
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT c.bio_conversation_id,
           c.bio_title,
           c.bio_created_at,
           c.bio_updated_at,
           count(m.bio_message_id)::BIGINT AS message_count
    FROM public.bio_copilot_conversations AS c
    LEFT JOIN public.bio_copilot_messages AS m
      ON m.bio_conversation_id = c.bio_conversation_id
    GROUP BY c.bio_conversation_id, c.bio_title, c.bio_created_at, c.bio_updated_at
    ORDER BY c.bio_updated_at DESC
    LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION bio_fn_get_copilot_conversation_messages(
    p_conversation_id UUID
) RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    sender_role VARCHAR,
    message_text TEXT,
    model_name VARCHAR,
    created_at TIMESTAMPTZ,
    citations JSONB
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT m.bio_message_id,
           m.bio_conversation_id,
           m.bio_sender_role,
           m.bio_message_text,
           m.bio_model_name,
           m.bio_created_at,
           coalesce(
               (
                   SELECT jsonb_agg(
                       jsonb_build_object(
                           'sighting_id', s.bio_sighting_id,
                           'observation_reference', s.bio_observation_reference,
                           'species_common_name', sp.bio_common_name,
                           'field_notes', s.bio_field_notes,
                           'similarity', cit.bio_similarity
                       ) ORDER BY cit.bio_rank
                   )
                   FROM public.bio_copilot_citations AS cit
                   JOIN public.bio_sightings AS s ON s.bio_sighting_id = cit.bio_sighting_id
                   JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
                   WHERE cit.bio_copilot_usage_id = m.bio_copilot_usage_id
               ),
               '[]'::jsonb
           ) AS citations
    FROM public.bio_copilot_messages AS m
    WHERE m.bio_conversation_id = p_conversation_id
    ORDER BY m.bio_created_at ASC;
$$;

CREATE OR REPLACE FUNCTION bio_fn_record_copilot_turn(
    p_conversation_id UUID,
    p_prompt_text TEXT,
    p_response_text TEXT,
    p_system_prompt_version VARCHAR,
    p_model_name VARCHAR,
    p_input_tokens INTEGER,
    p_output_tokens INTEGER,
    p_sighting_ids UUID[],
    p_similarities NUMERIC[]
) RETURNS TABLE (
    usage_id UUID,
    user_message_id UUID,
    assistant_message_id UUID
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
    v_usage_id UUID;
    v_user_msg_id UUID;
    v_asst_msg_id UUID;
    v_conv_title VARCHAR;
    v_current_title VARCHAR;
BEGIN
    v_actor_id := nullif(current_setting('app.current_user_id', true), '')::uuid;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0001';
    END IF;

    -- Verify conversation ownership under RLS
    SELECT bio_title INTO v_current_title
    FROM public.bio_copilot_conversations
    WHERE bio_conversation_id = p_conversation_id;

    IF v_current_title IS NULL THEN
        RAISE EXCEPTION 'conversation not found' USING ERRCODE = 'P0004';
    END IF;

    -- Record usage audit
    v_usage_id := bio_fn_log_copilot_usage(
        p_prompt_text, p_response_text, p_system_prompt_version,
        p_model_name, p_input_tokens, p_output_tokens,
        p_sighting_ids, p_similarities
    );

    -- Insert user message
    INSERT INTO public.bio_copilot_messages (
        bio_conversation_id, bio_researcher_id, bio_sender_role,
        bio_message_text, bio_model_name, bio_input_tokens,
        bio_output_tokens, bio_copilot_usage_id, bio_created_at
    ) VALUES (
        p_conversation_id, v_actor_id, 'user',
        p_prompt_text, NULL, 0, 0, NULL, now()
    ) RETURNING bio_message_id INTO v_user_msg_id;

    -- Insert assistant message
    INSERT INTO public.bio_copilot_messages (
        bio_conversation_id, bio_researcher_id, bio_sender_role,
        bio_message_text, bio_model_name, bio_input_tokens,
        bio_output_tokens, bio_copilot_usage_id, bio_created_at
    ) VALUES (
        p_conversation_id, v_actor_id, 'assistant',
        p_response_text, p_model_name, p_input_tokens,
        p_output_tokens, v_usage_id, now() + interval '1 millisecond'
    ) RETURNING bio_message_id INTO v_asst_msg_id;

    -- If title is still default, update it with summary of first question
    IF v_current_title = 'Nueva consulta' THEN
        v_conv_title := trim(p_prompt_text);
        IF length(v_conv_title) > 60 THEN
            v_conv_title := left(v_conv_title, 57) || '...';
        END IF;
    ELSE
        v_conv_title := v_current_title;
    END IF;

    UPDATE public.bio_copilot_conversations
    SET bio_title = v_conv_title,
        bio_updated_at = now()
    WHERE bio_conversation_id = p_conversation_id;

    RETURN QUERY SELECT v_usage_id, v_user_msg_id, v_asst_msg_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_delete_copilot_conversation(
    p_conversation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    DELETE FROM public.bio_copilot_conversations
    WHERE bio_conversation_id = p_conversation_id;
END;
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.bio_copilot_conversations, public.bio_copilot_messages TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_copilot_conversation(VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_list_copilot_conversations(INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_copilot_conversation_messages(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_record_copilot_turn(UUID, TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) TO bio_app_user;

RESET ROLE;