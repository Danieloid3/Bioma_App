BEGIN;

DO $$
DECLARE
    v_researcher_id UUID := (
        SELECT bio_researcher_id
        FROM bio_researchers
        WHERE bio_email = 'valentina.rios@yarumo.org'
    );
    v_family_id UUID := gen_random_uuid();
    v_original_id UUID;
    v_parent_id UUID;
    v_original_used_at TIMESTAMPTZ;
BEGIN
    v_original_id := bio_fn_create_refresh_token(
        v_researcher_id,
        repeat('d', 64),
        v_family_id,
        now() + INTERVAL '1 day',
        NULL
    );
    PERFORM bio_fn_rotate_refresh_token(
        repeat('d', 64), repeat('e', 64), now() + INTERVAL '2 days'
    );

    SELECT bio_parent_refresh_token_id
    INTO v_parent_id
    FROM bio_refresh_tokens
    WHERE bio_token_hash = repeat('e', 64);

    SELECT bio_used_at
    INTO v_original_used_at
    FROM bio_refresh_tokens
    WHERE bio_refresh_token_id = v_original_id;

    IF v_parent_id <> v_original_id OR v_original_used_at IS NULL THEN
        RAISE EXCEPTION 'Refresh rotation failure: token lineage or used timestamp is invalid';
    END IF;
END;
$$;

ROLLBACK;
