SET ROLE bio_owner;

CREATE FUNCTION bio_trg_fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    NEW.bio_updated_at := now();
    RETURN NEW;
END;
$$;

CREATE FUNCTION bio_trg_fn_protect_sighting_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NEW.bio_observation_reference IS DISTINCT FROM OLD.bio_observation_reference
       OR NEW.bio_researcher_id IS DISTINCT FROM OLD.bio_researcher_id
       OR NEW.bio_species_id IS DISTINCT FROM OLD.bio_species_id
       OR NEW.bio_site_id IS DISTINCT FROM OLD.bio_site_id
       OR NEW.bio_observed_at IS DISTINCT FROM OLD.bio_observed_at THEN
        RAISE EXCEPTION 'sighting identity fields are immutable' USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION bio_trg_fn_archive_sighting_revision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_actor_id UUID := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
BEGIN
    IF OLD.bio_field_notes IS NOT DISTINCT FROM NEW.bio_field_notes
       AND OLD.bio_classification_level IS NOT DISTINCT FROM NEW.bio_classification_level
       AND OLD.bio_exact_latitude IS NOT DISTINCT FROM NEW.bio_exact_latitude
       AND OLD.bio_exact_longitude IS NOT DISTINCT FROM NEW.bio_exact_longitude
       AND OLD.bio_is_voided IS NOT DISTINCT FROM NEW.bio_is_voided THEN
        RETURN NEW;
    END IF;
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'an actor is required to revise a sighting' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.bio_sighting_revisions (
        bio_sighting_id, bio_revision_number, bio_changed_by_researcher_id,
        bio_change_type, bio_previous_classification_level,
        bio_previous_exact_latitude, bio_previous_exact_longitude,
        bio_previous_field_notes, bio_change_reason
    ) VALUES (
        OLD.bio_sighting_id,
        (SELECT COALESCE(MAX(bio_revision_number), 0) + 1
         FROM public.bio_sighting_revisions
         WHERE bio_sighting_id = OLD.bio_sighting_id),
        v_actor_id,
        CASE WHEN NEW.bio_is_voided AND NOT OLD.bio_is_voided THEN 'voided' ELSE 'edited' END,
        OLD.bio_classification_level,
        OLD.bio_exact_latitude,
        OLD.bio_exact_longitude,
        OLD.bio_field_notes,
        NULLIF(current_setting('app.change_reason', true), '')
    );
    RETURN NEW;
END;
$$;

CREATE FUNCTION bio_trg_fn_invalidate_embedding()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.bio_field_notes IS DISTINCT FROM OLD.bio_field_notes THEN
        NEW.bio_field_notes_embedding := NULL;
        NEW.bio_embedding_status := 'pending';
        NEW.bio_embedding_model := NULL;
        NEW.bio_embedded_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION bio_trg_fn_forbid_sighting_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    RAISE EXCEPTION 'physical deletion of scientific evidence is prohibited' USING ERRCODE = '55000';
END;
$$;

CREATE FUNCTION bio_trg_fn_notify_sighting_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    -- Notification carries only an identifier; consumers must re-query through RLS.
    PERFORM pg_notify('bio_sighting_changed', NEW.bio_sighting_id::TEXT);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bio_researchers_30_touch
BEFORE UPDATE ON bio_researchers
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_species_30_touch
BEFORE UPDATE ON bio_species
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_sites_30_touch
BEFORE UPDATE ON bio_sites
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();

CREATE TRIGGER trg_bio_sightings_10_archive_revision
BEFORE UPDATE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_archive_sighting_revision();
CREATE TRIGGER trg_bio_sightings_15_protect_identity
BEFORE UPDATE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_protect_sighting_identity();
CREATE TRIGGER trg_bio_sightings_20_invalidate_embedding
BEFORE INSERT OR UPDATE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_invalidate_embedding();
CREATE TRIGGER trg_bio_sightings_30_touch
BEFORE UPDATE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_set_updated_at();
CREATE TRIGGER trg_bio_sightings_40_forbid_delete
BEFORE DELETE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_forbid_sighting_delete();
CREATE TRIGGER trg_bio_sightings_50_notify_change
AFTER INSERT OR UPDATE ON bio_sightings
FOR EACH ROW EXECUTE FUNCTION bio_trg_fn_notify_sighting_change();

RESET ROLE;

