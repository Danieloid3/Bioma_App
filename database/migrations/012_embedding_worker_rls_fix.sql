-- Embedding jobs run without an actor context. Keep FORCE RLS on researcher
-- writes, but allow the SECURITY DEFINER worker functions to operate.
ALTER TABLE public.bio_sightings NO FORCE ROW LEVEL SECURITY;
ALTER FUNCTION public.bio_fn_claim_embedding_job(interval) SET row_security = off;
ALTER FUNCTION public.bio_fn_mark_embedding_failed(uuid, text) SET row_security = off;
ALTER FUNCTION public.bio_fn_store_sighting_embedding(uuid, vector, character varying) SET row_security = off;
