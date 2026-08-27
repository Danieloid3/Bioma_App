SET ROLE bio_owner;

-- Add descriptive biological and ecological columns to bio_species
ALTER TABLE bio_species
    ADD COLUMN IF NOT EXISTS bio_description TEXT,
    ADD COLUMN IF NOT EXISTS bio_habitat TEXT,
    ADD COLUMN IF NOT EXISTS bio_diet TEXT,
    ADD COLUMN IF NOT EXISTS bio_conservation_status TEXT;

-- Add descriptive columns to bio_sites
ALTER TABLE bio_sites
    ADD COLUMN IF NOT EXISTS bio_description TEXT,
    ADD COLUMN IF NOT EXISTS bio_ecosystem VARCHAR(100);

-- Populate rich biological descriptions for all 7 catalog species
UPDATE bio_species
SET bio_description = 'Único oso nativo de América del Sur y una de las especies sombrilla más representativas de los Andes tropicales. Posee pelaje negro o marrón oscuro con marcas claras características alrededor de los ojos, hocico y pecho.',
    bio_habitat = 'Páramos, bosques de niebla y bosques altoandinos entre los 1.000 y 4.300 msnm en las tres cordilleras de Colombia.',
    bio_diet = 'Principalmente vegetariano (frugívoro y folívoro). Se alimenta de cogollos de frailejones (Espeletia), bromelias epífitas, palmas, frutos silvestres y ocasionalmente carroña o pequeños mamíferos.',
    bio_conservation_status = 'Vulnerable (VU) según UICN y el Libro Rojo de Mamíferos de Colombia. Amenazado por deforestación, fragmentación de páramos y cacería por conflicto con actividades agropecuarias.'
WHERE bio_scientific_name = 'Tremarctos ornatus';

UPDATE bio_species
SET bio_description = 'Ave carroñera no marina de mayor envergadura alar de América del Sur y símbolo patrio de Colombia. Plumaje negro brillante con collar de plumas blancas y cabeza desnuda.',
    bio_habitat = 'Alta montaña andina, páramos, riscos y cañones escarpados entre los 3.000 y 5.000 msnm.',
    bio_diet = 'Carroñero estricto. Cumple un rol ecológico indispensable en el saneamiento biológico de los páramos al consumir cadáveres de animales silvestres y ganado.',
    bio_conservation_status = 'Vulnerable (VU) a nivel global y En Peligro Crítico (CR) en Colombia. Su población silvestre es reducida debido a envenenamientos accidentales, tendidos eléctricos y cacería.'
WHERE bio_scientific_name = 'Vultur gryphus';

UPDATE bio_species
SET bio_description = 'Uno de los vertebrados más tóxicos del planeta. Es una pequeña rana diurna de color amarillo oro brillante o naranja metálico que sintetiza batracotoxina letal a partir de su dieta silvestre.',
    bio_habitat = 'Suelo húmedo y hojarasca de la selva húmeda tropical del Chocó biogeográfico en la costa Pacífica colombiana (50 a 200 msnm).',
    bio_diet = 'Especialista en hormigas nativas, coleópteros diminutos y pequeños artrópodos que le proveen los alcaloides precursores de su toxina.',
    bio_conservation_status = 'En Peligro (EN) según UICN. Endémica estricta de Colombia con un rango de distribución sumamente reducido amenazado por deforestación, minería ilegal y expansión agrícola.'
WHERE bio_scientific_name = 'Phyllobates terribilis';

UPDATE bio_species
SET bio_description = 'Pequeño primate endémico de Colombia, caracterizado por una llamativa cresta de pelo blanco largo que corona su cabeza desde la frente hasta la nuca.',
    bio_habitat = 'Bosques secos tropicales y bosques húmedos de tierras bajas en el noroccidente de Colombia (región Caribe, cuencas de los ríos Sinú y Magdalena, hasta 1.500 msnm).',
    bio_diet = 'Omnívoro: frutos maduros, néctar, savia de árboles, insectos, arañas y pequeños lagartos.',
    bio_conservation_status = 'En Peligro Crítico (CR) según UICN. Es una de las especies de primates más amenazadas del mundo debido a la pérdida de más del 75% de su bosque original y el tráfico de fauna silvestre.'
WHERE bio_scientific_name = 'Saguinus oedipus';

UPDATE bio_species
SET bio_description = 'El felino más grande de América y tercer carnívoro terrestre más grande del mundo. Posee pelaje amarillo leonado con rosetas oscuras y mandíbulas extremadamente poderosas.',
    bio_habitat = 'Bosques húmedos tropicales, sabanas, bosques de galería y serranías de tierras bajas (0 a 2.000 msnm).',
    bio_diet = 'Carnívoro estricto y depredador tope. Caza pecaríes, chigüiros, venados, armadillos, caimanes y tortugas de río.',
    bio_conservation_status = 'Casi Amenazado (NT) según UICN. En Colombia enfrenta severa fragmentación de corredores biológicos por ganadería extensiva y cacería en retaliación.'
