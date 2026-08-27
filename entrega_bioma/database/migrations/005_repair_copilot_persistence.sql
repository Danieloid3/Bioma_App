-- =============================================================================
-- 005_repair_copilot_persistence.sql
-- Repairs regressions introduced while consolidating the canonical baseline:
--   * restores privileged, authorization-aware copilot auditing;
--   * persists a conversation turn against the audit row already created by the
--     use case instead of duplicating usage;
--   * aligns assistant-message ownership with the table constraint;
--   * restores the usage-summary contract consumed by the API/frontend;
--   * closes direct DML and citation-visibility gaps.
-- =============================================================================

SET ROLE bio_owner;

-- SECURITY DEFINER functions below are the only write path for conversations
-- and messages. FORCE RLS remains enabled, so the owning role needs explicit
-- policies while the application role receives read-only policies.
DROP POLICY IF EXISTS bio_copilot_conversations_policy ON public.bio_copilot_conversations;
DROP POLICY IF EXISTS bio_copilot_conversations_owner_policy ON public.bio_copilot_conversations;
CREATE POLICY bio_copilot_conversations_select_policy
    ON public.bio_copilot_conversations
    FOR SELECT TO bio_app_user
    USING (
        bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
    );
CREATE POLICY bio_copilot_conversations_owner_policy
    ON public.bio_copilot_conversations
    FOR ALL TO bio_owner
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS bio_copilot_messages_policy ON public.bio_copilot_messages;
DROP POLICY IF EXISTS bio_copilot_messages_owner_policy ON public.bio_copilot_messages;
CREATE POLICY bio_copilot_messages_select_policy
    ON public.bio_copilot_messages
    FOR SELECT TO bio_app_user
    USING (
        EXISTS (
            SELECT 1
            FROM public.bio_copilot_conversations AS conversation
            WHERE conversation.bio_conversation_id = bio_copilot_messages.bio_conversation_id
              AND conversation.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
        )
    );
CREATE POLICY bio_copilot_messages_owner_policy
    ON public.bio_copilot_messages
    FOR ALL TO bio_owner
    USING (true)
    WITH CHECK (true);

ALTER TABLE public.bio_copilot_citations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bio_copilot_citations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bio_copilot_citations_select_policy ON public.bio_copilot_citations;
DROP POLICY IF EXISTS bio_copilot_citations_owner_policy ON public.bio_copilot_citations;
CREATE POLICY bio_copilot_citations_select_policy
    ON public.bio_copilot_citations
    FOR SELECT TO bio_app_user
    USING (
        EXISTS (
            SELECT 1
            FROM public.bio_copilot_usage AS usage
            WHERE usage.bio_copilot_usage_id = bio_copilot_citations.bio_copilot_usage_id
              AND usage.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
        )
    );
CREATE POLICY bio_copilot_citations_owner_policy
    ON public.bio_copilot_citations
    FOR ALL TO bio_owner
    USING (true)
    WITH CHECK (true);

REVOKE INSERT, UPDATE, DELETE
    ON public.bio_copilot_conversations, public.bio_copilot_messages
    FROM bio_app_user;

