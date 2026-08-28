-- Semantic catalogue retrieval is deliberately separate from protected sightings.
SET ROLE bio_owner;

ALTER TABLE public.bio_species
  ADD COLUMN bio_catalog_embedding VECTOR(1536),
  ADD COLUMN bio_catalog_embedding_status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (bio_catalog_embedding_status IN ('pending', 'processing', 'ready', 'failed')),
  ADD COLUMN bio_catalog_embedding_model VARCHAR(120),
  ADD COLUMN bio_catalog_embedding_attempts SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN bio_catalog_embedding_error TEXT;

ALTER TABLE public.bio_sites
  ADD COLUMN bio_catalog_embedding VECTOR(1536),
  ADD COLUMN bio_catalog_embedding_status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (bio_catalog_embedding_status IN ('pending', 'processing', 'ready', 'failed')),
  ADD COLUMN bio_catalog_embedding_model VARCHAR(120),
  ADD COLUMN bio_catalog_embedding_attempts SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN bio_catalog_embedding_error TEXT;

CREATE INDEX ix_bio_species_catalog_embedding ON public.bio_species USING hnsw (bio_catalog_embedding vector_cosine_ops) WHERE bio_catalog_embedding_status = 'ready';
CREATE INDEX ix_bio_sites_catalog_embedding ON public.bio_sites USING hnsw (bio_catalog_embedding vector_cosine_ops) WHERE bio_catalog_embedding_status = 'ready';

CREATE OR REPLACE FUNCTION bio_fn_retrieve_catalog_context(p_embedding VECTOR, p_limit INTEGER DEFAULT 8)
RETURNS TABLE (catalog_type VARCHAR, catalog_id UUID, source_reference VARCHAR, label VARCHAR, detail TEXT, similarity NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog, public AS $$
  SELECT * FROM (
    SELECT 'species'::VARCHAR, s.bio_species_id, ('species-' || s.bio_species_id::TEXT)::VARCHAR,
      (s.bio_common_name || ' · ' || s.bio_scientific_name)::VARCHAR,
      concat_ws('. ', s.bio_description, s.bio_habitat, s.bio_diet, s.bio_conservation_status),
      (1 - (s.bio_catalog_embedding <=> p_embedding))::NUMERIC
    FROM public.bio_species s WHERE s.bio_catalog_embedding_status = 'ready'
    UNION ALL
    SELECT 'site'::VARCHAR, t.bio_site_id, ('site-' || t.bio_site_id::TEXT)::VARCHAR,
      (t.bio_site_name || ' · ' || t.bio_region)::VARCHAR,
      concat_ws('. ', t.bio_description, t.bio_ecosystem),
      (1 - (t.bio_catalog_embedding <=> p_embedding))::NUMERIC
    FROM public.bio_sites t WHERE t.bio_catalog_embedding_status = 'ready'
  ) catalog ORDER BY 6 DESC LIMIT greatest(1, least(p_limit, 20));
$$;

-- The worker claims one catalogue row at a time. It is a maintenance path and
-- never reads protected sightings or researcher data.
CREATE OR REPLACE FUNCTION bio_fn_claim_catalog_embedding_job()
RETURNS TABLE(catalog_type VARCHAR, catalog_id UUID, catalog_text TEXT, attempts SMALLINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  RETURN QUERY
  WITH candidate AS (
    SELECT 'species'::VARCHAR AS kind, bio_species_id AS id,
      concat_ws('. ', bio_common_name, bio_scientific_name, bio_description, bio_habitat, bio_diet, bio_conservation_status) AS text
    FROM public.bio_species WHERE bio_catalog_embedding_status IN ('pending', 'failed') ORDER BY bio_updated_at FOR UPDATE SKIP LOCKED LIMIT 1
  )
  UPDATE public.bio_species s SET bio_catalog_embedding_status='processing', bio_catalog_embedding_attempts=s.bio_catalog_embedding_attempts+1, bio_catalog_embedding_error=NULL
  FROM candidate WHERE candidate.kind='species' AND s.bio_species_id=candidate.id
  RETURNING candidate.kind, s.bio_species_id, candidate.text, s.bio_catalog_embedding_attempts;
  IF FOUND THEN RETURN; END IF;
  RETURN QUERY
  WITH candidate AS (
    SELECT 'site'::VARCHAR AS kind, bio_site_id AS id, concat_ws('. ', bio_site_name, bio_region, bio_description, bio_ecosystem) AS text
    FROM public.bio_sites WHERE bio_catalog_embedding_status IN ('pending', 'failed') ORDER BY bio_updated_at FOR UPDATE SKIP LOCKED LIMIT 1
  )
  UPDATE public.bio_sites t SET bio_catalog_embedding_status='processing', bio_catalog_embedding_attempts=t.bio_catalog_embedding_attempts+1, bio_catalog_embedding_error=NULL
  FROM candidate WHERE candidate.kind='site' AND t.bio_site_id=candidate.id
  RETURNING candidate.kind, t.bio_site_id, candidate.text, t.bio_catalog_embedding_attempts;
END; $$;

CREATE OR REPLACE FUNCTION bio_fn_store_catalog_embedding(p_type VARCHAR, p_id UUID, p_embedding VECTOR, p_model VARCHAR)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF p_type = 'species' THEN UPDATE public.bio_species SET bio_catalog_embedding=p_embedding, bio_catalog_embedding_status='ready', bio_catalog_embedding_model=p_model, bio_catalog_embedding_error=NULL WHERE bio_species_id=p_id;
  ELSIF p_type = 'site' THEN UPDATE public.bio_sites SET bio_catalog_embedding=p_embedding, bio_catalog_embedding_status='ready', bio_catalog_embedding_model=p_model, bio_catalog_embedding_error=NULL WHERE bio_site_id=p_id;
  ELSE RAISE EXCEPTION 'invalid catalog type' USING ERRCODE='22023'; END IF;
END; $$;

REVOKE ALL ON FUNCTION bio_fn_claim_catalog_embedding_job(), bio_fn_store_catalog_embedding(VARCHAR, UUID, VECTOR, VARCHAR), bio_fn_retrieve_catalog_context(VECTOR, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_claim_catalog_embedding_job(), bio_fn_store_catalog_embedding(VARCHAR, UUID, VECTOR, VARCHAR), bio_fn_retrieve_catalog_context(VECTOR, INTEGER) TO bio_app_user;
RESET ROLE;
