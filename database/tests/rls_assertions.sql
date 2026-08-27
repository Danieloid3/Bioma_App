BEGIN;

SELECT set_config(
    'app.current_user_id',
    (SELECT bio_researcher_id::TEXT FROM bio_researchers WHERE bio_email = 'valentina.rios@yarumo.org'),
    true
);

SELECT set_config('app.test_hidden_sighting_id', :'hidden_sighting_id', true);

DO $$
DECLARE
    v_denied_confidential INTEGER;
    v_own_confidential INTEGER;
    v_rag_denied INTEGER;
    v_rag_own INTEGER;
    v_detail_denied INTEGER;
    v_detail_own INTEGER;
    v_history_image TEXT;
    v_dashboard_visible BIGINT;
    v_dashboard_hidden BIGINT;
    v_query_vector VECTOR(1536) := (
        '[' || array_to_string(array_prepend(1::REAL, array_fill(0::REAL, ARRAY[1535])), ',') || ']'
    )::VECTOR;
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

    SELECT COUNT(*) INTO v_detail_denied
    FROM bio_fn_get_sighting_detail(current_setting('app.test_hidden_sighting_id')::UUID);
    IF v_detail_denied <> 0 THEN
        RAISE EXCEPTION 'Detail failure: confidential sighting detail reached low-accreditation actor';
    END IF;

    SELECT COUNT(*) INTO v_detail_own
    FROM bio_fn_get_sighting_detail(
        (SELECT bio_sighting_id FROM bio_sightings WHERE bio_observation_reference = 'obs-5005')
    )
    WHERE exact_latitude = 9.801200 AND exact_longitude = -75.120300;
    IF v_detail_own <> 1 THEN
        RAISE EXCEPTION 'Detail failure: author could not read own authorized coordinates';
    END IF;

    SELECT image_url INTO v_history_image
    FROM bio_fn_sighting_history_with_images(NULL, NULL, NULL, NULL, 20, false)
    WHERE observation_reference = 'obs-5006';
    IF v_history_image IS NULL THEN
        RAISE EXCEPTION 'History failure: catalogue image was not returned for visible species';
    END IF;

    SELECT visible_sightings INTO v_dashboard_visible FROM bio_fn_dashboard_summary();
    SELECT COUNT(*) INTO v_dashboard_hidden
    FROM bio_sightings
    WHERE bio_observation_reference = 'obs-5001';
    IF v_dashboard_visible < 1 OR v_dashboard_hidden <> 0 THEN
        RAISE EXCEPTION 'Dashboard failure: aggregate did not preserve RLS visibility';
    END IF;
END;
$$;

ROLLBACK;
