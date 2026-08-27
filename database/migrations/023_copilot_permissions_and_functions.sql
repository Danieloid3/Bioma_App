SET ROLE bio_owner;

GRANT SELECT ON public.bio_copilot_citations TO bio_app_user;

CREATE OR REPLACE FUNCTION bio_fn_get_copilot_conversation_messages(
    p_conversation_id UUID
) RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    sender_role VARCHAR,
    message_text TEXT,
    model_name VARCHAR,
    created_at TIMESTAMPTZ,
    citations JSONB
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT m.bio_message_id,
           m.bio_conversation_id,
           m.bio_sender_role,
           m.bio_message_text,
           m.bio_model_name,
           m.bio_created_at,
           coalesce(
               (
                   SELECT jsonb_agg(
                       jsonb_build_object(
                           'sighting_id', s.bio_sighting_id,
                           'observation_reference', s.bio_observation_reference,
                           'species_common_name', sp.bio_common_name,
                           'field_notes', s.bio_field_notes,
                           'similarity', cit.bio_similarity
                       ) ORDER BY cit.bio_rank
                   )
                   FROM public.bio_copilot_citations AS cit
                   JOIN public.bio_sightings AS s ON s.bio_sighting_id = cit.bio_sighting_id
                   JOIN public.bio_species AS sp ON sp.bio_species_id = s.bio_species_id
                   WHERE cit.bio_copilot_usage_id = m.bio_copilot_usage_id
               ),
               '[]'::jsonb
           ) AS citations
    FROM public.bio_copilot_messages AS m
    WHERE m.bio_conversation_id = p_conversation_id
    ORDER BY m.bio_created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION bio_fn_get_copilot_conversation_messages(UUID) TO bio_app_user;

RESET ROLE;