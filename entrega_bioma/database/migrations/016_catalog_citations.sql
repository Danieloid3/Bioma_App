-- Persist catalogue citations without weakening sighting or chat RLS.
SET ROLE bio_owner;

CREATE TABLE public.bio_copilot_catalog_citations (
    bio_copilot_catalog_citation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_copilot_usage_id UUID NOT NULL REFERENCES public.bio_copilot_usage (bio_copilot_usage_id) ON DELETE CASCADE,
    bio_source_type VARCHAR(12) NOT NULL CHECK (bio_source_type IN ('species', 'site')),
    bio_source_reference VARCHAR(80) NOT NULL,
    bio_source_id UUID NOT NULL,
    bio_rank SMALLINT NOT NULL CHECK (bio_rank > 0),
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (bio_copilot_usage_id, bio_source_type, bio_source_id)
);
ALTER TABLE public.bio_copilot_catalog_citations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bio_copilot_catalog_citations FORCE ROW LEVEL SECURITY;
CREATE POLICY bio_copilot_catalog_citations_actor_select ON public.bio_copilot_catalog_citations
FOR SELECT TO bio_app_user USING (EXISTS (
    SELECT 1 FROM public.bio_copilot_usage usage
    WHERE usage.bio_copilot_usage_id = bio_copilot_catalog_citations.bio_copilot_usage_id
      AND usage.bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
));
CREATE POLICY bio_copilot_catalog_citations_owner_all ON public.bio_copilot_catalog_citations
FOR ALL TO bio_owner USING (true) WITH CHECK (true);
GRANT SELECT ON public.bio_copilot_catalog_citations TO bio_app_user;

