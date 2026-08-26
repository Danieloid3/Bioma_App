-- Canonical normalized loading of seed.json. Seed password for local demos: Bioma2026!
-- The migration administrator loads the corpus because bio_owner is forced through RLS.

DO $$
DECLARE
    v_camila UUID; v_nestor UUID; v_valentina UUID;
    v_rana UUID; v_oso UUID; v_condor UUID; v_colibri UUID; v_titi UUID; v_iguana UUID; v_jaguar UUID;
    v_nambi UUID; v_chingaza UUID; v_ceibal UUID; v_san_lucas UUID; v_sumapaz UUID;
BEGIN
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_created_at)
    VALUES ('Camila Andrade', 'camila.andrade@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Scientific Coordinator', 3, '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_camila;
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_created_at)
    VALUES ('Néstor Quiñones', 'nestor.quinones@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Field Biologist', 2, '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_nestor;
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_created_at)
    VALUES ('Valentina Ríos', 'valentina.rios@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Field Technician', 1, '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_valentina;

    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Rana dorada venenosa', 'Phyllobates terribilis', 'EN') RETURNING bio_species_id INTO v_rana;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Oso de anteojos', 'Tremarctos ornatus', 'VU') RETURNING bio_species_id INTO v_oso;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Cóndor de los Andes', 'Vultur gryphus', 'VU') RETURNING bio_species_id INTO v_condor;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Colibrí chillón', 'Colibri coruscans', 'LC') RETURNING bio_species_id INTO v_colibri;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Tití cabeciblanco', 'Saguinus oedipus', 'CR') RETURNING bio_species_id INTO v_titi;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Iguana verde', 'Iguana iguana', 'LC') RETURNING bio_species_id INTO v_iguana;
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category) VALUES ('Jaguar', 'Panthera onca', 'NT') RETURNING bio_species_id INTO v_jaguar;

    INSERT INTO bio_sites (bio_site_name, bio_region) VALUES ('Reserva Río Ñambí', 'Nariño') RETURNING bio_site_id INTO v_nambi;
    INSERT INTO bio_sites (bio_site_name, bio_region) VALUES ('PNN Chingaza', 'Cundinamarca') RETURNING bio_site_id INTO v_chingaza;
    INSERT INTO bio_sites (bio_site_name, bio_region) VALUES ('Reserva El Ceibal', 'Bolívar') RETURNING bio_site_id INTO v_ceibal;
    INSERT INTO bio_sites (bio_site_name, bio_region) VALUES ('Serranía de San Lucas', 'Bolívar') RETURNING bio_site_id INTO v_san_lucas;
    INSERT INTO bio_sites (bio_site_name, bio_region) VALUES ('Páramo de Sumapaz', 'Cundinamarca') RETURNING bio_site_id INTO v_sumapaz;

    INSERT INTO bio_sightings (bio_observation_reference, bio_researcher_id, bio_species_id, bio_site_id, bio_observed_at, bio_exact_latitude, bio_exact_longitude, bio_classification_level, bio_field_notes, bio_created_at) VALUES
    ('obs-5001', v_camila, v_rana, v_nambi, '2026-01-09T11:20:00Z', 1.278300, -78.093100, 3, 'Población pequeña detectada cerca de la quebrada norte. Piel con coloración intensa, indicador de alta toxicidad. Reportar ubicación exacta solo a nivel confidencial por riesgo de tráfico.', '2026-01-09T11:20:00Z'),
    ('obs-5002', v_camila, v_oso, v_chingaza, '2026-01-10T08:45:00Z', 4.521900, -73.751900, 2, 'Huellas frescas y rastros de alimentación en frailejones. Individuo adulto probable. Zona de páramo con buena conectividad de hábitat.', '2026-01-10T08:45:00Z'),
    ('obs-5003', v_nestor, v_condor, v_chingaza, '2026-01-10T15:30:00Z', 4.540100, -73.738800, 2, 'Avistamiento de dos individuos sobrevolando la cuchilla. Envergadura considerable. Se documentó con fotografía a distancia sin perturbar.', '2026-01-10T15:30:00Z'),
    ('obs-5004', v_nestor, v_colibri, v_chingaza, '2026-01-11T09:10:00Z', 4.531000, -73.745000, 1, 'Especie común y abundante en la zona. Varios individuos alimentándose en chuscales florecidos. Sin restricción de difusión.', '2026-01-11T09:10:00Z'),
    ('obs-5005', v_valentina, v_titi, v_ceibal, '2026-01-11T14:25:00Z', 9.801200, -75.120300, 3, 'Grupo familiar de aprox. 6 individuos. Especie endémica en peligro crítico. Ubicación altamente sensible por presión de tráfico de fauna.', '2026-01-11T14:25:00Z'),
    ('obs-5006', v_valentina, v_iguana, v_ceibal, '2026-01-12T10:40:00Z', 9.805500, -75.118000, 1, 'Adulto tomando sol sobre rama expuesta. Especie común. Buen indicador de recuperación del bosque seco tropical.', '2026-01-12T10:40:00Z'),
    ('obs-5007', v_nestor, v_jaguar, v_san_lucas, '2026-01-13T06:00:00Z', 8.123400, -74.056700, 3, 'Registro en cámara trampa de un macho adulto. Zona de corredor biológico. Ubicación confidencial: presencia de actividad de caza en el área.', '2026-01-13T06:00:00Z'),
    ('obs-5008', v_camila, v_rana, v_nambi, '2026-01-13T12:15:00Z', 1.280100, -78.095500, 3, 'Segundo registro en la misma reserva, quebrada sur. Confirma presencia estable. Este avistamiento reemplazaba un dato mal digitado y quedó anulado.', '2026-01-13T12:15:00Z'),
    ('obs-5009', v_valentina, v_condor, v_sumapaz, '2026-01-14T07:50:00Z', 3.987600, -74.301200, 2, 'Un individuo juvenil posado en risco. Registro relevante por ampliar el rango conocido. La autora tiene acreditación básica pero es su propio registro.', '2026-01-14T07:50:00Z'),
    ('obs-5010', v_nestor, v_oso, v_san_lucas, '2026-01-14T13:05:00Z', 8.130100, -74.048900, 2, 'Rastros de alimentación y marcas en corteza. No se observó el individuo directamente. Evidencia indirecta consistente con presencia reciente.', '2026-01-14T13:05:00Z');

    -- Preserve the original corpus state for the annulled observation without physical deletion.
    PERFORM set_config('app.current_user_id', v_camila::TEXT, true);
    PERFORM set_config('app.change_reason', 'Seed corpus: corrected data entry', true);
    UPDATE bio_sightings
    SET bio_is_voided = true,
        bio_voided_at = '2026-01-13T12:20:00Z',
        bio_voided_by_researcher_id = v_camila,
        bio_void_reason = 'Seed corpus: corrected data entry'
    WHERE bio_observation_reference = 'obs-5008';

END;
$$;

RESET ROLE;
