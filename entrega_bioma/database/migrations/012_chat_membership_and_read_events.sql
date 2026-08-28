-- 012_chat_membership_and_read_events.sql
-- Safe group membership mutations and explicit read-receipt event support.

SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_fn_add_chat_members(
    p_channel_id UUID,
    p_member_ids UUID[]
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.bio_chat_channels c
        JOIN public.bio_chat_channel_members m ON m.bio_chat_channel_id = c.bio_chat_channel_id
        WHERE c.bio_chat_channel_id = p_channel_id
          AND c.bio_channel_type = 'group' AND c.bio_is_active
          AND m.bio_researcher_id = v_actor AND m.bio_member_role = 'owner' AND m.bio_left_at IS NULL
    ) THEN
        RAISE EXCEPTION 'only an active group owner may add members' USING ERRCODE = 'P0004';
    END IF;
    IF p_member_ids IS NULL OR cardinality(p_member_ids) = 0 THEN
        RAISE EXCEPTION 'at least one member is required' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(p_member_ids) id
        LEFT JOIN public.bio_researchers r ON r.bio_researcher_id = id
        WHERE r.bio_researcher_id IS NULL OR NOT r.bio_is_active
    ) THEN
        RAISE EXCEPTION 'all members must be active researchers' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.bio_chat_channel_members (bio_chat_channel_id, bio_researcher_id, bio_member_role, bio_left_at)
    SELECT p_channel_id, id, 'member', NULL
    FROM (SELECT DISTINCT unnest(p_member_ids) AS id) selected
    ON CONFLICT (bio_chat_channel_id, bio_researcher_id)
    DO UPDATE SET bio_left_at = NULL
    WHERE public.bio_chat_channel_members.bio_member_role <> 'owner';
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_leave_chat_channel(p_channel_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::UUID;
    v_is_owner BOOLEAN;
BEGIN
    SELECT m.bio_member_role = 'owner' INTO v_is_owner
    FROM public.bio_chat_channel_members m
    WHERE m.bio_chat_channel_id = p_channel_id
      AND m.bio_researcher_id = v_actor AND m.bio_left_at IS NULL;
    IF v_is_owner IS NULL THEN
        RAISE EXCEPTION 'channel membership not found' USING ERRCODE = 'P0004';
    END IF;
    IF v_is_owner AND EXISTS (
        SELECT 1 FROM public.bio_chat_channel_members
        WHERE bio_chat_channel_id = p_channel_id
          AND bio_left_at IS NULL AND bio_researcher_id <> v_actor
    ) THEN
        RAISE EXCEPTION 'the group owner must transfer ownership before leaving' USING ERRCODE = 'P0004';
    END IF;
    UPDATE public.bio_chat_channel_members
    SET bio_left_at = clock_timestamp()
    WHERE bio_chat_channel_id = p_channel_id
      AND bio_researcher_id = v_actor AND bio_left_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_add_chat_members(UUID, UUID[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_leave_chat_channel(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_add_chat_members(UUID, UUID[]) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_leave_chat_channel(UUID) TO bio_app_user;

RESET ROLE;
