-- =============================================================================
-- 008_fix_chat_message_counter.sql
-- The canonical view joined every active member before counting messages.
-- Because a member can see all members of their channel, each message was
-- counted once per participant (a 3-member channel showed 3 messages).
-- =============================================================================

SET ROLE bio_owner;

CREATE OR REPLACE VIEW bio_v_my_chat_conversations
WITH (security_invoker = true) AS
SELECT
    c.bio_chat_channel_id AS channel_id,
    c.bio_channel_type,
    c.bio_name,
    c.bio_created_at,
    c.bio_updated_at,
    count(m.bio_chat_message_id) FILTER (WHERE NOT m.bio_is_deleted) AS message_count,
    max(m.bio_created_at) AS last_message_at
FROM public.bio_chat_channels AS c
LEFT JOIN public.bio_chat_messages AS m
    ON m.bio_chat_channel_id = c.bio_chat_channel_id
WHERE EXISTS (
    SELECT 1
    FROM public.bio_chat_channel_members AS mine
    WHERE mine.bio_chat_channel_id = c.bio_chat_channel_id
      AND mine.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
      AND mine.bio_left_at IS NULL
)
GROUP BY c.bio_chat_channel_id, c.bio_channel_type, c.bio_name, c.bio_created_at, c.bio_updated_at;

GRANT SELECT ON public.bio_v_my_chat_conversations TO bio_app_user;

RESET ROLE;
