-- =============================================================================
-- 004_hotfix_copilot.sql
-- Hotfix: (1) create missing bio_fn_copilot_usage_summary()
--         (2) fix bio_fn_claim/store/mark_chat_embedding_* by removing
--             FORCE ROW LEVEL SECURITY from bio_chat_messages so the
--             postgres owner (embedding worker) can bypass RLS correctly
--             while bio_app_user remains fully policy-restricted.
-- =============================================================================

SET ROLE postgres;

-- ---------------------------------------------------------------------------
-- 1. bio_fn_copilot_usage_summary (was missing entirely from migrations)
--    Returns aggregate usage metrics for the calling researcher via RLS.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bio_fn_copilot_usage_summary()
RETURNS TABLE (
    conversations_total   BIGINT,
    conversations_30d     BIGINT,
    turns_total           BIGINT,
    turns_30d             BIGINT,
    input_tokens_30d      BIGINT,
    output_tokens_30d     BIGINT
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::uuid;
BEGIN
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0001';
    END IF;
    RETURN QUERY
    SELECT
        COUNT(DISTINCT c.bio_conversation_id)::BIGINT,
        COUNT(DISTINCT c.bio_conversation_id) FILTER (WHERE c.bio_created_at >= now() - INTERVAL '30 days')::BIGINT,
        COALESCE(SUM(u.bio_turn_count), 0)::BIGINT,
        COALESCE(SUM(u.bio_turn_count) FILTER (WHERE u.bio_asked_at >= now() - INTERVAL '30 days'), 0)::BIGINT,
        COALESCE(SUM(u.bio_input_tokens) FILTER (WHERE u.bio_asked_at >= now() - INTERVAL '30 days'), 0)::BIGINT,
        COALESCE(SUM(u.bio_output_tokens) FILTER (WHERE u.bio_asked_at >= now() - INTERVAL '30 days'), 0)::BIGINT
    FROM public.bio_copilot_conversations c
    LEFT JOIN public.bio_copilot_usage u ON u.bio_conversation_id = c.bio_conversation_id
    WHERE c.bio_researcher_id = v_actor_id;
END;
$$;

GRANT EXECUTE ON FUNCTION bio_fn_copilot_usage_summary() TO bio_app_user;

-- ---------------------------------------------------------------------------
-- 2. Fix embedding worker RLS bypass
--    bio_chat_messages had FORCE ROW LEVEL SECURITY which prevents the
--    postgres owner from bypassing RLS even inside SECURITY DEFINER functions.
--    Removing FORCE is correct: RLS (ENABLE) remains active for bio_app_user
--    and bio_owner; only the table owner (postgres) is now unrestricted.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bio_chat_messages NO FORCE ROW LEVEL SECURITY;

-- Rebuild the three worker functions cleanly (body unchanged, just idempotent)
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

RESET ROLE;
