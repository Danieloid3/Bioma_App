-- Membership mutations stay behind PostgreSQL authorization checks.
BEGIN;
SELECT set_config('app.current_user_id', (SELECT bio_researcher_id::text FROM bio_researchers WHERE bio_email = 'camila.andrade@yarumo.org'), true);
DO $$
DECLARE
    v_channel UUID;
    v_nestor UUID := (SELECT bio_researcher_id FROM bio_researchers WHERE bio_email = 'nestor.quinones@yarumo.org');
    v_valentina UUID := (SELECT bio_researcher_id FROM bio_researchers WHERE bio_email = 'valentina.rios@yarumo.org');
BEGIN
    v_channel := bio_fn_create_chat_channel('group', 'RLS membership test', ARRAY[v_nestor]);
    PERFORM bio_fn_add_chat_members(v_channel, ARRAY[v_valentina]);
    IF NOT EXISTS (SELECT 1 FROM bio_chat_channel_members WHERE bio_chat_channel_id = v_channel AND bio_researcher_id = v_valentina AND bio_left_at IS NULL) THEN
        RAISE EXCEPTION 'owner could not add an active member';
    END IF;
    PERFORM set_config('app.current_user_id', v_valentina::text, true);
    PERFORM bio_fn_leave_chat_channel(v_channel);
    IF EXISTS (SELECT 1 FROM bio_chat_channel_members WHERE bio_chat_channel_id = v_channel AND bio_researcher_id = v_valentina AND bio_left_at IS NULL) THEN
        RAISE EXCEPTION 'member could not leave the group';
    END IF;
END;
$$;
ROLLBACK;
