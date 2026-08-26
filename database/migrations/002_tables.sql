SET ROLE bio_owner;

CREATE TABLE bio_researchers (
    bio_researcher_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_full_name VARCHAR(150) NOT NULL CHECK (length(btrim(bio_full_name)) > 0),
    bio_email CITEXT NOT NULL UNIQUE,
    bio_password_hash VARCHAR(255) NOT NULL,
    bio_role_title VARCHAR(100) NOT NULL,
    bio_accreditation_level SMALLINT NOT NULL CHECK (bio_accreditation_level BETWEEN 1 AND 3),
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bio_species (
    bio_species_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_common_name VARCHAR(200) NOT NULL,
    bio_scientific_name VARCHAR(200) NOT NULL UNIQUE,
    bio_iucn_category VARCHAR(5) NOT NULL CHECK (bio_iucn_category IN ('LC', 'NT', 'VU', 'EN', 'CR', 'EW', 'EX', 'DD', 'NE')),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bio_sites (
    bio_site_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_site_name VARCHAR(200) NOT NULL,
    bio_region VARCHAR(100) NOT NULL,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_sites_name_region UNIQUE (bio_site_name, bio_region)
);

CREATE TABLE bio_sightings (
    bio_sighting_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_observation_reference VARCHAR(30) NOT NULL UNIQUE,
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_species_id UUID NOT NULL REFERENCES bio_species (bio_species_id) ON DELETE RESTRICT,
    bio_site_id UUID NOT NULL REFERENCES bio_sites (bio_site_id) ON DELETE RESTRICT,
    bio_observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_exact_latitude NUMERIC(9, 6) NOT NULL CHECK (bio_exact_latitude BETWEEN -90 AND 90),
    bio_exact_longitude NUMERIC(10, 6) NOT NULL CHECK (bio_exact_longitude BETWEEN -180 AND 180),
    bio_classification_level SMALLINT NOT NULL CHECK (bio_classification_level BETWEEN 1 AND 3),
    bio_field_notes TEXT NOT NULL CHECK (length(btrim(bio_field_notes)) > 0),
    bio_field_notes_embedding VECTOR(1536),
    bio_embedding_status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (bio_embedding_status IN ('pending', 'processing', 'ready', 'failed')),
    bio_embedding_model VARCHAR(100),
    bio_embedded_at TIMESTAMPTZ,
    bio_is_voided BOOLEAN NOT NULL DEFAULT false,
    bio_voided_at TIMESTAMPTZ,
    bio_voided_by_researcher_id UUID REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_void_reason TEXT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_bio_sightings_void_metadata CHECK (
        (NOT bio_is_voided AND bio_voided_at IS NULL AND bio_voided_by_researcher_id IS NULL AND bio_void_reason IS NULL)
        OR
        (bio_is_voided AND bio_voided_at IS NOT NULL AND bio_voided_by_researcher_id IS NOT NULL AND length(btrim(bio_void_reason)) > 0)
    )
);

CREATE TABLE bio_sighting_revisions (
    bio_sighting_revision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_sighting_id UUID NOT NULL REFERENCES bio_sightings (bio_sighting_id) ON DELETE RESTRICT,
    bio_revision_number INTEGER NOT NULL CHECK (bio_revision_number > 0),
    bio_changed_by_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_change_type VARCHAR(16) NOT NULL CHECK (bio_change_type IN ('edited', 'voided')),
    bio_previous_classification_level SMALLINT NOT NULL CHECK (bio_previous_classification_level BETWEEN 1 AND 3),
    bio_previous_exact_latitude NUMERIC(9, 6) NOT NULL,
    bio_previous_exact_longitude NUMERIC(10, 6) NOT NULL,
    bio_previous_field_notes TEXT NOT NULL,
    bio_change_reason TEXT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_sighting_revisions_sighting_number UNIQUE (bio_sighting_id, bio_revision_number)
);

CREATE TABLE bio_refresh_tokens (
    bio_refresh_token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE CASCADE,
    bio_token_family_id UUID NOT NULL,
    bio_parent_refresh_token_id UUID REFERENCES bio_refresh_tokens (bio_refresh_token_id) ON DELETE RESTRICT,
    bio_token_hash VARCHAR(255) NOT NULL UNIQUE,
    bio_expires_at TIMESTAMPTZ NOT NULL,
    bio_used_at TIMESTAMPTZ,
    bio_revoked_at TIMESTAMPTZ,
    bio_revocation_reason VARCHAR(40),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_bio_refresh_tokens_expiry CHECK (bio_expires_at > bio_created_at),
    CONSTRAINT ck_bio_refresh_tokens_revocation CHECK (
        (bio_revoked_at IS NULL AND bio_revocation_reason IS NULL)
        OR (bio_revoked_at IS NOT NULL AND bio_revocation_reason IS NOT NULL)
    )
);

CREATE TABLE bio_copilot_usage (
    bio_copilot_usage_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_prompt_text TEXT NOT NULL,
    bio_response_text TEXT NOT NULL,
    bio_system_prompt_version VARCHAR(40) NOT NULL,
    bio_model_name VARCHAR(100) NOT NULL,
    bio_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_input_tokens >= 0),
    bio_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_output_tokens >= 0),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bio_copilot_citations (
    bio_copilot_citation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_copilot_usage_id UUID NOT NULL REFERENCES bio_copilot_usage (bio_copilot_usage_id) ON DELETE CASCADE,
    bio_sighting_id UUID NOT NULL REFERENCES bio_sightings (bio_sighting_id) ON DELETE RESTRICT,
    bio_rank SMALLINT NOT NULL CHECK (bio_rank > 0),
    bio_similarity NUMERIC(6, 5) CHECK (bio_similarity BETWEEN -1 AND 1),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_copilot_citations_usage_rank UNIQUE (bio_copilot_usage_id, bio_rank),
    CONSTRAINT uq_bio_copilot_citations_usage_sighting UNIQUE (bio_copilot_usage_id, bio_sighting_id)
);

RESET ROLE;

