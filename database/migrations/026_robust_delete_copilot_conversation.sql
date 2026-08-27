SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_fn_delete_copilot_conversation(
    p_conversation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'authenticated actor is required' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.bio_copilot_conversations
    SET bio_is_active = false,
        bio_archived_at = now(),
        bio_updated_at = now()
    WHERE bio_conversation_id = p_conversation_id
      AND bio_researcher_id = v_actor_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'conversation not found, already archived, or not owned by actor' USING ERRCODE = 'P0004';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_delete_copilot_conversation(UUID) TO bio_app_user;

RESET ROLE;