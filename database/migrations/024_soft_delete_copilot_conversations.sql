SET ROLE bio_owner;

-- Soft delete / archival for copilot conversations (no physical DELETE for audit persistence)

ALTER TABLE bio_copilot_conversations
    ADD COLUMN IF NOT EXISTS bio_is_active BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS bio_archived_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS ix_bio_copilot_conversations_active
    ON bio_copilot_conversations (bio_researcher_id, bio_is_active, bio_updated_at DESC);

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
    WHERE c.bio_is_active = true
    GROUP BY c.bio_conversation_id, c.bio_title, c.bio_created_at, c.bio_updated_at
    ORDER BY c.bio_updated_at DESC
    LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION bio_fn_delete_copilot_conversation(
    p_conversation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    UPDATE public.bio_copilot_conversations
    SET bio_is_active = false,
        bio_archived_at = now(),
        bio_updated_at = now()
    WHERE bio_conversation_id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION bio_fn_list_copilot_conversations(INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) TO bio_app_user;

RESET ROLE;