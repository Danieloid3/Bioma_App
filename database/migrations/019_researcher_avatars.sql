SET ROLE bio_owner;

-- A finite key, rather than a client-provided image URL, keeps researcher
-- avatars presentational and lets the client render its vetted local library.
ALTER TABLE bio_researchers ADD COLUMN bio_avatar_key VARCHAR(32);

WITH available_keys(avatar_key, position) AS (
    VALUES
        ('spectacled_bear', 1),
        ('andean_condor', 2),
        ('golden_poison_frog', 3),
        ('jaguar', 4),
        ('hummingbird', 5),
        ('cotton_top_tamarin', 6),
        ('green_iguana', 7),
        ('mountain_tapir', 8)
), ordered_researchers AS (
    SELECT bio_researcher_id,
           row_number() OVER (ORDER BY bio_created_at, bio_researcher_id) AS position
    FROM bio_researchers
)
UPDATE bio_researchers AS researcher
SET bio_avatar_key = available_keys.avatar_key
FROM ordered_researchers
JOIN available_keys
  ON available_keys.position = 1 + ((ordered_researchers.position - 1) % 8)
WHERE researcher.bio_researcher_id = ordered_researchers.bio_researcher_id;

ALTER TABLE bio_researchers
    ALTER COLUMN bio_avatar_key SET NOT NULL,
    ADD CONSTRAINT ck_bio_researchers_avatar_key CHECK (
        bio_avatar_key IN (
            'spectacled_bear', 'andean_condor', 'golden_poison_frog', 'jaguar',
            'hummingbird', 'cotton_top_tamarin', 'green_iguana', 'mountain_tapir'
        )
    );

-- PostgreSQL cannot replace a function when its OUT columns change, so these
-- are recreated in this migration and their least-privilege grants restored.
DROP FUNCTION bio_fn_get_researcher_for_login(CITEXT);
CREATE FUNCTION bio_fn_get_researcher_for_login(p_email CITEXT)
RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, email CITEXT, password_hash VARCHAR,
    role_title VARCHAR, accreditation_level SMALLINT, avatar_key VARCHAR, is_active BOOLEAN
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_email, r.bio_password_hash,
           r.bio_role_title, r.bio_accreditation_level, r.bio_avatar_key, r.bio_is_active
    FROM public.bio_researchers AS r
    WHERE r.bio_email = p_email;
$$;

DROP FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ);
CREATE FUNCTION bio_fn_rotate_refresh_token(
    p_current_token_hash VARCHAR(255),
    p_next_token_hash VARCHAR(255),
    p_next_expires_at TIMESTAMPTZ
) RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, role_title VARCHAR,
    accreditation_level SMALLINT, avatar_key VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_token public.bio_refresh_tokens%ROWTYPE;
BEGIN
    SELECT * INTO v_token
    FROM public.bio_refresh_tokens
    WHERE bio_token_hash = p_current_token_hash
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'refresh token is invalid' USING ERRCODE = 'P0008';
    END IF;
    IF v_token.bio_used_at IS NOT NULL OR v_token.bio_revoked_at IS NOT NULL OR v_token.bio_expires_at <= now() THEN
        UPDATE public.bio_refresh_tokens
        SET bio_revoked_at = COALESCE(bio_revoked_at, now()),
            bio_revocation_reason = COALESCE(bio_revocation_reason, 'reuse_detected')
        WHERE bio_token_family_id = v_token.bio_token_family_id
          AND bio_revoked_at IS NULL;
        RAISE EXCEPTION 'refresh token reuse or expiry detected' USING ERRCODE = 'P0009';
    END IF;
    UPDATE public.bio_refresh_tokens
    SET bio_used_at = now(), bio_revoked_at = now(), bio_revocation_reason = 'rotated'
    WHERE bio_refresh_token_id = v_token.bio_refresh_token_id;
    PERFORM public.bio_fn_create_refresh_token(
        v_token.bio_researcher_id, p_next_token_hash, v_token.bio_token_family_id,
        p_next_expires_at, v_token.bio_refresh_token_id
    );
    RETURN QUERY
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title,
           r.bio_accreditation_level, r.bio_avatar_key
    FROM public.bio_researchers AS r
    WHERE r.bio_researcher_id = v_token.bio_researcher_id AND r.bio_is_active;
END;
$$;

DROP FUNCTION bio_fn_researcher_directory();
CREATE FUNCTION bio_fn_researcher_directory()
RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, role_title VARCHAR,
    accreditation_level SMALLINT, avatar_key VARCHAR
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title,
           r.bio_accreditation_level, r.bio_avatar_key
    FROM public.bio_researchers AS r
    WHERE r.bio_is_active = true
    ORDER BY r.bio_full_name, r.bio_researcher_id;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_get_researcher_for_login(CITEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_researcher_directory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_get_researcher_for_login(CITEXT) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_researcher_directory() TO bio_app_user;

RESET ROLE;
