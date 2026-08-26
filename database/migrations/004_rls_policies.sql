SET ROLE bio_owner;

ALTER TABLE bio_sightings ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_sightings FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_usage FORCE ROW LEVEL SECURITY;

CREATE POLICY bio_sightings_select_policy ON bio_sightings
    FOR SELECT TO bio_app_user, bio_owner
    USING (
        EXISTS (
            SELECT 1
            FROM bio_researchers AS actor
            WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
              AND actor.bio_is_active
              AND (
                    bio_sightings.bio_classification_level <= actor.bio_accreditation_level
                    OR bio_sightings.bio_researcher_id = actor.bio_researcher_id
              )
        )
    );

CREATE POLICY bio_sightings_insert_policy ON bio_sightings
    FOR INSERT TO bio_app_user, bio_owner
    WITH CHECK (
        bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
        AND EXISTS (
            SELECT 1 FROM bio_researchers AS actor
            WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
              AND actor.bio_is_active
        )
    );

-- Visibility is broader than edit rights. Only an author can change a sighting.
CREATE POLICY bio_sightings_update_policy ON bio_sightings
    FOR UPDATE TO bio_app_user, bio_owner
    USING (
        bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
        AND EXISTS (
            SELECT 1 FROM bio_researchers AS actor
            WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
              AND actor.bio_is_active
        )
    )
    WITH CHECK (
        bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID
    );

CREATE POLICY bio_copilot_usage_select_policy ON bio_copilot_usage
    FOR SELECT TO bio_app_user, bio_owner
    USING (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID);
CREATE POLICY bio_copilot_usage_insert_policy ON bio_copilot_usage
    FOR INSERT TO bio_app_user, bio_owner
    WITH CHECK (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID);

RESET ROLE;