CREATE OR REPLACE FUNCTION bio_fn_log_copilot_usage(
    p_prompt TEXT,
    p_answer TEXT,
    p_system_prompt_version VARCHAR,
    p_model_name VARCHAR,
    p_input_tokens INTEGER,
    p_output_tokens INTEGER,
    p_source_sighting_ids UUID[],
    p_source_similarities NUMERIC[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_usage_id UUID := gen_random_uuid();
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
    v_actor_accreditation SMALLINT;
    v_idx INTEGER;
    v_source_ids UUID[] := coalesce(p_source_sighting_ids, ARRAY[]::UUID[]);
    v_similarities NUMERIC[] := coalesce(p_source_similarities, ARRAY[]::NUMERIC[]);
BEGIN
    SELECT researcher.bio_accreditation_level
    INTO v_actor_accreditation
    FROM public.bio_researchers AS researcher
    WHERE researcher.bio_researcher_id = v_actor_id
      AND researcher.bio_is_active;

    IF v_actor_id IS NULL OR v_actor_accreditation IS NULL THEN
        RAISE EXCEPTION 'an active actor is required' USING ERRCODE = '42501';
    END IF;
    IF cardinality(v_source_ids) <> cardinality(v_similarities) THEN
        RAISE EXCEPTION 'copilot source ids and similarities must have equal length'
            USING ERRCODE = '22023';
    END IF;
    IF p_input_tokens < 0 OR p_output_tokens < 0 THEN
        RAISE EXCEPTION 'copilot token counts cannot be negative' USING ERRCODE = '22023';
    END IF;

    -- Do not rely on the definer's privileges here. Re-check the immutable
    -- business rule explicitly before persisting any citation.
    IF EXISTS (
        SELECT 1
        FROM unnest(v_source_ids) AS requested(sighting_id)
        LEFT JOIN public.bio_sightings AS sighting
          ON sighting.bio_sighting_id = requested.sighting_id
        WHERE sighting.bio_sighting_id IS NULL
           OR sighting.bio_is_voided
           OR NOT (
               sighting.bio_classification_level <= v_actor_accreditation
               OR sighting.bio_researcher_id = v_actor_id
           )
    ) THEN
        RAISE EXCEPTION 'copilot citations contain a sighting unavailable to actor'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.bio_copilot_usage (
        bio_copilot_usage_id,
        bio_researcher_id,
        bio_prompt_text,
        bio_response_text,
        bio_system_prompt_version,
        bio_model_name,
        bio_input_tokens,
        bio_output_tokens
    ) VALUES (
        v_usage_id,
        v_actor_id,
        p_prompt,
        p_answer,
        p_system_prompt_version,
        p_model_name,
        p_input_tokens,
        p_output_tokens
    );

    FOR v_idx IN 1..cardinality(v_source_ids) LOOP
        INSERT INTO public.bio_copilot_citations (
            bio_copilot_usage_id,
            bio_sighting_id,
            bio_rank,
            bio_similarity
        ) VALUES (
            v_usage_id,
            v_source_ids[v_idx],
            v_idx,
            v_similarities[v_idx]
        );
    END LOOP;

    RETURN v_usage_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_create_copilot_conversation(
    p_title VARCHAR(120) DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_conversation_id UUID := gen_random_uuid();
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
    v_title VARCHAR(120) := left(coalesce(nullif(btrim(p_title), ''), 'Nueva consulta'), 120);
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.bio_researchers AS researcher
        WHERE researcher.bio_researcher_id = v_actor_id
          AND researcher.bio_is_active
    ) THEN
        RAISE EXCEPTION 'an active actor is required' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.bio_copilot_conversations (
        bio_conversation_id,
        bio_researcher_id,
        bio_title
    ) VALUES (
        v_conversation_id,
        v_actor_id,
        v_title
    );

    RETURN v_conversation_id;
END;
$$;

DROP FUNCTION IF EXISTS bio_fn_record_copilot_turn(
    UUID, TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]
);

CREATE FUNCTION bio_fn_record_copilot_turn(
    p_conversation_id UUID,
    p_usage_id UUID,
    p_prompt TEXT,
    p_answer TEXT
) RETURNS TABLE (
    usage_id UUID,
    user_message_id UUID,
    assistant_message_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
    v_user_message_id UUID := gen_random_uuid();
    v_assistant_message_id UUID := gen_random_uuid();
    v_model_name VARCHAR(100);
    v_input_tokens INTEGER;
    v_output_tokens INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.bio_copilot_conversations AS conversation
        WHERE conversation.bio_conversation_id = p_conversation_id
          AND conversation.bio_researcher_id = v_actor_id
          AND conversation.bio_is_active
    ) THEN
        RAISE EXCEPTION 'active copilot conversation not found' USING ERRCODE = '42501';
    END IF;

    SELECT usage.bio_model_name, usage.bio_input_tokens, usage.bio_output_tokens
    INTO v_model_name, v_input_tokens, v_output_tokens
    FROM public.bio_copilot_usage AS usage
    WHERE usage.bio_copilot_usage_id = p_usage_id
      AND usage.bio_researcher_id = v_actor_id
      AND usage.bio_prompt_text = p_prompt
      AND usage.bio_response_text = p_answer;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'copilot audit row does not match the authenticated turn'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.bio_copilot_messages (
        bio_message_id,
        bio_conversation_id,
        bio_researcher_id,
        bio_sender_role,
        bio_message_text
    ) VALUES (
        v_user_message_id,
        p_conversation_id,
        v_actor_id,
        'user',
        p_prompt
    );

    INSERT INTO public.bio_copilot_messages (
        bio_message_id,
        bio_conversation_id,
        bio_researcher_id,
        bio_sender_role,
        bio_message_text,
        bio_model_name,
        bio_input_tokens,
        bio_output_tokens,
        bio_copilot_usage_id
    ) VALUES (
        v_assistant_message_id,
        p_conversation_id,
        NULL,
        'assistant',
        p_answer,
        v_model_name,
        v_input_tokens,
        v_output_tokens,
        p_usage_id
    );

    UPDATE public.bio_copilot_conversations
    SET bio_updated_at = now(),
        bio_title = CASE
            WHEN bio_title = 'Nueva consulta' THEN left(p_prompt, 120)
            ELSE bio_title
        END
    WHERE bio_conversation_id = p_conversation_id;

    RETURN QUERY
    SELECT p_usage_id, v_user_message_id, v_assistant_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_delete_copilot_conversation(
    p_conversation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    UPDATE public.bio_copilot_conversations
    SET bio_is_active = false,
        bio_archived_at = now(),
        bio_updated_at = now()
    WHERE bio_conversation_id = p_conversation_id
      AND bio_researcher_id = v_actor_id
      AND bio_is_active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'active copilot conversation not found' USING ERRCODE = '42501';
    END IF;
END;
$$;

-- Migration 004 created this function while acting as postgres, so return to
-- the session role before replacing it and then restore the application owner.
RESET ROLE;
DROP FUNCTION IF EXISTS bio_fn_copilot_usage_summary();
SET ROLE bio_owner;
CREATE FUNCTION bio_fn_copilot_usage_summary()
RETURNS TABLE (
    researcher_id UUID,
    total_queries BIGINT,
    total_tokens BIGINT,
    last_query_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT usage.bio_researcher_id,
           count(*)::BIGINT AS total_queries,
           sum(usage.bio_input_tokens + usage.bio_output_tokens)::BIGINT AS total_tokens,
           max(usage.bio_created_at) AS last_query_at
    FROM public.bio_copilot_usage AS usage
    GROUP BY usage.bio_researcher_id;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_log_copilot_usage(
    TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_create_copilot_conversation(VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_record_copilot_turn(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_copilot_usage_summary() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION bio_fn_log_copilot_usage(
    TEXT, TEXT, VARCHAR, VARCHAR, INTEGER, INTEGER, UUID[], NUMERIC[]
) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_create_copilot_conversation(VARCHAR) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_record_copilot_turn(UUID, UUID, TEXT, TEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_copilot_usage_summary() TO bio_app_user;

RESET ROLE;
