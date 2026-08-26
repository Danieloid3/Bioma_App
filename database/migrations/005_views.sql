SET ROLE bio_owner;

-- The invoker's RLS policy, never the view owner's, governs every row.
CREATE VIEW bio_v_visible_sightings
WITH (security_invoker = true, security_barrier = true)
AS
SELECT
    s.bio_sighting_id,
    s.bio_observation_reference,
    s.bio_researcher_id,
    r.bio_full_name AS bio_researcher_name,
    s.bio_species_id,
    sp.bio_common_name AS bio_species_common_name,
    sp.bio_scientific_name AS bio_species_scientific_name,
    sp.bio_iucn_category,
    s.bio_site_id,
    si.bio_site_name,
    si.bio_region,
    s.bio_observed_at,
    s.bio_exact_latitude,
    s.bio_exact_longitude,
    s.bio_classification_level,
    s.bio_field_notes,
    s.bio_embedding_status,
    s.bio_is_voided,
    s.bio_voided_at,
    s.bio_created_at,
    s.bio_updated_at
FROM bio_sightings AS s
JOIN bio_researchers AS r ON r.bio_researcher_id = s.bio_researcher_id
JOIN bio_species AS sp ON sp.bio_species_id = s.bio_species_id
JOIN bio_sites AS si ON si.bio_site_id = s.bio_site_id;

RESET ROLE;