CREATE OR REPLACE FUNCTION bio_fn_log_copilot_usage(
    p_prompt TEXT, p_answer TEXT, p_system_prompt_version VARCHAR, p_model_name VARCHAR,
    p_input_tokens INTEGER, p_output_tokens INTEGER, p_source_sighting_ids UUID[],
    p_source_similarities NUMERIC[], p_catalog_sources JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_usage UUID; v_source JSONB; v_rank SMALLINT := 100;
BEGIN
    IF p_catalog_sources IS NULL OR jsonb_typeof(p_catalog_sources) <> 'array' THEN
        RAISE EXCEPTION 'catalog sources must be a JSON array' USING ERRCODE='22023';
    END IF;
    FOR v_source IN SELECT value FROM jsonb_array_elements(p_catalog_sources) source(value) LOOP
        IF v_source->>'type' = 'species' THEN
            IF NOT EXISTS (SELECT 1 FROM public.bio_species WHERE bio_species_id=(v_source->>'id')::UUID AND v_source->>'reference'='species-'||bio_species_id::TEXT) THEN
                RAISE EXCEPTION 'invalid species citation' USING ERRCODE='22023'; END IF;
        ELSIF v_source->>'type' = 'site' THEN
            IF NOT EXISTS (SELECT 1 FROM public.bio_sites WHERE bio_site_id=(v_source->>'id')::UUID AND v_source->>'reference'='site-'||bio_site_id::TEXT) THEN
                RAISE EXCEPTION 'invalid site citation' USING ERRCODE='22023'; END IF;
        ELSE RAISE EXCEPTION 'invalid catalog source type' USING ERRCODE='22023'; END IF;
    END LOOP;
    v_usage := public.bio_fn_log_copilot_usage(p_prompt,p_answer,p_system_prompt_version,p_model_name,p_input_tokens,p_output_tokens,p_source_sighting_ids,p_source_similarities);
    FOR v_source IN SELECT value FROM jsonb_array_elements(p_catalog_sources) source(value) LOOP
        v_rank := v_rank + 1;
        INSERT INTO public.bio_copilot_catalog_citations(bio_copilot_usage_id,bio_source_type,bio_source_reference,bio_source_id,bio_rank)
        VALUES(v_usage,v_source->>'type',v_source->>'reference',(v_source->>'id')::UUID,v_rank);
    END LOOP;
    RETURN v_usage;
END $$;

CREATE OR REPLACE FUNCTION bio_fn_get_copilot_conversation_messages(p_conversation_id UUID)
RETURNS TABLE (message_id UUID, conversation_id UUID, sender_role VARCHAR(20), message_text TEXT, model_name VARCHAR(100), created_at TIMESTAMPTZ, citations JSONB)
LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
SELECT m.bio_message_id,m.bio_conversation_id,m.bio_sender_role,m.bio_message_text,m.bio_model_name,m.bio_created_at,
COALESCE((SELECT jsonb_agg(source.payload ORDER BY source.rank) FROM (
    SELECT c.bio_rank AS rank,jsonb_build_object('sighting_id',s.bio_sighting_id,'observation_reference',s.bio_observation_reference,'species_common_name',sp.bio_common_name,'field_notes',s.bio_field_notes,'similarity',c.bio_similarity,'source_type','sighting') payload
    FROM public.bio_copilot_citations c JOIN public.bio_sightings s ON s.bio_sighting_id=c.bio_sighting_id JOIN public.bio_species sp ON sp.bio_species_id=s.bio_species_id WHERE c.bio_copilot_usage_id=m.bio_copilot_usage_id
    UNION ALL
    SELECT c.bio_rank,jsonb_build_object('sighting_id',c.bio_source_id,'observation_reference',c.bio_source_reference,'species_common_name',CASE WHEN c.bio_source_type='species' THEN sp.bio_common_name ELSE st.bio_site_name END,'field_notes',CASE WHEN c.bio_source_type='species' THEN sp.bio_description ELSE st.bio_description END,'similarity',1,'source_type',c.bio_source_type)
    FROM public.bio_copilot_catalog_citations c LEFT JOIN public.bio_species sp ON c.bio_source_type='species' AND sp.bio_species_id=c.bio_source_id LEFT JOIN public.bio_sites st ON c.bio_source_type='site' AND st.bio_site_id=c.bio_source_id WHERE c.bio_copilot_usage_id=m.bio_copilot_usage_id
) source),'[]'::jsonb)
FROM public.bio_copilot_messages m WHERE m.bio_conversation_id=p_conversation_id ORDER BY m.bio_created_at;
$$;

ALTER TABLE public.bio_chat_copilot_citations DROP CONSTRAINT IF EXISTS bio_chat_copilot_citations_bio_source_type_check;
ALTER TABLE public.bio_chat_copilot_citations ADD CONSTRAINT bio_chat_copilot_citations_bio_source_type_check CHECK (bio_source_type IN ('message','sighting','species','site'));

CREATE OR REPLACE FUNCTION bio_fn_record_chat_copilot_response(p_channel_id UUID,p_text TEXT,p_sources JSONB DEFAULT '[]'::JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_actor UUID:=nullif(current_setting('app.current_user_id',true),'')::UUID; v_message UUID:=gen_random_uuid(); v JSONB; v_type VARCHAR(12); v_ref VARCHAR(80); v_id UUID; v_rank SMALLINT:=0;
BEGIN
 IF NOT bio_fn_is_chat_member(p_channel_id) THEN RAISE EXCEPTION 'unauthorized channel' USING ERRCODE='42501'; END IF;
 IF length(btrim(coalesce(p_text,'')))=0 OR p_sources IS NULL OR jsonb_typeof(p_sources)<>'array' THEN RAISE EXCEPTION 'invalid response' USING ERRCODE='22023'; END IF;
 FOR v IN SELECT value FROM jsonb_array_elements(p_sources) source(value) LOOP
  v_type:=v->>'type'; v_ref:=v->>'reference'; v_id:=(v->>'id')::UUID;
  IF v_type='message' THEN
   IF NOT EXISTS(SELECT 1 FROM public.bio_chat_messages WHERE bio_chat_message_id=v_id AND bio_chat_channel_id=p_channel_id AND NOT bio_is_deleted AND v_ref='msg-'||substring(bio_chat_message_id::TEXT,1,8)) THEN RAISE EXCEPTION 'invalid message citation' USING ERRCODE='42501'; END IF;
  ELSIF v_type='sighting' THEN
   IF NOT EXISTS(SELECT 1 FROM public.bio_sightings s WHERE s.bio_sighting_id=v_id AND s.bio_observation_reference=v_ref AND NOT s.bio_is_voided AND NOT EXISTS(SELECT 1 FROM public.bio_chat_channel_members cm JOIN public.bio_researchers r ON r.bio_researcher_id=cm.bio_researcher_id WHERE cm.bio_chat_channel_id=p_channel_id AND cm.bio_left_at IS NULL AND r.bio_is_active AND s.bio_classification_level>r.bio_accreditation_level AND s.bio_researcher_id<>r.bio_researcher_id)) THEN RAISE EXCEPTION 'invalid sighting citation' USING ERRCODE='42501'; END IF;
  ELSIF v_type='species' THEN
   IF NOT EXISTS(SELECT 1 FROM public.bio_species WHERE bio_species_id=v_id AND v_ref='species-'||bio_species_id::TEXT) THEN RAISE EXCEPTION 'invalid species citation' USING ERRCODE='22023'; END IF;
  ELSIF v_type='site' THEN
   IF NOT EXISTS(SELECT 1 FROM public.bio_sites WHERE bio_site_id=v_id AND v_ref='site-'||bio_site_id::TEXT) THEN RAISE EXCEPTION 'invalid site citation' USING ERRCODE='22023'; END IF;
  ELSE RAISE EXCEPTION 'invalid source type' USING ERRCODE='22023'; END IF;
 END LOOP;
 INSERT INTO public.bio_chat_messages(bio_chat_message_id,bio_chat_channel_id,bio_author_researcher_id,bio_sender_role,bio_message_text) VALUES(v_message,p_channel_id,NULL,'copilot',btrim(p_text));
 INSERT INTO public.bio_chat_message_receipts(bio_chat_message_id,bio_researcher_id,bio_read_at) SELECT v_message,bio_researcher_id,CASE WHEN bio_researcher_id=v_actor THEN now() END FROM public.bio_chat_channel_members WHERE bio_chat_channel_id=p_channel_id AND bio_left_at IS NULL;
 FOR v IN SELECT value FROM jsonb_array_elements(p_sources) source(value) LOOP v_rank:=v_rank+1; INSERT INTO public.bio_chat_copilot_citations(bio_chat_message_id,bio_source_type,bio_source_reference,bio_source_id,bio_rank) VALUES(v_message,v->>'type',v->>'reference',(v->>'id')::UUID,v_rank); END LOOP;
 RETURN v_message;
END $$;

CREATE OR REPLACE FUNCTION bio_fn_mark_catalog_embedding_failed(p_type VARCHAR,p_id UUID,p_error TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN
 IF p_type='species' THEN UPDATE public.bio_species SET bio_catalog_embedding_status='failed',bio_catalog_embedding_error=left(p_error,500) WHERE bio_species_id=p_id;
 ELSIF p_type='site' THEN UPDATE public.bio_sites SET bio_catalog_embedding_status='failed',bio_catalog_embedding_error=left(p_error,500) WHERE bio_site_id=p_id;
 ELSE RAISE EXCEPTION 'invalid catalog type' USING ERRCODE='22023'; END IF;
END $$;

REVOKE ALL ON FUNCTION bio_fn_log_copilot_usage(TEXT,TEXT,VARCHAR,VARCHAR,INTEGER,INTEGER,UUID[],NUMERIC[],JSONB), bio_fn_mark_catalog_embedding_failed(VARCHAR,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bio_fn_log_copilot_usage(TEXT,TEXT,VARCHAR,VARCHAR,INTEGER,INTEGER,UUID[],NUMERIC[],JSONB), bio_fn_mark_catalog_embedding_failed(VARCHAR,UUID,TEXT) TO bio_app_user;
RESET ROLE;
