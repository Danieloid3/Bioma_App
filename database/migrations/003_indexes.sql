SET ROLE bio_owner;

-- Fixed UTC conversion makes the business-day expression deterministic.
CREATE UNIQUE INDEX uix_bio_sightings_one_active_per_day
    ON bio_sightings (
        bio_researcher_id,
        bio_species_id,
        bio_site_id,
        ((bio_observed_at AT TIME ZONE 'UTC')::date)
    )
    WHERE bio_is_voided = false;

CREATE INDEX ix_bio_sightings_species_keyset
    ON bio_sightings (bio_species_id, bio_observed_at DESC, bio_sighting_id DESC)
    WHERE bio_is_voided = false;
CREATE INDEX ix_bio_sightings_site_keyset
    ON bio_sightings (bio_site_id, bio_observed_at DESC, bio_sighting_id DESC)
    WHERE bio_is_voided = false;
CREATE INDEX ix_bio_sightings_visible_keyset
    ON bio_sightings (bio_observed_at DESC, bio_sighting_id DESC);
CREATE INDEX ix_bio_sightings_notes_fts
    ON bio_sightings USING gin (to_tsvector('spanish', bio_field_notes));
CREATE INDEX ix_bio_sightings_embedding_hnsw
    ON bio_sightings USING hnsw (bio_field_notes_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE bio_field_notes_embedding IS NOT NULL;
CREATE INDEX ix_bio_sighting_revisions_sighting
    ON bio_sighting_revisions (bio_sighting_id, bio_revision_number DESC);
CREATE INDEX ix_bio_refresh_tokens_family
    ON bio_refresh_tokens (bio_token_family_id)
    WHERE bio_revoked_at IS NULL;
CREATE INDEX ix_bio_refresh_tokens_active_expiry
    ON bio_refresh_tokens (bio_expires_at)
    WHERE bio_used_at IS NULL AND bio_revoked_at IS NULL;
CREATE INDEX ix_bio_copilot_usage_researcher_created
    ON bio_copilot_usage (bio_researcher_id, bio_created_at DESC);
CREATE INDEX ix_bio_copilot_citations_sighting
    ON bio_copilot_citations (bio_sighting_id);

RESET ROLE;

