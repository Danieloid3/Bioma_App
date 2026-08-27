-- =============================================================================
-- 007_repair_refresh_token_rotation.sql
-- Restores the refresh-token function contract consumed by the backend and
-- the canonical parent/child rotation direction lost during consolidation.
-- =============================================================================

SET ROLE bio_owner;

DROP FUNCTION IF EXISTS bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ);
CREATE FUNCTION bio_fn_rotate_refresh_token(
    p_current_token_hash VARCHAR,
    p_new_token_hash VARCHAR,
    p_new_expires_at TIMESTAMPTZ
) RETURNS TABLE (
    researcher_id UUID,
    full_name VARCHAR,
    role_title VARCHAR,
    accreditation_level SMALLINT,
    avatar_key VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_token public.bio_refresh_tokens%ROWTYPE;
    v_new_token_id UUID := gen_random_uuid();
BEGIN
    SELECT token.*
    INTO v_token
    FROM public.bio_refresh_tokens AS token
    WHERE token.bio_token_hash = p_current_token_hash
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'refresh token is invalid' USING ERRCODE = 'P0008';
    END IF;
    IF v_token.bio_used_at IS NOT NULL
       OR v_token.bio_revoked_at IS NOT NULL
       OR v_token.bio_expires_at <= now() THEN
        -- The repository catches P0009 and revokes the family in a separate
        -- statement because an exception rolls back writes in this function.
        RAISE EXCEPTION 'refresh token reuse or expiry detected' USING ERRCODE = 'P0009';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.bio_researchers AS researcher
        WHERE researcher.bio_researcher_id = v_token.bio_researcher_id
          AND researcher.bio_is_active
    ) THEN
        RAISE EXCEPTION 'refresh token is invalid' USING ERRCODE = 'P0008';
    END IF;
    IF p_new_expires_at <= now() THEN
        RAISE EXCEPTION 'new refresh token expiry must be in the future'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.bio_refresh_tokens
    SET bio_used_at = now(),
        bio_revoked_at = now(),
        bio_revocation_reason = 'rotated'
    WHERE bio_refresh_token_id = v_token.bio_refresh_token_id;

    INSERT INTO public.bio_refresh_tokens (
        bio_refresh_token_id,
        bio_researcher_id,
        bio_token_family_id,
        bio_parent_refresh_token_id,
        bio_token_hash,
        bio_expires_at
    ) VALUES (
        v_new_token_id,
        v_token.bio_researcher_id,
        v_token.bio_token_family_id,
        v_token.bio_refresh_token_id,
        p_new_token_hash,
        p_new_expires_at
    );

    RETURN QUERY
    SELECT researcher.bio_researcher_id,
           researcher.bio_full_name,
           researcher.bio_role_title,
           researcher.bio_accreditation_level,
           researcher.bio_avatar_key
    FROM public.bio_researchers AS researcher
    WHERE researcher.bio_researcher_id = v_token.bio_researcher_id
      AND researcher.bio_is_active;
END;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_rotate_refresh_token(VARCHAR, VARCHAR, TIMESTAMPTZ) TO bio_app_user;

RESET ROLE;
