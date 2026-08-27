-- 001_core_schema.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bio_owner') THEN
        CREATE ROLE bio_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bio_app_user') THEN
        CREATE ROLE bio_app_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    END IF;
END;
$$;

ALTER ROLE bio_app_user PASSWORD :'bio_app_password';
GRANT USAGE, CREATE ON SCHEMA public TO bio_owner;
GRANT USAGE ON SCHEMA public TO bio_app_user;

SET ROLE bio_owner;

CREATE OR REPLACE FUNCTION bio_fn_immutable_unaccent(TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
STRICT
AS $$
    SELECT public.unaccent('public.unaccent', $1);
$$;

CREATE TABLE bio_researchers (
    bio_researcher_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_full_name VARCHAR(150) NOT NULL CHECK (length(btrim(bio_full_name)) > 0),
    bio_email CITEXT NOT NULL UNIQUE,
    bio_password_hash VARCHAR(255) NOT NULL,
    bio_role_title VARCHAR(100) NOT NULL,
    bio_accreditation_level SMALLINT NOT NULL CHECK (bio_accreditation_level BETWEEN 1 AND 3),
    bio_avatar_key VARCHAR(32) NOT NULL CHECK (
        bio_avatar_key IN (
            'spectacled_bear', 'andean_condor', 'golden_poison_frog', 'jaguar',
            'hummingbird', 'cotton_top_tamarin', 'green_iguana', 'mountain_tapir'
        )
    ),
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bio_species (
    bio_species_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_common_name VARCHAR(200) NOT NULL,
    bio_scientific_name VARCHAR(200) NOT NULL UNIQUE,
    bio_iucn_category VARCHAR(5) NOT NULL CHECK (bio_iucn_category IN ('LC', 'NT', 'VU', 'EN', 'CR', 'EW', 'EX', 'DD', 'NE')),
    bio_description TEXT,
    bio_habitat TEXT,
    bio_diet TEXT,
    bio_conservation_status TEXT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

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
CREATE UNIQUE INDEX uix_bio_species_images_featured_active ON bio_species_images (bio_species_id) WHERE bio_is_featured AND bio_is_active;
CREATE INDEX ix_bio_species_images_species_active ON bio_species_images (bio_species_id) WHERE bio_is_active;

CREATE TABLE bio_sites (
    bio_site_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_site_name VARCHAR(200) NOT NULL,
    bio_region VARCHAR(100) NOT NULL,
    bio_description TEXT,
    bio_ecosystem VARCHAR(100),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_sites_name_region UNIQUE (bio_site_name, bio_region)
);

CREATE TABLE bio_site_images (
    bio_site_image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_site_id UUID NOT NULL REFERENCES bio_sites (bio_site_id) ON DELETE RESTRICT,
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
CREATE UNIQUE INDEX uix_bio_site_images_featured_active ON bio_site_images (bio_site_id) WHERE bio_is_featured AND bio_is_active;
CREATE INDEX ix_bio_site_images_site_active ON bio_site_images (bio_site_id) WHERE bio_is_active;

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
    bio_embedding_attempts INTEGER NOT NULL DEFAULT 0 CHECK (bio_embedding_attempts >= 0),
    bio_embedding_error TEXT,
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

CREATE TABLE bio_copilot_conversations (
    bio_conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_title VARCHAR(120) NOT NULL DEFAULT 'Nueva consulta',
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_archived_at TIMESTAMPTZ,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bio_copilot_messages (
    bio_message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_conversation_id UUID NOT NULL REFERENCES bio_copilot_conversations (bio_conversation_id) ON DELETE CASCADE,
    bio_researcher_id UUID REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_sender_role VARCHAR(12) NOT NULL DEFAULT 'user' CHECK (bio_sender_role IN ('user', 'copilot', 'assistant')),
    bio_message_text TEXT NOT NULL,
    bio_model_name VARCHAR(100),
    bio_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_input_tokens >= 0),
    bio_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK (bio_output_tokens >= 0),
    bio_copilot_usage_id UUID REFERENCES bio_copilot_usage (bio_copilot_usage_id) ON DELETE SET NULL,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_bio_copilot_messages_sender CHECK (
        (bio_sender_role = 'user' AND bio_researcher_id IS NOT NULL)
        OR (bio_sender_role IN ('copilot', 'assistant') AND bio_researcher_id IS NULL)
    )
);

CREATE TABLE bio_chat_channels (
    bio_chat_channel_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_created_by_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_channel_type VARCHAR(12) NOT NULL CHECK (bio_channel_type IN ('direct', 'group')),
    bio_name VARCHAR(120),
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_bio_chat_channels_name CHECK (
        (bio_channel_type = 'group' AND length(btrim(coalesce(bio_name, ''))) > 0)
        OR (bio_channel_type = 'direct' AND bio_name IS NULL)
    )
);

CREATE TABLE bio_chat_channel_members (
    bio_chat_channel_id UUID NOT NULL REFERENCES bio_chat_channels (bio_chat_channel_id) ON DELETE RESTRICT,
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_member_role VARCHAR(12) NOT NULL DEFAULT 'member' CHECK (bio_member_role IN ('owner', 'member')),
    bio_joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_left_at TIMESTAMPTZ,
    PRIMARY KEY (bio_chat_channel_id, bio_researcher_id),
    CONSTRAINT ck_bio_chat_channel_members_left_after_join CHECK (bio_left_at IS NULL OR bio_left_at >= bio_joined_at)
);

CREATE TABLE bio_chat_messages (
    bio_chat_message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_chat_channel_id UUID NOT NULL REFERENCES bio_chat_channels (bio_chat_channel_id) ON DELETE RESTRICT,
    bio_author_researcher_id UUID REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_sender_role VARCHAR(12) NOT NULL DEFAULT 'user' CHECK (bio_sender_role IN ('user', 'copilot')),
    bio_message_text TEXT NOT NULL CHECK (length(btrim(bio_message_text)) BETWEEN 1 AND 4000),
    bio_search_document TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', bio_message_text)) STORED,
    bio_message_embedding VECTOR(1536),
    bio_embedding_status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (bio_embedding_status IN ('pending', 'processing', 'ready', 'failed')),
    bio_embedding_model VARCHAR(100),
    bio_embedding_attempts INTEGER NOT NULL DEFAULT 0 CHECK (bio_embedding_attempts >= 0),
    bio_embedding_error TEXT,
    bio_embedded_at TIMESTAMPTZ,
    bio_is_edited BOOLEAN NOT NULL DEFAULT false,
    bio_is_deleted BOOLEAN NOT NULL DEFAULT false,
    bio_deleted_at TIMESTAMPTZ,
    bio_deleted_by_researcher_id UUID REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_bio_chat_messages_deleted_metadata CHECK (
        (NOT bio_is_deleted AND bio_deleted_at IS NULL AND bio_deleted_by_researcher_id IS NULL)
        OR (bio_is_deleted AND bio_deleted_at IS NOT NULL AND bio_deleted_by_researcher_id IS NOT NULL)
    ),
    CONSTRAINT ck_bio_chat_messages_sender CHECK (
        (bio_sender_role = 'user' AND bio_author_researcher_id IS NOT NULL)
        OR (bio_sender_role = 'copilot' AND bio_author_researcher_id IS NULL)
    )
);

CREATE TABLE bio_chat_message_versions (
    bio_chat_message_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_chat_message_id UUID NOT NULL REFERENCES bio_chat_messages (bio_chat_message_id) ON DELETE RESTRICT,
    bio_version_number INTEGER NOT NULL CHECK (bio_version_number > 0),
    bio_message_text TEXT NOT NULL,
    bio_change_type VARCHAR(12) NOT NULL CHECK (bio_change_type IN ('edited', 'deleted')),
    bio_changed_by_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_chat_message_versions_message_number UNIQUE (bio_chat_message_id, bio_version_number)
);

CREATE TABLE bio_chat_message_receipts (
    bio_chat_message_id UUID NOT NULL REFERENCES bio_chat_messages (bio_chat_message_id) ON DELETE RESTRICT,
    bio_researcher_id UUID NOT NULL REFERENCES bio_researchers (bio_researcher_id) ON DELETE RESTRICT,
    bio_read_at TIMESTAMPTZ,
    PRIMARY KEY (bio_chat_message_id, bio_researcher_id)
);

CREATE TABLE bio_chat_copilot_citations (
    bio_chat_copilot_citation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_chat_message_id UUID NOT NULL REFERENCES bio_chat_messages (bio_chat_message_id) ON DELETE RESTRICT,
    bio_source_type VARCHAR(12) NOT NULL CHECK (bio_source_type IN ('message', 'sighting')),
    bio_source_reference VARCHAR(80) NOT NULL,
    bio_source_id UUID NOT NULL,
    bio_rank SMALLINT NOT NULL CHECK (bio_rank > 0),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bio_chat_copilot_citations_rank UNIQUE (bio_chat_message_id, bio_rank),
    CONSTRAINT uq_bio_chat_copilot_citations_source UNIQUE (bio_chat_message_id, bio_source_type, bio_source_id)
);


-- Indexes
CREATE UNIQUE INDEX uix_bio_sightings_one_active_per_day
    ON bio_sightings (bio_researcher_id, bio_species_id, bio_site_id, ((bio_observed_at AT TIME ZONE 'UTC')::date))
    WHERE bio_is_voided = false;
CREATE INDEX ix_bio_sightings_species_keyset ON bio_sightings (bio_species_id, bio_observed_at DESC, bio_sighting_id DESC) WHERE bio_is_voided = false;
CREATE INDEX ix_bio_sightings_site_keyset ON bio_sightings (bio_site_id, bio_observed_at DESC, bio_sighting_id DESC) WHERE bio_is_voided = false;
CREATE INDEX ix_bio_sightings_visible_keyset ON bio_sightings (bio_observed_at DESC, bio_sighting_id DESC);
CREATE INDEX ix_bio_sightings_notes_fts ON bio_sightings USING gin (to_tsvector('spanish', bio_field_notes));
CREATE INDEX ix_bio_sightings_embedding_hnsw ON bio_sightings USING hnsw (bio_field_notes_embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64) WHERE bio_field_notes_embedding IS NOT NULL;
CREATE INDEX ix_bio_sighting_revisions_sighting ON bio_sighting_revisions (bio_sighting_id, bio_revision_number DESC);
CREATE INDEX ix_bio_refresh_tokens_family ON bio_refresh_tokens (bio_token_family_id) WHERE bio_revoked_at IS NULL;
CREATE INDEX ix_bio_refresh_tokens_active_expiry ON bio_refresh_tokens (bio_expires_at) WHERE bio_used_at IS NULL AND bio_revoked_at IS NULL;
CREATE INDEX ix_bio_copilot_usage_researcher_created ON bio_copilot_usage (bio_researcher_id, bio_created_at DESC);
CREATE INDEX ix_bio_copilot_citations_sighting ON bio_copilot_citations (bio_sighting_id);
CREATE INDEX ix_bio_copilot_conversations_active ON bio_copilot_conversations (bio_researcher_id, bio_is_active, bio_updated_at DESC);
CREATE INDEX ix_bio_copilot_conversations_researcher ON bio_copilot_conversations (bio_researcher_id, bio_updated_at DESC);
CREATE INDEX ix_bio_copilot_messages_conversation ON bio_copilot_messages (bio_conversation_id, bio_created_at ASC);
CREATE INDEX ix_bio_chat_members_visible_channels ON bio_chat_channel_members (bio_researcher_id, bio_chat_channel_id) WHERE bio_left_at IS NULL;
CREATE INDEX ix_bio_chat_messages_history ON bio_chat_messages (bio_chat_channel_id, bio_created_at DESC, bio_chat_message_id DESC);
CREATE INDEX ix_bio_chat_messages_search ON bio_chat_messages USING GIN (bio_search_document) WHERE bio_is_deleted = false;
CREATE INDEX ix_bio_chat_messages_embedding ON bio_chat_messages USING ivfflat (bio_message_embedding vector_cosine_ops) WITH (lists = 10) WHERE bio_message_embedding IS NOT NULL AND bio_is_deleted = false;

-- RLS
ALTER TABLE bio_sightings ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_usage FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_sighting_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_copilot_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_channels FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_channel_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_channel_members FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_message_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_message_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_message_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_message_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_copilot_citations ENABLE ROW LEVEL SECURITY;
ALTER TABLE bio_chat_copilot_citations FORCE ROW LEVEL SECURITY;

CREATE POLICY bio_sightings_select_policy ON bio_sightings FOR SELECT TO bio_app_user, bio_owner USING (EXISTS (SELECT 1 FROM bio_researchers AS actor WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID AND actor.bio_is_active AND (bio_sightings.bio_classification_level <= actor.bio_accreditation_level OR bio_sightings.bio_researcher_id = actor.bio_researcher_id)));
CREATE POLICY bio_sightings_insert_policy ON bio_sightings FOR INSERT TO bio_app_user, bio_owner WITH CHECK (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID AND EXISTS (SELECT 1 FROM bio_researchers AS actor WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID AND actor.bio_is_active));
CREATE POLICY bio_sightings_update_policy ON bio_sightings FOR UPDATE TO bio_app_user, bio_owner USING (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID AND EXISTS (SELECT 1 FROM bio_researchers AS actor WHERE actor.bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID AND actor.bio_is_active)) WITH CHECK (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID);
CREATE POLICY bio_copilot_usage_select_policy ON bio_copilot_usage FOR SELECT TO bio_app_user, bio_owner USING (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID);
CREATE POLICY bio_copilot_usage_insert_policy ON bio_copilot_usage FOR INSERT TO bio_app_user, bio_owner WITH CHECK (bio_researcher_id = NULLIF(current_setting('app.current_user_id', true), '')::UUID);
CREATE POLICY bio_sighting_revisions_select_policy ON bio_sighting_revisions FOR SELECT TO bio_app_user USING (EXISTS (SELECT 1 FROM bio_sightings AS sighting WHERE sighting.bio_sighting_id = bio_sighting_revisions.bio_sighting_id));
CREATE POLICY bio_copilot_conversations_policy ON bio_copilot_conversations FOR ALL TO bio_app_user USING (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid) WITH CHECK (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid);
CREATE POLICY bio_copilot_messages_policy ON bio_copilot_messages FOR ALL TO bio_app_user USING (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid) WITH CHECK (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE OR REPLACE FUNCTION bio_fn_is_chat_member(p_channel_id UUID) RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$ SELECT EXISTS (SELECT 1 FROM public.bio_chat_channel_members m WHERE m.bio_chat_channel_id = p_channel_id AND m.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid AND m.bio_left_at IS NULL); $$;
CREATE POLICY bio_chat_channels_member_policy ON bio_chat_channels FOR SELECT TO bio_app_user USING (bio_fn_is_chat_member(bio_chat_channel_id));
CREATE POLICY bio_chat_members_member_policy ON bio_chat_channel_members FOR SELECT TO bio_app_user USING (bio_fn_is_chat_member(bio_chat_channel_id));
CREATE POLICY bio_chat_messages_member_policy ON bio_chat_messages FOR SELECT TO bio_app_user USING (bio_fn_is_chat_member(bio_chat_channel_id));
CREATE POLICY bio_chat_versions_member_policy ON bio_chat_message_versions FOR SELECT TO bio_app_user USING (EXISTS (SELECT 1 FROM bio_chat_messages msg WHERE msg.bio_chat_message_id = bio_chat_message_versions.bio_chat_message_id AND bio_fn_is_chat_member(msg.bio_chat_channel_id)));
CREATE POLICY bio_chat_receipts_own_policy ON bio_chat_message_receipts FOR SELECT TO bio_app_user USING (bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::uuid);
CREATE POLICY bio_chat_channels_owner_policy ON bio_chat_channels FOR ALL TO bio_owner USING (true) WITH CHECK (true);
CREATE POLICY bio_chat_members_owner_policy ON bio_chat_channel_members FOR ALL TO bio_owner USING (true) WITH CHECK (true);
CREATE POLICY bio_chat_messages_owner_policy ON bio_chat_messages FOR ALL TO bio_owner USING (true) WITH CHECK (true);
CREATE POLICY bio_chat_versions_owner_policy ON bio_chat_message_versions FOR ALL TO bio_owner USING (true) WITH CHECK (true);
CREATE POLICY bio_chat_receipts_owner_policy ON bio_chat_message_receipts FOR ALL TO bio_owner USING (true) WITH CHECK (true);
CREATE POLICY bio_chat_copilot_citations_member_policy ON bio_chat_copilot_citations FOR SELECT TO bio_app_user USING (EXISTS (SELECT 1 FROM bio_chat_messages m WHERE m.bio_chat_message_id=bio_chat_copilot_citations.bio_chat_message_id AND bio_fn_is_chat_member(m.bio_chat_channel_id)));
CREATE POLICY bio_chat_copilot_citations_owner_policy ON bio_chat_copilot_citations FOR ALL TO bio_owner USING (true) WITH CHECK (true);

REVOKE ALL ON TABLE public.bio_researchers, public.bio_species, public.bio_sites, public.bio_sightings, public.bio_sighting_revisions, public.bio_refresh_tokens, public.bio_copilot_usage, public.bio_copilot_citations, public.bio_chat_channels, public.bio_chat_channel_members, public.bio_chat_messages, public.bio_chat_message_versions, public.bio_chat_message_receipts FROM bio_app_user;
GRANT SELECT ON public.bio_sightings, public.bio_species, public.bio_sites, public.bio_copilot_usage TO bio_app_user;
GRANT SELECT (bio_researcher_id, bio_full_name, bio_email, bio_role_title, bio_accreditation_level, bio_is_active, bio_created_at, bio_updated_at, bio_avatar_key) ON public.bio_researchers TO bio_app_user;
GRANT SELECT ON public.bio_sighting_revisions, public.bio_species_images, public.bio_site_images, public.bio_copilot_conversations, public.bio_copilot_messages, public.bio_copilot_citations, public.bio_chat_channels, public.bio_chat_channel_members, public.bio_chat_messages, public.bio_chat_message_versions, public.bio_chat_message_receipts, public.bio_chat_copilot_citations TO bio_app_user;
GRANT INSERT, UPDATE, DELETE ON public.bio_copilot_conversations, public.bio_copilot_messages TO bio_app_user;
RESET ROLE;
