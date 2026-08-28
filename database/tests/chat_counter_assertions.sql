BEGIN;

SELECT set_config(
    'app.current_user_id',
    (SELECT bio_researcher_id::TEXT FROM bio_researchers WHERE bio_email = 'camila.andrade@yarumo.org'),
    true
);

DO $$
DECLARE
    v_channel_id UUID;
    v_message_id UUID;
    v_count BIGINT;
    v_unread BIGINT;
    v_preview TEXT;
BEGIN
    v_channel_id := bio_fn_create_chat_channel(
        'group', 'Counter assertion', ARRAY[
            (SELECT bio_researcher_id FROM bio_researchers WHERE bio_email = 'andres.londono@yarumo.org')
        ]
    );
    v_message_id := bio_fn_send_chat_message(v_channel_id, 'one message');

    SELECT message_count, unread_count, last_message_preview INTO v_count, v_unread, v_preview
    FROM bio_v_my_chat_conversations
    WHERE channel_id = v_channel_id;

    IF v_count <> 1 OR v_unread <> 0 OR v_preview <> 'one message' THEN
        RAISE EXCEPTION 'Chat channel preview failure: expected 1/0/one message, got %/%/%', v_count, v_unread, v_preview;
    END IF;
END;
$$;

ROLLBACK;
