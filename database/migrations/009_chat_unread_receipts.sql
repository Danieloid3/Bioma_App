-- 009_chat_unread_receipts.sql
-- Per-actor unread counts and read receipts when a channel is opened.

SET ROLE bio_owner;

CREATE OR REPLACE VIEW bio_v_my_chat_conversations
WITH (security_invoker = true) AS
SELECT c.bio_chat_channel_id AS channel_id, c.bio_channel_type, c.bio_name,
       c.bio_created_at, c.bio_updated_at,
       count(m.bio_chat_message_id) FILTER (WHERE NOT m.bio_is_deleted) AS message_count,
       max(m.bio_created_at) AS last_message_at,
       count(m.bio_chat_message_id) FILTER (
           WHERE NOT m.bio_is_deleted AND EXISTS (
               SELECT 1 FROM public.bio_chat_message_receipts unread
               WHERE unread.bio_chat_message_id = m.bio_chat_message_id
                 AND unread.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
                 AND unread.bio_read_at IS NULL
           )
       ) AS unread_count
FROM public.bio_chat_channels c
LEFT JOIN public.bio_chat_messages m ON m.bio_chat_channel_id = c.bio_chat_channel_id
WHERE EXISTS (
    SELECT 1 FROM public.bio_chat_channel_members mine
    WHERE mine.bio_chat_channel_id = c.bio_chat_channel_id
      AND mine.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
      AND mine.bio_left_at IS NULL
)
GROUP BY c.bio_chat_channel_id, c.bio_channel_type, c.bio_name, c.bio_created_at, c.bio_updated_at;

CREATE OR REPLACE FUNCTION bio_fn_mark_chat_channel_read(p_channel_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_actor_id UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.bio_chat_channel_members
        WHERE bio_chat_channel_id = p_channel_id AND bio_researcher_id = v_actor_id AND bio_left_at IS NULL
    ) THEN RETURN; END IF;
    UPDATE public.bio_chat_message_receipts receipt
    SET bio_read_at = COALESCE(receipt.bio_read_at, clock_timestamp())
    FROM public.bio_chat_messages message
    WHERE receipt.bio_chat_message_id = message.bio_chat_message_id
      AND receipt.bio_researcher_id = v_actor_id
      AND message.bio_chat_channel_id = p_channel_id
      AND receipt.bio_read_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_mark_chat_channel_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_mark_chat_channel_read(UUID) TO bio_app_user;
GRANT SELECT ON public.bio_v_my_chat_conversations TO bio_app_user;
RESET ROLE;
