BEGIN;

SELECT set_config(
    'app.current_user_id',
    (SELECT bio_researcher_id::TEXT FROM bio_researchers WHERE bio_email = 'camila.andrade@yarumo.org'),
    true
);

DO $$
DECLARE
    v_active_count INTEGER;
BEGIN
    SELECT count(*) INTO v_active_count FROM bio_fn_list_system_prompt_versions() WHERE is_active;
    IF v_active_count <> 3 THEN
        RAISE EXCEPTION 'Prompt version failure: expected three active prompt scopes, got %', v_active_count;
    END IF;
END;
$$;

DO $$
BEGIN
    PERFORM set_config(
        'app.current_user_id',
        (SELECT bio_researcher_id::TEXT FROM bio_researchers WHERE bio_email = 'valentina.rios@yarumo.org'),
        true
    );
    BEGIN
        PERFORM * FROM bio_fn_list_system_prompt_versions();
        RAISE EXCEPTION 'Prompt version failure: a non-admin listed prompt versions';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
END;
$$;

ROLLBACK;
