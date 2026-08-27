SET ROLE bio_owner;

-- Site catalogue imagery is deliberately separate from scientific observations.
-- It depicts a representative public landscape, never an observation, route or
-- coordinate, and remains attributable and replaceable by curators.
CREATE TABLE bio_site_images (
    bio_site_image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_site_id UUID NOT NULL REFERENCES bio_sites (bio_site_id) ON DELETE RESTRICT,
    bio_display_url TEXT NOT NULL CHECK (bio_display_url ~ '^https://'),
    bio_source_url TEXT NOT NULL CHECK (bio_source_url ~ '^https://'),
    bio_alt_text_es VARCHAR(300) NOT NULL CHECK (length(btrim(bio_alt_text_es)) > 0),
    bio_alt_text_en VARCHAR(300) NOT NULL CHECK (length(btrim(bio_alt_text_en)) > 0),
    bio_attribution TEXT NOT NULL CHECK (length(btrim(bio_attribution)) > 0),
    bio_license_code VARCHAR(40) NOT NULL CHECK (length(btrim(bio_license_code)) > 0),
    bio_license_url TEXT NOT NULL CHECK (bio_license_url ~ '^https://'),
    bio_is_featured BOOLEAN NOT NULL DEFAULT false,
    bio_is_active BOOLEAN NOT NULL DEFAULT true,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bio_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uix_bio_site_images_featured_active
    ON bio_site_images (bio_site_id)
    WHERE bio_is_featured AND bio_is_active;

CREATE INDEX ix_bio_site_images_site_active
    ON bio_site_images (bio_site_id)
    WHERE bio_is_active;

CREATE TRIGGER bio_site_images_set_updated_at
BEFORE UPDATE ON bio_site_images
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();

-- Curated public landscape illustrations, not evidence associated with a
-- sighting. Unsplash assets are used under the Unsplash License and retain
-- their source and attribution for presentation in the client.
INSERT INTO bio_site_images (
    bio_site_id, bio_display_url, bio_source_url, bio_alt_text_es, bio_alt_text_en,
    bio_attribution, bio_license_code, bio_license_url, bio_is_featured
)
SELECT s.bio_site_id, v.display_url, v.source_url, v.alt_es, v.alt_en,
       v.attribution, v.license_code, v.license_url, true
FROM bio_sites AS s
JOIN (VALUES
    ('Reserva Río Ñambí', 'Nariño',
     'https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=1200&q=85',
     'https://unsplash.com/photos/0YHIlxeCuhg',
     'Bosque húmedo tropical representativo de la Reserva Río Ñambí.',
     'Tropical rainforest representative of Reserva Río Ñambí.',
     'Casey Horner / Unsplash', 'Unsplash License', 'https://unsplash.com/license'),
    ('PNN Chingaza', 'Cundinamarca',
     'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=1200&q=85',
     'https://unsplash.com/photos/7YVZYZeITc8',
     'Paisaje altoandino representativo del Parque Nacional Natural Chingaza.',
     'High-Andean landscape representative of Chingaza National Natural Park.',
     'eberhard grossgasteiger / Unsplash', 'Unsplash License', 'https://unsplash.com/license'),
    ('Reserva El Ceibal', 'Bolívar',
     'https://images.unsplash.com/photo-1513836279014-a89f7a76ae86?auto=format&fit=crop&w=1200&q=85',
     'https://unsplash.com/photos/ANbPxQmF-0Q',
     'Dosel de bosque tropical representativo de la Reserva El Ceibal.',
     'Tropical forest canopy representative of Reserva El Ceibal.',
     'Niko Photos / Unsplash', 'Unsplash License', 'https://unsplash.com/license'),
    ('Serranía de San Lucas', 'Bolívar',
     'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1200&q=85',
     'https://unsplash.com/photos/uOiD0ejlQ1A',
     'Bosque montañoso representativo de la Serranía de San Lucas.',
     'Mountain forest representative of Serranía de San Lucas.',
     'Lukasz Szmigiel / Unsplash', 'Unsplash License', 'https://unsplash.com/license'),
    ('Páramo de Sumapaz', 'Cundinamarca',
     'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1200&q=85',
     'https://unsplash.com/photos/9SoCnyQmkzI',
     'Paisaje de montaña representativo del Páramo de Sumapaz.',
     'Mountain landscape representative of Páramo de Sumapaz.',
     'Jake Weirick / Unsplash', 'Unsplash License', 'https://unsplash.com/license')
) AS v(site_name, region, display_url, source_url, alt_es, alt_en, attribution, license_code, license_url)
  ON s.bio_site_name = v.site_name AND s.bio_region = v.region;

GRANT SELECT ON public.bio_site_images TO bio_app_user;

RESET ROLE;
