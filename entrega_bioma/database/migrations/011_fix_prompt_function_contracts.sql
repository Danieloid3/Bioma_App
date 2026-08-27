SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_fn_get_active_system_prompt(p_scope VARCHAR)
RETURNS TABLE(version_key VARCHAR, prompt_text TEXT)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
    SELECT (bio_scope || '-v' || bio_version_number)::VARCHAR, bio_prompt_text
    FROM public.bio_system_prompt_versions
    WHERE bio_scope = p_scope AND bio_is_active;
$$;

CREATE OR REPLACE FUNCTION bio_fn_list_system_prompt_versions()
RETURNS TABLE(prompt_id UUID, scope VARCHAR, version_key VARCHAR, prompt_text TEXT, content_sha256 VARCHAR, is_active BOOLEAN, created_at TIMESTAMPTZ, created_by VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
    IF NOT bio_fn_is_current_admin() THEN RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT p.bio_system_prompt_version_id, p.bio_scope, (p.bio_scope || '-v' || p.bio_version_number)::VARCHAR,
        p.bio_prompt_text, p.bio_content_sha256, p.bio_is_active, p.bio_created_at, r.bio_full_name
    FROM public.bio_system_prompt_versions p JOIN public.bio_researchers r ON r.bio_researcher_id=p.bio_created_by_researcher_id
    ORDER BY p.bio_scope, p.bio_version_number DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION bio_fn_get_active_system_prompt(VARCHAR), bio_fn_list_system_prompt_versions() TO bio_app_user;
RESET ROLE;
