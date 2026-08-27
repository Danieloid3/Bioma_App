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
    v_site_image TEXT;
    v_dashboard_visible BIGINT;
    v_dashboard_hidden BIGINT;
    v_copilot_conversation_id UUID;
    v_copilot_usage_id UUID;
    v_copilot_message_count INTEGER;
    v_copilot_audit_count INTEGER;
    v_copilot_summary_queries BIGINT;
    v_hidden_citation_rejected BOOLEAN := false;
    v_refresh_family_id UUID := gen_random_uuid();
    v_refresh_actor_name VARCHAR;
    v_refresh_reuse_rejected BOOLEAN := false;
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

    SELECT image.bio_display_url INTO v_site_image
    FROM bio_sites AS site
    JOIN bio_site_images AS image ON image.bio_site_id = site.bio_site_id
    WHERE site.bio_site_name = 'Reserva El Ceibal'
      AND site.bio_region = 'Bolívar'
      AND image.bio_is_featured = true
      AND image.bio_is_active = true;
    IF v_site_image IS NULL THEN
        RAISE EXCEPTION 'Catalogue failure: featured active image was not seeded for a site';
    END IF;

    SELECT visible_sightings INTO v_dashboard_visible FROM bio_fn_dashboard_summary();
    SELECT COUNT(*) INTO v_dashboard_hidden
    FROM bio_sightings
    WHERE bio_observation_reference = 'obs-5001';
    IF v_dashboard_visible < 1 OR v_dashboard_hidden <> 0 THEN
        RAISE EXCEPTION 'Dashboard failure: aggregate did not preserve RLS visibility';
    END IF;

    -- Copilot persistence must write exactly one audit row, link it to the
    -- assistant message and expose the stable usage-summary contract.
    v_copilot_conversation_id := bio_fn_create_copilot_conversation('Prueba RLS copiloto');
    v_copilot_usage_id := bio_fn_log_copilot_usage(
        'Prueba canónica de persistencia',
        'Respuesta verificable [obs-5005].',
        'security-test-v1',
        'bioma-policy',
        3,
        2,
        ARRAY[(SELECT bio_sighting_id FROM bio_sightings WHERE bio_observation_reference = 'obs-5005')],
        ARRAY[0.99::NUMERIC]
    );

    PERFORM bio_fn_record_copilot_turn(
        v_copilot_conversation_id,
        v_copilot_usage_id,
        'Prueba canónica de persistencia',
        'Respuesta verificable [obs-5005].'
    );

    SELECT COUNT(*) INTO v_copilot_message_count
    FROM bio_fn_get_copilot_conversation_messages(v_copilot_conversation_id);
    IF v_copilot_message_count <> 2 THEN
        RAISE EXCEPTION 'Copilot persistence failure: expected one user and one assistant message';
    END IF;

    SELECT COUNT(*) INTO v_copilot_audit_count
    FROM bio_copilot_usage
    WHERE bio_prompt_text = 'Prueba canónica de persistencia';
    IF v_copilot_audit_count <> 1 THEN
        RAISE EXCEPTION 'Copilot audit failure: a turn must create exactly one usage row';
    END IF;

    SELECT total_queries INTO v_copilot_summary_queries
    FROM bio_fn_copilot_usage_summary();
    IF v_copilot_summary_queries IS NULL OR v_copilot_summary_queries < 1 THEN
        RAISE EXCEPTION 'Copilot summary failure: stable actor-scoped totals were not returned';
    END IF;

    BEGIN
        PERFORM bio_fn_log_copilot_usage(
            'Intento de cita no autorizada',
            'No debe persistirse.',
            'security-test-v1',
            'bioma-policy',
            0,
            0,
            ARRAY[current_setting('app.test_hidden_sighting_id')::UUID],
            ARRAY[0.99::NUMERIC]
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_hidden_citation_rejected := true;
    END;
    IF NOT v_hidden_citation_rejected THEN
        RAISE EXCEPTION 'Copilot audit failure: hidden sighting citation was accepted';
    END IF;

    -- Refresh rotation returns the actor contract expected by the backend and
    -- links the new token to its parent in the correct direction.
    PERFORM bio_fn_create_refresh_token(
        (SELECT bio_researcher_id FROM bio_researchers WHERE bio_email = 'valentina.rios@yarumo.org'),
        repeat('a', 64),
        v_refresh_family_id,
        now() + INTERVAL '1 day',
        NULL
    );
    SELECT full_name INTO v_refresh_actor_name
    FROM bio_fn_rotate_refresh_token(repeat('a', 64), repeat('b', 64), now() + INTERVAL '2 days');
    IF v_refresh_actor_name <> 'Valentina Ríos' THEN
        RAISE EXCEPTION 'Refresh rotation failure: actor contract is invalid';
    END IF;

    BEGIN
        PERFORM bio_fn_rotate_refresh_token(
            repeat('a', 64), repeat('c', 64), now() + INTERVAL '2 days'
        );
    EXCEPTION
        WHEN SQLSTATE 'P0009' THEN
            v_refresh_reuse_rejected := true;
    END;
    IF NOT v_refresh_reuse_rejected THEN
        RAISE EXCEPTION 'Refresh rotation failure: reused token was accepted';
    END IF;

    -- =========================================================================
    -- QA & RLS: Pruebas de Canales de Chat, Aislamiento y No-Miembros (Punto 9)
    -- =========================================================================
    DECLARE
        v_camila_id UUID := (SELECT researcher_id FROM bio_fn_researcher_directory() WHERE full_name = 'Camila Andrade');
        v_nestor_id UUID := (SELECT researcher_id FROM bio_fn_researcher_directory() WHERE full_name = 'Néstor Quiñones');
        v_valentina_id UUID := (SELECT researcher_id FROM bio_fn_researcher_directory() WHERE full_name = 'Valentina Ríos');
        v_private_channel_id UUID;
        v_other_channel_id UUID;
        v_private_message_id UUID;
        v_other_message_id UUID;
        v_copilot_message_id UUID;
        v_history_count INTEGER;
        v_citation_count INTEGER;
        v_non_member_read_count INTEGER;
        v_non_member_send_rejected BOOLEAN := false;
        v_cross_channel_source_rejected BOOLEAN := false;
    BEGIN


        -- 1. Camila (actriz) crea un canal privado directo con Néstor
        PERFORM set_config('app.current_user_id', v_camila_id::text, true);
        v_private_channel_id := bio_fn_create_chat_channel('direct', NULL, ARRAY[v_nestor_id]);
        v_private_message_id := bio_fn_send_chat_message(v_private_channel_id, 'Mensaje privado confidencial de canal');

        SELECT COUNT(*) INTO v_history_count
        FROM bio_fn_chat_history(v_private_channel_id, NULL, NULL, 50)
        WHERE message_id = v_private_message_id;
        IF v_history_count <> 1 THEN
            RAISE EXCEPTION 'Chat history failure: newly sent message was not returned';
        END IF;

        v_copilot_message_id := bio_fn_record_chat_copilot_response(
            v_private_channel_id,
            'Respuesta sustentada en un mensaje autorizado.',
            jsonb_build_array(jsonb_build_object(
                'type', 'message',
                'reference', 'msg-' || substring(v_private_message_id::TEXT, 1, 8),
                'id', v_private_message_id
            ))
        );

        SELECT jsonb_array_length(citations) INTO v_citation_count
        FROM bio_fn_chat_history(v_private_channel_id, NULL, NULL, 50)
        WHERE message_id = v_copilot_message_id;
        IF v_citation_count <> 1 THEN
            RAISE EXCEPTION 'Chat copilot failure: authorized citation was not persisted in canonical format';
        END IF;

        -- A member cannot smuggle a message from another channel into the
        -- current channel's copilot citations.
        v_other_channel_id := bio_fn_create_chat_channel('direct', NULL, ARRAY[v_valentina_id]);
        v_other_message_id := bio_fn_send_chat_message(v_other_channel_id, 'Mensaje de otro canal');
        BEGIN
            PERFORM bio_fn_record_chat_copilot_response(
                v_private_channel_id,
                'Intento inválido',
                jsonb_build_array(jsonb_build_object(
                    'type', 'message',
                    'reference', 'msg-' || substring(v_other_message_id::TEXT, 1, 8),
                    'id', v_other_message_id
                ))
            );
        EXCEPTION
            WHEN insufficient_privilege THEN
                v_cross_channel_source_rejected := true;
        END;
        IF NOT v_cross_channel_source_rejected THEN
            RAISE EXCEPTION 'Chat copilot failure: cross-channel source was accepted';
        END IF;

        -- 2. Cambiamos de actor a Valentina (no es miembro de este canal privado)
        PERFORM set_config('app.current_user_id', v_valentina_id::text, true);


        -- Verificación A: El usuario no miembro no debe poder ver los mensajes del canal privado ajeno
        SELECT COUNT(*) INTO v_non_member_read_count
        FROM bio_chat_messages
        WHERE bio_chat_channel_id = v_private_channel_id;

        IF v_non_member_read_count <> 0 THEN
            RAISE EXCEPTION 'RLS Chat failure: non-member was able to read private messages from other users';
        END IF;

        -- Verificación B: El usuario no miembro debe ser rechazado al intentar enviar un mensaje
        BEGIN
            PERFORM bio_fn_send_chat_message(v_private_channel_id, 'Intento de infiltración');
        EXCEPTION
            WHEN sqlstate 'P0004' OR OTHERS THEN
                v_non_member_send_rejected := true;
        END;

        IF NOT v_non_member_send_rejected THEN
            RAISE EXCEPTION 'RLS Chat failure: non-member was not rejected when attempting to send message to private channel';
        END IF;

    END;
END;
$$;

ROLLBACK;
