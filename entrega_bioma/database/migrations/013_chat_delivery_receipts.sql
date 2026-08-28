-- 013_chat_delivery_receipts.sql
-- Expose both delivered and read receipt counts for WhatsApp-style status.

SET ROLE bio_owner;
DROP FUNCTION IF EXISTS bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER);

CREATE FUNCTION bio_fn_chat_history(
    p_channel_id UUID,
    p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
    p_cursor_message_id UUID DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
    message_id UUID, channel_id UUID, author_id UUID, author_name VARCHAR,
    message_text TEXT, sender_role VARCHAR, is_edited BOOLEAN, is_deleted BOOLEAN,
    created_at TIMESTAMPTZ, delivered_count BIGINT, read_count BIGINT, citations JSONB
)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
BEGIN
    IF NOT bio_fn_is_chat_member(p_channel_id) THEN RETURN; END IF;
    IF p_limit NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'chat history limit must be between 1 and 100' USING ERRCODE = '22023';
    END IF;
    IF (p_cursor_created_at IS NULL) <> (p_cursor_message_id IS NULL) THEN
        RAISE EXCEPTION 'chat history cursor must include timestamp and message id' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT message.bio_chat_message_id, message.bio_chat_channel_id,
           message.bio_author_researcher_id,
           coalesce(researcher.bio_full_name, 'Copiloto Bioma')::VARCHAR,
           CASE WHEN message.bio_is_deleted THEN 'Este mensaje fue eliminado' ELSE message.bio_message_text END,
           message.bio_sender_role, message.bio_is_edited, message.bio_is_deleted,
           message.bio_created_at,
           (SELECT count(*)::BIGINT FROM public.bio_chat_message_receipts receipt
            WHERE receipt.bio_chat_message_id = message.bio_chat_message_id),
           (SELECT count(*)::BIGINT FROM public.bio_chat_message_receipts receipt
            WHERE receipt.bio_chat_message_id = message.bio_chat_message_id AND receipt.bio_read_at IS NOT NULL),
           coalesce((SELECT jsonb_agg(jsonb_build_object(
               'type', citation.bio_source_type, 'reference', citation.bio_source_reference,
               'id', citation.bio_source_id) ORDER BY citation.bio_rank)
            FROM public.bio_chat_copilot_citations citation
            WHERE citation.bio_chat_message_id = message.bio_chat_message_id), '[]'::JSONB)
    FROM public.bio_chat_messages message
    LEFT JOIN public.bio_researchers researcher
      ON researcher.bio_researcher_id = message.bio_author_researcher_id
    WHERE message.bio_chat_channel_id = p_channel_id
      AND (p_cursor_created_at IS NULL OR (message.bio_created_at, message.bio_chat_message_id)
           < (p_cursor_created_at, p_cursor_message_id))
    ORDER BY message.bio_created_at DESC, message.bio_chat_message_id DESC
    LIMIT p_limit;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_chat_history(UUID, TIMESTAMPTZ, UUID, INTEGER) TO bio_app_user;
RESET ROLE;
