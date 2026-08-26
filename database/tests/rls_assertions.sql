BEGIN;

SELECT set_config(
    'app.current_user_id',
    (SELECT bio_researcher_id::TEXT FROM bio_researchers WHERE bio_email = 'valentina.rios@yarumo.org'),
    true
);

DO $$
DECLARE
    v_denied_confidential INTEGER;
    v_own_confidential INTEGER;
    v_rag_denied INTEGER;
    v_rag_own INTEGER;
    v_query_vector VECTOR(1536) := ('[' || array_to_string(array_fill(0::REAL, ARRAY[1536]), ',') || ']')::VECTOR;
BEGIN
    SELECT COUNT(*) INTO v_denied_confidential
    FROM bio_sightings
    WHERE bio_observation_reference = 'obs-5001';
    IF v_denied_confidential <> 0 THEN
        RAISE EXCEPTION 'RLS failure: low-accreditation actor read another confidential sighting';
    END IF;

    SELECT COUNT(*) INTO v_own_confidential
    FROM bio_sightings
    WHERE bio_observation_reference = 'obs-5005';
    IF v_own_confidential <> 1 THEN
        RAISE EXCEPTION 'RLS failure: author could not read own confidential sighting';
    END IF;

    SELECT COUNT(*) INTO v_rag_denied
    FROM bio_fn_retrieve_copilot_context(v_query_vector, 20)
    WHERE observation_reference = 'obs-5007';
    IF v_rag_denied <> 0 THEN
        RAISE EXCEPTION 'RAG failure: restricted context reached low-accreditation actor';
    END IF;

    SELECT COUNT(*) INTO v_rag_own
    FROM bio_fn_retrieve_copilot_context(v_query_vector, 20)
    WHERE observation_reference = 'obs-5005';
    IF v_rag_own <> 1 THEN
        RAISE EXCEPTION 'RAG failure: own confidential context was not recovered';
    END IF;
END;
$$;

ROLLBACK;

