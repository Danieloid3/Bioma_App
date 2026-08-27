-- The worker has no researcher actor context. Its claim function is SECURITY
-- DEFINER, but sightings enforce FORCE ROW LEVEL SECURITY, so explicitly
-- disable row security for this tightly scoped worker operation.
ALTER FUNCTION public.bio_fn_claim_embedding_job(interval) SET row_security = off;
ALTER FUNCTION public.bio_fn_mark_embedding_failed(uuid, text) SET row_security = off;
ALTER FUNCTION public.bio_fn_store_sighting_embedding(uuid, vector, character varying) SET row_security = off;
