SET ROLE bio_owner;

-- Catalogue imagery is curated separately from sighting evidence.  An image can
-- be credited, licensed and replaced without changing scientific taxonomy.
CREATE TABLE bio_species_images (
    bio_species_image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_species_id UUID NOT NULL REFERENCES bio_species (bio_species_id) ON DELETE RESTRICT,
    bio_display_url TEXT NOT NULL CHECK (bio_display_url ~ '^https://'),
    bio_source_url TEXT NOT NULL CHECK (bio_source_url ~ '^https://'),
    bio_alt_text_es VARCHAR(300) NOT NULL CHECK (length(btrim(bio_alt_text_es)) > 0),
    bio_alt_text_en VARCHAR(300) NOT NULL CHECK (length(btrim(bio_alt_text_en)) > 0),
    bio_attribution TEXT NOT NULL CHECK (length(btrim(bio_attribution)) > 0),
    bio_license_code VARCHAR(40) NOT NULL CHECK (length(btrim(bio_license_code)) > 0),
    bio_license_url TEXT NOT NULL CHECK (bio_license_url ~ '^https://'),
    bio_is_featured BOOLEAN NOT NULL DEFAULT false,
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uix_bio_species_images_featured_active
    ON bio_species_images (bio_species_id)
    WHERE bio_is_featured AND bio_is_active;

CREATE INDEX ix_bio_species_images_species_active
    ON bio_species_images (bio_species_id)
    WHERE bio_is_active;

CREATE TRIGGER bio_species_images_set_updated_at
BEFORE UPDATE ON bio_species_images
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();

-- These are catalogue images only. They carry their source and licence so the
-- client can present attribution; no observation evidence is exposed here.
INSERT INTO bio_species_images (
    bio_species_id, bio_display_url, bio_source_url, bio_alt_text_es, bio_alt_text_en,
    bio_attribution, bio_license_code, bio_license_url, bio_is_featured
)
SELECT bio_species_id, v.display_url, v.source_url, v.alt_es, v.alt_en,
       v.attribution, v.license_code, v.license_url, true
FROM bio_species AS s
JOIN (VALUES
    ('Phyllobates terribilis', 'https://upload.wikimedia.org/wikipedia/commons/9/96/Phyllobates_terribilis_01.JPG', 'https://commons.wikimedia.org/wiki/File:Phyllobates_terribilis_01.JPG', 'Rana dorada venenosa sobre hojarasca.', 'Golden poison frog on leaf litter.', 'The Lord of the Allosaurs / Wikimedia Commons', 'CC-BY-SA-3.0', 'https://creativecommons.org/licenses/by-sa/3.0/'),
    ('Tremarctos ornatus', 'https://inaturalist-open-data.s3.amazonaws.com/photos/187383867/medium.jpg', 'https://www.inaturalist.org/taxa/42051-Tremarctos-ornatus', 'Oso de anteojos en su hábitat.', 'Spectacled bear in its habitat.', '*snowwhite* / iNaturalist', 'CC-BY-NC-SA', 'https://creativecommons.org/licenses/by-nc-sa/4.0/'),
    ('Vultur gryphus', 'https://inaturalist-open-data.s3.amazonaws.com/photos/90906598/medium.jpg', 'https://www.inaturalist.org/taxa/5270-Vultur-gryphus', 'Cóndor de los Andes en vuelo.', 'Andean condor in flight.', 'Juan Rodolfo Lillo Lobos / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/'),
    ('Colibri coruscans', 'https://inaturalist-open-data.s3.amazonaws.com/photos/444300759/medium.jpg', 'https://www.inaturalist.org/taxa/9759-Colibri-coruscans', 'Colibrí chillón posado.', 'Sparkling violetear perched.', 'Tony Iwane / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/'),
    ('Saguinus oedipus', 'https://inaturalist-open-data.s3.amazonaws.com/photos/39541285/medium.jpg', 'https://www.inaturalist.org/taxa/41843-Saguinus-oedipus', 'Tití cabeciblanco.', 'Cotton-top tamarin.', 'Heather Pickard / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/'),
    ('Iguana iguana', 'https://inaturalist-open-data.s3.amazonaws.com/photos/356025444/medium.jpg', 'https://www.inaturalist.org/taxa/36229-Iguana-iguana', 'Iguana verde.', 'Green iguana.', 'Rainer Hungershausen / iNaturalist', 'CC-BY-NC-ND', 'https://creativecommons.org/licenses/by-nc-nd/4.0/')
) AS v(scientific_name, display_url, source_url, alt_es, alt_en, attribution, license_code, license_url)
    ON s.bio_scientific_name = v.scientific_name;

-- Dashboard aggregates always start from bio_sightings, therefore the invoker's
-- RLS policy filters every number before it reaches the API.
CREATE FUNCTION bio_fn_dashboard_summary()
RETURNS TABLE (
    visible_sightings BIGINT,
    registered_species BIGINT,
    monitored_sites BIGINT,
    field_notes BIGINT
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT COUNT(*)::BIGINT,
           COUNT(DISTINCT s.bio_species_id)::BIGINT,
           COUNT(DISTINCT s.bio_site_id)::BIGINT,
           COUNT(*)::BIGINT
    FROM public.bio_sightings AS s
    WHERE s.bio_is_voided = false;
$$;

CREATE FUNCTION bio_fn_dashboard_classification()
RETURNS TABLE (classification_level SMALLINT, total BIGINT)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT s.bio_classification_level, COUNT(*)::BIGINT
    FROM public.bio_sightings AS s
    WHERE s.bio_is_voided = false
    GROUP BY s.bio_classification_level
    ORDER BY s.bio_classification_level;
$$;

CREATE FUNCTION bio_fn_dashboard_activity(p_limit INTEGER DEFAULT 6)
RETURNS TABLE (
    activity_type VARCHAR,
    researcher_name VARCHAR,
    observation_reference VARCHAR,
    species_common_name VARCHAR,
    occurred_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_limit NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION 'activity limit must be between 1 and 20' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT * FROM (
        SELECT 'created'::VARCHAR, author.bio_full_name, s.bio_observation_reference,
               sp.bio_common_name, s.bio_created_at
        FROM public.bio_sightings AS s
        JOIN public.bio_researchers AS author ON author.bio_researcher_id = s.bio_researcher_id
        JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
        UNION ALL
        SELECT r.bio_change_type, editor.bio_full_name, s.bio_observation_reference,
               sp.bio_common_name, r.bio_created_at
        FROM public.bio_sighting_revisions AS r
        JOIN public.bio_sightings AS s ON s.bio_sighting_id = r.bio_sighting_id
        JOIN public.bio_researchers AS editor ON editor.bio_researcher_id = r.bio_changed_by_researcher_id
        JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
    ) AS activity
    ORDER BY occurred_at DESC
    LIMIT p_limit;
END;
$$;

-- A deliberately minimal directory: contact details and credentials stay private.
CREATE FUNCTION bio_fn_researcher_directory()
RETURNS TABLE (researcher_id UUID, full_name VARCHAR, role_title VARCHAR, accreditation_level SMALLINT)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title, r.bio_accreditation_level
    FROM public.bio_researchers AS r
    WHERE r.bio_is_active = true
    ORDER BY r.bio_full_name, r.bio_researcher_id;
$$;

GRANT SELECT ON public.bio_species_images TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_summary() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_classification() TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_dashboard_activity(INTEGER) TO bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_researcher_directory() TO bio_app_user;

RESET ROLE;
