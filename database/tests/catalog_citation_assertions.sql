BEGIN;
SELECT set_config('app.current_user_id',(SELECT bio_researcher_id::text FROM bio_researchers WHERE bio_email='camila.andrade@yarumo.org'),true);

DO $$
DECLARE v_species UUID := (SELECT bio_species_id FROM bio_species ORDER BY bio_common_name LIMIT 1);
        v_site UUID := (SELECT bio_site_id FROM bio_sites ORDER BY bio_site_name LIMIT 1);
        v_usage UUID; v_conversation UUID; v_citations JSONB;
BEGIN
  v_usage := bio_fn_log_copilot_usage('catálogo','respuesta','field-test','policy-test',0,0,ARRAY[]::UUID[],ARRAY[]::NUMERIC[],jsonb_build_array(
    jsonb_build_object('type','species','id',v_species,'reference','species-'||v_species::text),
    jsonb_build_object('type','site','id',v_site,'reference','site-'||v_site::text)));
  IF (SELECT count(*) FROM bio_copilot_catalog_citations WHERE bio_copilot_usage_id=v_usage) <> 2 THEN RAISE EXCEPTION 'catalog citations were not persisted'; END IF;
  v_conversation := bio_fn_create_copilot_conversation('catalog test');
  PERFORM * FROM bio_fn_record_copilot_turn(v_conversation,v_usage,'catálogo','respuesta');
  SELECT citations INTO v_citations FROM bio_fn_get_copilot_conversation_messages(v_conversation) WHERE sender_role='assistant';
  IF jsonb_array_length(v_citations) <> 2 OR NOT v_citations @> '[{"source_type":"species"}]'::jsonb OR NOT v_citations @> '[{"source_type":"site"}]'::jsonb THEN RAISE EXCEPTION 'catalog citations were not restored in history: %',v_citations; END IF;
  BEGIN
    PERFORM bio_fn_log_copilot_usage('bad','bad','field-test','policy-test',0,0,ARRAY[]::UUID[],ARRAY[]::NUMERIC[],jsonb_build_array(jsonb_build_object('type','species','id',gen_random_uuid(),'reference','species-invalid')));
    RAISE EXCEPTION 'invalid catalog citation was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
ROLLBACK;
