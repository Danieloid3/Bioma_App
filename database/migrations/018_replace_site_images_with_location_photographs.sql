SET ROLE bio_owner;

-- Replace generic stock landscapes with photographs that identify the monitored
-- place itself.  These remain catalogue art only: no observation, route or
-- sensitive sighting coordinate is ever used as a site image.
UPDATE bio_site_images AS image
SET bio_display_url = source.display_url,
    bio_source_url = source.source_url,
    bio_alt_text_es = source.alt_es,
    bio_alt_text_en = source.alt_en,
    bio_attribution = source.attribution,
    bio_license_code = source.license_code,
    bio_license_url = source.license_url
FROM (
    VALUES
      ('Reserva Río Ñambí', 'Nariño',
       'https://colombia.travel/sites/default/files/reserva-natural-rio-nambi_0.jpg',
       'https://colombia.travel/en/blog/nature-and-adventure/forests-colombia',
       'Vista aérea de la Reserva Natural Río Ñambí en Nariño.',
       'Aerial view of Reserva Natural Río Ñambí in Nariño.',
       'Colombia Travel', 'Términos del sitio', 'https://colombia.travel/en/legal-notice'),
      ('PNN Chingaza', 'Cundinamarca',
       'https://commons.wikimedia.org/wiki/Special:FilePath/Parque%20Chingaza%20banner.jpg?width=1400',
       'https://commons.wikimedia.org/wiki/File:Parque_Chingaza_banner.jpg',
       'Panorámica del Parque Nacional Natural Chingaza.',
       'Panorama of Chingaza National Natural Park.',
       'Ministerio de Ambiente de Colombia / Wikimedia Commons', 'CC BY-SA 4.0', 'https://creativecommons.org/licenses/by-sa/4.0/'),
      ('Reserva El Ceibal', 'Bolívar',
       'https://www.ecosistemassecos.org/images/proyectos/el_ceibal/P1140379.JPG',
       'https://www.ecosistemassecos.org/en/programs/environmental-management-and-sustainable-use/declaration-protected-areas/55-el-ceibal-titi-monkey-dry-forest-regional-natural-park',
       'Tití cabeciblanco en el bosque seco tropical del Parque Regional El Ceibal.',
       'Cotton-top tamarin in the tropical dry forest of El Ceibal Regional Park.',
       'Fundación Ecosistemas Secos de Colombia', 'Términos del sitio', 'https://www.ecosistemassecos.org/en/terms-of-use'),
      ('Serranía de San Lucas', 'Bolívar',
       'https://old.parquesnacionales.gov.co/portal/wp-content/uploads/2021/09/sanlucas.jpg',
       'https://old.parquesnacionales.gov.co/portal/es/serrania-de-san-lucas-busca-una-estrategia-de-conservacion/',
       'Paisaje de la Serranía de San Lucas en Bolívar.',
       'Landscape of Serranía de San Lucas in Bolívar.',
       'Parques Nacionales Naturales de Colombia', 'Términos del sitio', 'https://www.parquesnacionales.gov.co/'),
      ('Páramo de Sumapaz', 'Cundinamarca',
       'https://upload.wikimedia.org/wikipedia/commons/0/0d/P%C3%A1ramo_de_Sumapaz.jpg',
       'https://en.wikipedia.org/wiki/Climate_of_Colombia',
       'Páramo de Sumapaz con frailejones y laguna.',
       'Sumapaz moorland with frailejones and a lagoon.',
       'Wikimedia Commons', 'Consultar ficha de archivo', 'https://commons.wikimedia.org/')
) AS source(site_name, region, display_url, source_url, alt_es, alt_en, attribution, license_code, license_url)
  JOIN bio_sites AS site
    ON site.bio_site_name = source.site_name AND site.bio_region = source.region
WHERE image.bio_site_id = site.bio_site_id
  AND image.bio_is_featured
  AND image.bio_is_active;

RESET ROLE;
