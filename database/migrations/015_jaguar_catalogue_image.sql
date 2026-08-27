SET ROLE bio_owner;

INSERT INTO bio_species_images (
    bio_species_id, bio_display_url, bio_source_url, bio_alt_text_es, bio_alt_text_en,
    bio_attribution, bio_license_code, bio_license_url, bio_is_featured
)
SELECT bio_species_id,
       'https://inaturalist-open-data.s3.amazonaws.com/photos/7272878/large.jpg',
       'https://www.inaturalist.org/observations/7272878',
       'Jaguar posado sobre troncos.',
       'Jaguar resting on logs.',
       'Laura Foy / iNaturalist',
       'CC-BY-NC',
       'https://creativecommons.org/licenses/by-nc/4.0/',
       true
FROM bio_species
WHERE bio_scientific_name = 'Panthera onca';

RESET ROLE;
