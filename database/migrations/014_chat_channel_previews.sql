-- 014_chat_channel_previews.sql
-- Return the most recent message preview for each channel shown to a member.
-- The view remains SECURITY INVOKER and its membership predicate stays in the
-- query, so a preview cannot reveal a channel or message outside RLS access.

SET ROLE bio_owner;

CREATE OR REPLACE VIEW public.bio_v_my_chat_conversations
WITH (security_invoker = true) AS
SELECT
    channel.bio_chat_channel_id AS channel_id,
    channel.bio_channel_type,
    channel.bio_name,
    channel.bio_created_at,
    channel.bio_updated_at,
    count(message.bio_chat_message_id) FILTER (WHERE NOT message.bio_is_deleted) AS message_count,
    max(message.bio_created_at) AS last_message_at,
    count(message.bio_chat_message_id) FILTER (
        WHERE NOT message.bio_is_deleted
          AND EXISTS (
              SELECT 1
              FROM public.bio_chat_message_receipts AS unread
              WHERE unread.bio_chat_message_id = message.bio_chat_message_id
                AND unread.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
                AND unread.bio_read_at IS NULL
          )
    ) AS unread_count,
    latest.last_message_preview
FROM public.bio_chat_channels AS channel
LEFT JOIN public.bio_chat_messages AS message
  ON message.bio_chat_channel_id = channel.bio_chat_channel_id
LEFT JOIN LATERAL (
    SELECT CASE
        WHEN newest.bio_is_deleted THEN 'Este mensaje fue eliminado'
        ELSE newest.bio_message_text
    END AS last_message_preview
    FROM public.bio_chat_messages AS newest
    WHERE newest.bio_chat_channel_id = channel.bio_chat_channel_id
    ORDER BY newest.bio_created_at DESC, newest.bio_chat_message_id DESC
    LIMIT 1
) AS latest ON true
WHERE EXISTS (
    SELECT 1
    FROM public.bio_chat_channel_members AS mine
    WHERE mine.bio_chat_channel_id = channel.bio_chat_channel_id
      AND mine.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
      AND mine.bio_left_at IS NULL
)
GROUP BY
    channel.bio_chat_channel_id,
    channel.bio_channel_type,
    channel.bio_name,
    channel.bio_created_at,
    channel.bio_updated_at,
    latest.last_message_preview;

RESET ROLE;
