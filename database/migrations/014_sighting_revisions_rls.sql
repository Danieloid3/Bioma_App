SET ROLE bio_owner;

-- Revisions contain historical coordinates and notes. Protect them with the same
-- visibility predicate as the current sighting before allowing dashboard activity.
ALTER TABLE bio_sighting_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY bio_sighting_revisions_select_policy ON bio_sighting_revisions
    FOR SELECT TO bio_app_user
    USING (
        EXISTS (
            SELECT 1
            FROM bio_sightings AS sighting
            WHERE sighting.bio_sighting_id = bio_sighting_revisions.bio_sighting_id
        )
    );

GRANT SELECT ON public.bio_sighting_revisions TO bio_app_user;

RESET ROLE;
