SET ROLE bio_owner;

-- These functions deliberately run as the caller. PostgreSQL RLS on
-- bio_sightings remains the sole authority for the current record, its exact
-- coordinates and the associated detail.
CREATE FUNCTION bio_fn_sighting_history_with_images(
    p_species_id UUID DEFAULT NULL,
    p_site_id UUID DEFAULT NULL,
    p_cursor_observed_at TIMESTAMPTZ DEFAULT NULL,
    p_cursor_sighting_id UUID DEFAULT NULL,
    p_page_size INTEGER DEFAULT 20,
    p_include_voided BOOLEAN DEFAULT false
) RETURNS TABLE (
    sighting_id UUID, observation_reference VARCHAR, researcher_name VARCHAR,
    species_common_name VARCHAR, site_name VARCHAR, classification_level SMALLINT,
    field_notes TEXT, is_voided BOOLEAN, observed_at TIMESTAMPTZ,
    image_url TEXT, image_alt_text_es VARCHAR
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_page_size NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'page size must be between 1 and 100' USING ERRCODE = '22023';
    END IF;
    IF (p_cursor_observed_at IS NULL) <> (p_cursor_sighting_id IS NULL) THEN
        RAISE EXCEPTION 'both cursor values are required together' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT s.bio_sighting_id, s.bio_observation_reference, r.bio_full_name,
           sp.bio_common_name, site.bio_site_name, s.bio_classification_level,
           s.bio_field_notes, s.bio_is_voided, s.bio_observed_at,
           image.bio_display_url, image.bio_alt_text_es
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS site ON site.bio_site_id = s.bio_site_id
    LEFT JOIN public.bio_species_images AS image
      ON image.bio_species_id = sp.bio_species_id
     AND image.bio_is_featured = true
     AND image.bio_is_active = true
    WHERE (p_species_id IS NULL OR s.bio_species_id = p_species_id)
      AND (p_site_id IS NULL OR s.bio_site_id = p_site_id)
      AND (p_include_voided OR s.bio_is_voided = false)
      AND (p_cursor_observed_at IS NULL OR (s.bio_observed_at, s.bio_sighting_id) <
           (p_cursor_observed_at, p_cursor_sighting_id))
    ORDER BY s.bio_observed_at DESC, s.bio_sighting_id DESC
    LIMIT p_page_size;
END;
$$;

CREATE FUNCTION bio_fn_get_sighting_detail(p_sighting_id UUID)
RETURNS TABLE (
    sighting_id UUID, observation_reference VARCHAR,
    researcher_id UUID, researcher_name VARCHAR,
    species_id UUID, species_common_name VARCHAR, species_scientific_name VARCHAR,
    species_iucn_category VARCHAR, site_id UUID, site_name VARCHAR, region VARCHAR,
    observed_at TIMESTAMPTZ, exact_latitude NUMERIC(9, 6), exact_longitude NUMERIC(10, 6),
    classification_level SMALLINT, field_notes TEXT, is_voided BOOLEAN,
    voided_at TIMESTAMPTZ, voided_by_researcher_id UUID, void_reason TEXT,
    created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
    image_url TEXT, image_alt_text_es VARCHAR, image_attribution TEXT,
    image_license_code VARCHAR, image_license_url TEXT
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT s.bio_sighting_id, s.bio_observation_reference,
           author.bio_researcher_id, author.bio_full_name,
           species.bio_species_id, species.bio_common_name, species.bio_scientific_name,
           species.bio_iucn_category, site.bio_site_id, site.bio_site_name, site.bio_region,
           s.bio_observed_at, s.bio_exact_latitude, s.bio_exact_longitude,
           s.bio_classification_level, s.bio_field_notes, s.bio_is_voided,
           s.bio_voided_at, s.bio_voided_by_researcher_id, s.bio_void_reason,
           s.bio_created_at, s.bio_updated_at,
           image.bio_display_url, image.bio_alt_text_es, image.bio_attribution,
           image.bio_license_code, image.bio_license_url
    FROM public.bio_sightings AS s
    JOIN public.bio_researchers AS author ON author.bio_researcher_id = s.bio_researcher_id
    JOIN public.bio_species AS species ON species.bio_species_id = s.bio_species_id
    JOIN public.bio_sites AS site ON site.bio_site_id = s.bio_site_id
    LEFT JOIN public.bio_species_images AS image
      ON image.bio_species_id = species.bio_species_id
     AND image.bio_is_featured = true
     AND image.bio_is_active = true
    WHERE s.bio_sighting_id = p_sighting_id;
$$;

REVOKE EXECUTE ON FUNCTION bio_fn_sighting_history_with_images(UUID, UUID, TIMESTAMPTZ, UUID, INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bio_fn_get_sighting_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_sighting_history_with_images(UUID, UUID, TIMESTAMPTZ, UUID, INTEGER, BOOLEAN) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_get_sighting_detail(UUID) TO bio_app_user;

RESET ROLE;
