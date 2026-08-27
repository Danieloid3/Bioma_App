-- 003_seed_data.sql
SET ROLE bio_owner;

DO $$
DECLARE
    v_camila UUID; v_nestor UUID; v_valentina UUID;
    v_r1 UUID; v_r2 UUID; v_r3 UUID; v_r4 UUID; v_r5 UUID; v_r6 UUID; v_r7 UUID; v_r8 UUID;
    v_rana UUID; v_oso UUID; v_condor UUID; v_colibri UUID; v_titi UUID; v_iguana UUID; v_jaguar UUID;
    v_nambi UUID; v_chingaza UUID; v_ceibal UUID; v_san_lucas UUID; v_sumapaz UUID;
BEGIN
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Camila Andrade', 'camila.andrade@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Scientific Coordinator', 3, 'spectacled_bear', '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_camila;
    
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Néstor Quiñones', 'nestor.quinones@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Field Biologist', 2, 'andean_condor', '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_nestor;
    
    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Valentina Ríos', 'valentina.rios@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Field Technician', 1, 'golden_poison_frog', '2025-06-01T00:00:00Z')
    RETURNING bio_researcher_id INTO v_valentina;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Laura Gómez', 'laura.gomez@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Ornitóloga Principal', 3, 'jaguar', '2026-02-01T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r1;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Carlos Restrepo', 'carlos.restrepo@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Mastozoólogo de Campo', 2, 'hummingbird', '2026-02-02T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r2;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Andrés Londoño', 'andres.londono@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Coordinadora de Botánica', 3, 'cotton_top_tamarin', '2026-02-03T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r3;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('María Camila Osorio', 'maria.osorio@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Guardaparques de Alta Montaña', 1, 'green_iguana', '2026-02-04T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r4;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Juan Pablo Arango', 'juan.arango@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Especialista en Herpetología', 3, 'mountain_tapir', '2026-02-05T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r5;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Valentina Jaramillo', 'valentina.jaramillo@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Investigadora Junior', 1, 'spectacled_bear', '2026-02-06T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r6;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Diego Botero', 'diego.botero@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Biólogo Acuático', 2, 'andean_condor', '2026-02-07T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r7;

    INSERT INTO bio_researchers (bio_full_name, bio_email, bio_password_hash, bio_role_title, bio_accreditation_level, bio_avatar_key, bio_created_at)
    VALUES ('Sofía Zapata', 'sofia.zapata@yarumo.org', crypt('Bioma2026!', gen_salt('bf', 12)), 'Entomóloga Senior', 2, 'golden_poison_frog', '2026-02-08T10:00:00Z')
    RETURNING bio_researcher_id INTO v_r8;

    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Rana dorada venenosa', 'Phyllobates terribilis', 'EN', 'Uno de los vertebrados más tóxicos del planeta. Es una pequeña rana diurna de color amarillo oro brillante o naranja metálico que sintetiza batracotoxina letal a partir de su dieta silvestre.', 'Suelo húmedo y hojarasca de la selva húmeda tropical del Chocó biogeográfico en la costa Pacífica colombiana (50 a 200 msnm).', 'Especialista en hormigas nativas, coleópteros diminutos y pequeños artrópodos que le proveen los alcaloides precursores de su toxina.', 'En Peligro (EN) según UICN. Endémica estricta de Colombia con un rango de distribución sumamente reducido amenazado por deforestación, minería ilegal y expansión agrícola.') RETURNING bio_species_id INTO v_rana;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Oso de anteojos', 'Tremarctos ornatus', 'VU', 'Único oso nativo de América del Sur y una de las especies sombrilla más representativas de los Andes tropicales. Posee pelaje negro o marrón oscuro con marcas claras características alrededor de los ojos, hocico y pecho.', 'Páramos, bosques de niebla y bosques altoandinos entre los 1.000 y 4.300 msnm en las tres cordilleras de Colombia.', 'Principalmente vegetariano (frugívoro y folívoro). Se alimenta de cogollos de frailejones (Espeletia), bromelias epífitas, palmas, frutos silvestres y ocasionalmente carroña o pequeños mamíferos.', 'Vulnerable (VU) según UICN y el Libro Rojo de Mamíferos de Colombia. Amenazado por deforestación, fragmentación de páramos y cacería por conflicto con actividades agropecuarias.') RETURNING bio_species_id INTO v_oso;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Cóndor de los Andes', 'Vultur gryphus', 'VU', 'Ave carroñera no marina de mayor envergadura alar de América del Sur y símbolo patrio de Colombia. Plumaje negro brillante con collar de plumas blancas y cabeza desnuda.', 'Alta montaña andina, páramos, riscos y cañones escarpados entre los 3.000 y 5.000 msnm.', 'Carroñero estricto. Cumple un rol ecológico indispensable en el saneamiento biológico de los páramos al consumir cadáveres de animales silvestres y ganado.', 'Vulnerable (VU) a nivel global y En Peligro Crítico (CR) en Colombia. Su población silvestre es reducida debido a envenenamientos accidentales, tendidos eléctricos y cacería.') RETURNING bio_species_id INTO v_condor;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Colibrí chillón', 'Colibri coruscans', 'LC', 'Colibrí de tamaño mediano con plumaje verde esmeralda brillante, escudo pectoral azul violeta iridiscente y un pico ligeramente curvado.', 'Cordilleras andinas, bordes de bosque altoandino, matorrales y jardines entre los 1.800 y 3.800 msnm.', 'Nectarívoro y polinizador clave de plantas andinas (Salvia, Fuchsia, Puya). Complementa su dieta con pequeños insectos capturados en vuelo.', 'Preocupación Menor (LC). Especie común, adaptable y con poblaciones estables en hábitats andinos.') RETURNING bio_species_id INTO v_colibri;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Tití cabeciblanco', 'Saguinus oedipus', 'CR', 'Pequeño primate endémico de Colombia, caracterizado por una llamativa cresta de pelo blanco largo que corona su cabeza desde la frente hasta la nuca.', 'Bosques secos tropicales y bosques húmedos de tierras bajas en el noroccidente de Colombia (región Caribe, cuencas de los ríos Sinú y Magdalena, hasta 1.500 msnm).', 'Omnívoro: frutos maduros, néctar, savia de árboles, insectos, arañas y pequeños lagartos.', 'En Peligro Crítico (CR) según UICN. Es una de las especies de primates más amenazadas del mundo debido a la pérdida de más del 75% de su bosque original y el tráfico de fauna silvestre.') RETURNING bio_species_id INTO v_titi;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Iguana verde', 'Iguana iguana', 'LC', 'Reptil escamoso arbóreo de gran tamaño. De color verde brillante con cresta dorsal de espinas y cola larga comprimida lateralmente.', 'Bosques tropicales de tierras bajas, manglares, riberas y selvas húmedas (0 a 1.000 msnm) siempre cerca de ríos o ciénagas.', 'Herbívora estricta en etapa adulta: hojas tiernas, flores, brotes y frutos.', 'Preocupación Menor (LC). Especie ampliamente distribuida pero sujeta a presión de cacería local y extracción de huevos.') RETURNING bio_species_id INTO v_iguana;
    
    INSERT INTO bio_species (bio_common_name, bio_scientific_name, bio_iucn_category, bio_description, bio_habitat, bio_diet, bio_conservation_status) VALUES
    ('Jaguar', 'Panthera onca', 'NT', 'El felino más grande de América y tercer carnívoro terrestre más grande del mundo. Posee pelaje amarillo leonado con rosetas oscuras y mandíbulas extremadamente poderosas.', 'Bosques húmedos tropicales, sabanas, bosques de galería y serranías de tierras bajas (0 a 2.000 msnm).', 'Carnívoro estricto y depredador tope. Caza pecaríes, chigüiros, venados, armadillos, caimanes y tortugas de río.', 'Casi Amenazado (NT) según UICN. En Colombia enfrenta severa fragmentación de corredores biológicos por ganadería extensiva y cacería en retaliación.') RETURNING bio_species_id INTO v_jaguar;

    INSERT INTO bio_sites (bio_site_name, bio_region, bio_description, bio_ecosystem) VALUES
    ('Reserva Río Ñambí', 'Nariño', 'Reserva natural comunitaria en la vertiente pacífica de la cordillera Occidental, considerada una de las zonas con mayor precipitación y biodiversidad del planeta por metro cuadrado.', 'Selva Húmeda Tropical Chocoana') RETURNING bio_site_id INTO v_nambi;
    
    INSERT INTO bio_sites (bio_site_name, bio_region, bio_description, bio_ecosystem) VALUES
    ('PNN Chingaza', 'Cundinamarca', 'Parque Nacional Natural en la cordillera Oriental con lagunas glaciares de origen sagrado muisca y extensos valles de frailejones. Es la principal fuente de agua potable para Bogotá.', 'Páramo y Bosque Altoandino') RETURNING bio_site_id INTO v_chingaza;
    
    INSERT INTO bio_sites (bio_site_name, bio_region, bio_description, bio_ecosystem) VALUES
    ('Reserva El Ceibal', 'Bolívar', 'Área protegida en el departamento de Bolívar dedicada a la preservación del relicto de bosque seco tropical del Caribe colombiano.', 'Bosque Seco Tropical') RETURNING bio_site_id INTO v_ceibal;
    
    INSERT INTO bio_sites (bio_site_name, bio_region, bio_description, bio_ecosystem) VALUES
    ('Serranía de San Lucas', 'Bolívar', 'Formación montañosa aislada y agreste entre los valles de los ríos Magdalena y Cauca. Constituye un refugio biológico estratégico y corredor de grandes felinos.', 'Bosque Húmedo Tropical y Subandino') RETURNING bio_site_id INTO v_san_lucas;
    
    INSERT INTO bio_sites (bio_site_name, bio_region, bio_description, bio_ecosystem) VALUES
    ('Páramo de Sumapaz', 'Cundinamarca', 'El complejo de páramos más extenso del planeta, ubicado en la cordillera Oriental. Alberga una gigantesca red hídrica, turberas y pajonales de alta montaña.', 'Páramo de Alta Montaña') RETURNING bio_site_id INTO v_sumapaz;

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
    ('obs-5010', v_nestor, v_oso, v_san_lucas, '2026-01-14T13:05:00Z', 8.130100, -74.048900, 2, 'Rastros de alimentación y marcas en corteza. No se observó el individuo directamente. Evidencia indirecta consistente con presencia reciente.', '2026-01-14T13:05:00Z'),
    ('obs-5011', v_r1, v_condor, v_chingaza, '2026-02-10T11:20:00Z', 4.541000, -73.739000, 2, 'Pareja de cóndores planeando en corrientes térmicas. Gran altitud. Se requiere monitoreo para confirmar nido.', '2026-02-10T11:20:00Z'),
    ('obs-5012', v_r2, v_jaguar, v_san_lucas, '2026-02-11T05:45:00Z', 8.125000, -74.055000, 3, 'Huellas frescas de jaguar cerca de la fuente de agua. Posible hembra joven. Datos de ubicación altamente sensibles.', '2026-02-11T05:45:00Z'),
    ('obs-5013', v_r5, v_rana, v_nambi, '2026-02-12T14:30:00Z', 1.279000, -78.094000, 3, 'Avistamiento de dos ejemplares de rana dorada en microhábitat muy húmedo. Especie crítica. Requiere reserva nivel 3.', '2026-02-12T14:30:00Z'),
    ('obs-5014', v_r4, v_oso, v_sumapaz, '2026-02-13T09:10:00Z', 3.988000, -74.300000, 2, 'Oso de anteojos alimentándose de bromelias. Individuo juvenil. El área presenta buena oferta alimenticia.', '2026-02-13T09:10:00Z'),
    ('obs-5015', v_r6, v_titi, v_ceibal, '2026-02-14T16:25:00Z', 9.802000, -75.121000, 3, 'Manada de tití cabeciblanco moviéndose en el dosel. Se registraron crías. Alta prioridad de conservación.', '2026-02-14T16:25:00Z'),
    ('obs-5016', v_r7, v_iguana, v_ceibal, '2026-02-15T10:40:00Z', 9.806000, -75.119000, 1, 'Iguana verde descansando cerca del cauce del río. Comportamiento normal. Observación sin restricciones.', '2026-02-15T10:40:00Z'),
    ('obs-5017', v_r1, v_colibri, v_chingaza, '2026-02-16T08:00:00Z', 4.532000, -73.746000, 1, 'Múltiples colibríes libando flores de puyas. Actividad matutina intensa. Especie abundante en la zona.', '2026-02-16T08:00:00Z'),
    ('obs-5018', v_r8, v_oso, v_chingaza, '2026-02-17T13:15:00Z', 4.522000, -73.752000, 2, 'Marcas de garras en árboles y heces frescas de oso. No hubo avistamiento directo, pero evidencia es contundente.', '2026-02-17T13:15:00Z');

    -- Annullation
    PERFORM set_config('app.current_user_id', v_camila::TEXT, true);
    PERFORM set_config('app.change_reason', 'Seed corpus: corrected data entry', true);
    UPDATE bio_sightings
    SET bio_is_voided = true,
        bio_voided_at = '2026-01-13T12:20:00Z',
        bio_voided_by_researcher_id = v_camila,
        bio_void_reason = 'Seed corpus: corrected data entry'
    WHERE bio_observation_reference = 'obs-5008';
    
    -- Preserve explicit edit
    PERFORM set_config('app.preserve_updated_at', 'true', true);
    UPDATE bio_sightings

    SET bio_updated_at = '2026-01-10T16:00:00Z'
    WHERE bio_observation_reference = 'obs-5003';
    
    -- Images
    INSERT INTO bio_species_images (bio_species_id, bio_display_url, bio_source_url, bio_alt_text_es, bio_alt_text_en, bio_attribution, bio_license_code, bio_license_url, bio_is_featured) VALUES
    (v_rana, 'https://upload.wikimedia.org/wikipedia/commons/9/96/Phyllobates_terribilis_01.JPG', 'https://commons.wikimedia.org/wiki/File:Phyllobates_terribilis_01.JPG', 'Rana dorada venenosa sobre hojarasca.', 'Golden poison frog on leaf litter.', 'The Lord of the Allosaurs / Wikimedia Commons', 'CC-BY-SA-3.0', 'https://creativecommons.org/licenses/by-sa/3.0/', true),
    (v_oso, 'https://inaturalist-open-data.s3.amazonaws.com/photos/187383867/medium.jpg', 'https://www.inaturalist.org/taxa/42051-Tremarctos-ornatus', 'Oso de anteojos en su hábitat.', 'Spectacled bear in its habitat.', '*snowwhite* / iNaturalist', 'CC-BY-NC-SA', 'https://creativecommons.org/licenses/by-nc-sa/4.0/', true),
    (v_condor, 'https://inaturalist-open-data.s3.amazonaws.com/photos/90906598/medium.jpg', 'https://www.inaturalist.org/taxa/5270-Vultur-gryphus', 'Cóndor de los Andes en vuelo.', 'Andean condor in flight.', 'Juan Rodolfo Lillo Lobos / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/', true),
    (v_colibri, 'https://inaturalist-open-data.s3.amazonaws.com/photos/444300759/medium.jpg', 'https://www.inaturalist.org/taxa/9759-Colibri-coruscans', 'Colibrí chillón posado.', 'Sparkling violetear perched.', 'Tony Iwane / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/', true),
    (v_titi, 'https://inaturalist-open-data.s3.amazonaws.com/photos/39541285/medium.jpg', 'https://www.inaturalist.org/taxa/41843-Saguinus-oedipus', 'Tití cabeciblanco.', 'Cotton-top tamarin.', 'Heather Pickard / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/', true),
    (v_iguana, 'https://inaturalist-open-data.s3.amazonaws.com/photos/356025444/medium.jpg', 'https://www.inaturalist.org/taxa/36229-Iguana-iguana', 'Iguana verde.', 'Green iguana.', 'Rainer Hungershausen / iNaturalist', 'CC-BY-NC-ND', 'https://creativecommons.org/licenses/by-nc-nd/4.0/', true),
    (v_jaguar, 'https://inaturalist-open-data.s3.amazonaws.com/photos/7272878/large.jpg', 'https://www.inaturalist.org/observations/7272878', 'Jaguar posado sobre troncos.', 'Jaguar resting on logs.', 'Laura Foy / iNaturalist', 'CC-BY-NC', 'https://creativecommons.org/licenses/by-nc/4.0/', true);

    INSERT INTO bio_site_images (bio_site_id, bio_display_url, bio_source_url, bio_alt_text_es, bio_alt_text_en, bio_attribution, bio_license_code, bio_license_url, bio_is_featured) VALUES
    (v_nambi, 'https://colombia.travel/sites/default/files/reserva-natural-rio-nambi_0.jpg', 'https://colombia.travel/en/blog/nature-and-adventure/forests-colombia', 'Vista aérea de la Reserva Natural Río Ñambí en Nariño.', 'Aerial view of Reserva Natural Río Ñambí in Nariño.', 'Colombia Travel', 'Términos del sitio', 'https://colombia.travel/en/legal-notice', true),
    (v_chingaza, 'https://commons.wikimedia.org/wiki/Special:FilePath/Parque%20Chingaza%20banner.jpg?width=1400', 'https://commons.wikimedia.org/wiki/File:Parque_Chingaza_banner.jpg', 'Panorámica del Parque Nacional Natural Chingaza.', 'Panorama of Chingaza National Natural Park.', 'Ministerio de Ambiente de Colombia / Wikimedia Commons', 'CC BY-SA 4.0', 'https://creativecommons.org/licenses/by-sa/4.0/', true),
    (v_ceibal, 'https://www.ecosistemassecos.org/images/proyectos/el_ceibal/P1140379.JPG', 'https://www.ecosistemassecos.org/en/programs/environmental-management-and-sustainable-use/declaration-protected-areas/55-el-ceibal-titi-monkey-dry-forest-regional-natural-park', 'Tití cabeciblanco en el bosque seco tropical del Parque Regional El Ceibal.', 'Cotton-top tamarin in the tropical dry forest of El Ceibal Regional Park.', 'Fundación Ecosistemas Secos de Colombia', 'Términos del sitio', 'https://www.ecosistemassecos.org/en/terms-of-use', true),
    (v_san_lucas, 'https://old.parquesnacionales.gov.co/portal/wp-content/uploads/2021/09/sanlucas.jpg', 'https://old.parquesnacionales.gov.co/portal/es/serrania-de-san-lucas-busca-una-estrategia-de-conservacion/', 'Paisaje de la Serranía de San Lucas en Bolívar.', 'Landscape of Serranía de San Lucas in Bolívar.', 'Parques Nacionales Naturales de Colombia', 'Términos del sitio', 'https://www.parquesnacionales.gov.co/', true),
    (v_sumapaz, 'https://upload.wikimedia.org/wikipedia/commons/0/0d/P%C3%A1ramo_de_Sumapaz.jpg', 'https://en.wikipedia.org/wiki/Climate_of_Colombia', 'Páramo de Sumapaz con frailejones y laguna.', 'Sumapaz moorland with frailejones and a lagoon.', 'Wikimedia Commons', 'Consultar ficha de archivo', 'https://commons.wikimedia.org/', true);

END;
$$;

RESET ROLE;