WHERE bio_scientific_name = 'Panthera onca';

UPDATE bio_species
SET bio_description = 'Colibrí de tamaño mediano con plumaje verde esmeralda brillante, escudo pectoral azul violeta iridiscente y un pico ligeramente curvado.',
    bio_habitat = 'Cordilleras andinas, bordes de bosque altoandino, matorrales y jardines entre los 1.800 y 3.800 msnm.',
    bio_diet = 'Nectarívoro y polinizador clave de plantas andinas (Salvia, Fuchsia, Puya). Complementa su dieta con pequeños insectos capturados en vuelo.',
    bio_conservation_status = 'Preocupación Menor (LC). Especie común, adaptable y con poblaciones estables en hábitats andinos.'
WHERE bio_scientific_name = 'Colibri coruscans';

UPDATE bio_species
SET bio_description = 'Reptil escamoso arbóreo de gran tamaño. De color verde brillante con cresta dorsal de espinas y cola larga comprimida lateralmente.',
    bio_habitat = 'Bosques tropicales de tierras bajas, manglares, riberas y selvas húmedas (0 a 1.000 msnm) siempre cerca de ríos o ciénagas.',
    bio_diet = 'Herbívora estricta en etapa adulta: hojas tiernas, flores, brotes y frutos.',
    bio_conservation_status = 'Preocupación Menor (LC). Especie ampliamente distribuida pero sujeta a presión de cacería local y extracción de huevos.'
WHERE bio_scientific_name = 'Iguana iguana';

-- Populate rich descriptions for all 5 monitored sites
UPDATE bio_sites
SET bio_description = 'Parque Nacional Natural en la cordillera Oriental con lagunas glaciares de origen sagrado muisca y extensos valles de frailejones. Es la principal fuente de agua potable para Bogotá.',
    bio_ecosystem = 'Páramo y Bosque Altoandino'
WHERE bio_site_name = 'PNN Chingaza';

UPDATE bio_sites
SET bio_description = 'El complejo de páramos más extenso del planeta, ubicado en la cordillera Oriental. Alberga una gigantesca red hídrica, turberas y pajonales de alta montaña.',
    bio_ecosystem = 'Páramo de Alta Montaña'
WHERE bio_site_name = 'Páramo de Sumapaz';

UPDATE bio_sites
SET bio_description = 'Reserva natural comunitaria en la vertiente pacífica de la cordillera Occidental, considerada una de las zonas con mayor precipitación y biodiversidad del planeta por metro cuadrado.',
    bio_ecosystem = 'Selva Húmeda Tropical Chocoana'
WHERE bio_site_name = 'Reserva Río Ñambí';

UPDATE bio_sites
SET bio_description = 'Formación montañosa aislada y agreste entre los valles de los ríos Magdalena y Cauca. Constituye un refugio biológico estratégico y corredor de grandes felinos.',
    bio_ecosystem = 'Bosque Húmedo Tropical y Subandino'
WHERE bio_site_name = 'Serranía de San Lucas';

UPDATE bio_sites
SET bio_description = 'Área protegida en el departamento de Bolívar dedicada a la preservación del relicto de bosque seco tropical del Caribe colombiano.',
    bio_ecosystem = 'Bosque Seco Tropical'
WHERE bio_site_name = 'Reserva El Ceibal';

-- Create catalog knowledge query function
CREATE OR REPLACE FUNCTION bio_fn_get_knowledge_catalog()
RETURNS TABLE (
    catalog_type TEXT,
    common_name TEXT,
    scientific_name TEXT,
    iucn_category TEXT,
    ecosystem TEXT,
    region TEXT,
    description TEXT,
    habitat TEXT,
    diet TEXT,
    conservation_status TEXT
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
    SELECT 'species'::TEXT AS catalog_type,
           sp.bio_common_name::TEXT AS common_name,
           sp.bio_scientific_name::TEXT AS scientific_name,
           sp.bio_iucn_category::TEXT AS iucn_category,
           NULL::TEXT AS ecosystem,
           NULL::TEXT AS region,
           sp.bio_description AS description,
           sp.bio_habitat AS habitat,
           sp.bio_diet AS diet,
           sp.bio_conservation_status AS conservation_status
    FROM public.bio_species AS sp
    UNION ALL
    SELECT 'site'::TEXT AS catalog_type,
           si.bio_site_name::TEXT AS common_name,
           NULL::TEXT AS scientific_name,
           NULL::TEXT AS iucn_category,
           si.bio_ecosystem::TEXT AS ecosystem,
           si.bio_region::TEXT AS region,
           si.bio_description AS description,
           NULL::TEXT AS habitat,
           NULL::TEXT AS diet,
           NULL::TEXT AS conservation_status
    FROM public.bio_sites AS si;
$$;

GRANT EXECUTE ON FUNCTION bio_fn_get_knowledge_catalog() TO bio_app_user;

RESET ROLE;