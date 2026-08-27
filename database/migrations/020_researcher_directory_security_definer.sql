SET ROLE bio_owner;

-- The directory intentionally exposes only its narrow returned projection.
-- It must not grant bio_app_user direct SELECT on researcher emails, password
-- hashes or other private account data.
CREATE OR REPLACE FUNCTION bio_fn_researcher_directory()
RETURNS TABLE (
    researcher_id UUID, full_name VARCHAR, role_title VARCHAR,
    accreditation_level SMALLINT, avatar_key VARCHAR
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title,
           r.bio_accreditation_level, r.bio_avatar_key
    FROM public.bio_researchers AS r
    WHERE r.bio_is_active = true
    ORDER BY r.bio_full_name, r.bio_researcher_id;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_researcher_directory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_researcher_directory() TO bio_app_user;

RESET ROLE;
