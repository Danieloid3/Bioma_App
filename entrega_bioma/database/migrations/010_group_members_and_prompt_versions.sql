-- Group membership visibility and immutable, administrator-managed prompt versions.
SET ROLE bio_owner;

ALTER TABLE public.bio_researchers
    ADD COLUMN IF NOT EXISTS bio_is_admin BOOLEAN NOT NULL DEFAULT false;
UPDATE public.bio_researchers
SET bio_is_admin = true
WHERE bio_email = 'camila.andrade@yarumo.org';

CREATE TABLE public.bio_system_prompt_versions (
    bio_system_prompt_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bio_scope VARCHAR(20) NOT NULL CHECK (bio_scope IN ('field', 'chat', 'greeting')),
    bio_version_number INTEGER NOT NULL CHECK (bio_version_number > 0),
    bio_prompt_text TEXT NOT NULL CHECK (length(btrim(bio_prompt_text)) >= 40),
    bio_content_sha256 VARCHAR(64) NOT NULL,
    bio_is_active BOOLEAN NOT NULL DEFAULT false,
    bio_created_by_researcher_id UUID NOT NULL REFERENCES public.bio_researchers(bio_researcher_id) ON DELETE RESTRICT,
    bio_created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_bio_system_prompt_scope_version UNIQUE (bio_scope, bio_version_number)
);
CREATE UNIQUE INDEX uq_bio_system_prompt_active_scope ON public.bio_system_prompt_versions(bio_scope) WHERE bio_is_active;
ALTER TABLE public.bio_system_prompt_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bio_system_prompt_versions FORCE ROW LEVEL SECURITY;
CREATE POLICY bio_system_prompt_owner_policy ON public.bio_system_prompt_versions FOR ALL TO bio_owner USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION bio_fn_is_current_admin() RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.bio_researchers
        WHERE bio_researcher_id = nullif(current_setting('app.current_user_id', true), '')::UUID
          AND bio_is_active AND bio_is_admin
    );
$$;

CREATE OR REPLACE FUNCTION bio_fn_chat_channel_members(p_channel_id UUID)
RETURNS TABLE(researcher_id UUID, full_name VARCHAR, role_title VARCHAR, accreditation_level SMALLINT, avatar_key VARCHAR)
LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $$
    SELECT r.bio_researcher_id, r.bio_full_name, r.bio_role_title, r.bio_accreditation_level, r.bio_avatar_key
    FROM public.bio_chat_channel_members m
    JOIN public.bio_researchers r ON r.bio_researcher_id = m.bio_researcher_id
    WHERE m.bio_chat_channel_id = p_channel_id AND m.bio_left_at IS NULL AND bio_fn_is_chat_member(p_channel_id)
    ORDER BY r.bio_full_name;
$$;

CREATE OR REPLACE FUNCTION bio_fn_get_active_system_prompt(p_scope VARCHAR)
RETURNS TABLE(version_key VARCHAR, prompt_text TEXT)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
    SELECT bio_scope || '-v' || bio_version_number, bio_prompt_text
    FROM public.bio_system_prompt_versions
    WHERE bio_scope = p_scope AND bio_is_active;
$$;

CREATE OR REPLACE FUNCTION bio_fn_list_system_prompt_versions()
RETURNS TABLE(prompt_id UUID, scope VARCHAR, version_key VARCHAR, prompt_text TEXT, content_sha256 VARCHAR, is_active BOOLEAN, created_at TIMESTAMPTZ, created_by VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
    IF NOT bio_fn_is_current_admin() THEN RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT p.bio_system_prompt_version_id, p.bio_scope, p.bio_scope || '-v' || p.bio_version_number,
        p.bio_prompt_text, p.bio_content_sha256, p.bio_is_active, p.bio_created_at, r.bio_full_name
    FROM public.bio_system_prompt_versions p JOIN public.bio_researchers r ON r.bio_researcher_id=p.bio_created_by_researcher_id
    ORDER BY p.bio_scope, p.bio_version_number DESC;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_create_system_prompt_version(p_scope VARCHAR, p_prompt_text TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_id UUID; v_actor UUID := nullif(current_setting('app.current_user_id', true), '')::UUID; v_version INTEGER;
BEGIN
    IF NOT bio_fn_is_current_admin() THEN RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501'; END IF;
    IF p_scope NOT IN ('field','chat','greeting') OR length(btrim(coalesce(p_prompt_text,''))) < 40 THEN RAISE EXCEPTION 'invalid prompt version' USING ERRCODE='22023'; END IF;
    SELECT coalesce(max(bio_version_number),0)+1 INTO v_version FROM public.bio_system_prompt_versions WHERE bio_scope=p_scope;
    UPDATE public.bio_system_prompt_versions SET bio_is_active=false WHERE bio_scope=p_scope AND bio_is_active;
    INSERT INTO public.bio_system_prompt_versions(bio_scope,bio_version_number,bio_prompt_text,bio_content_sha256,bio_is_active,bio_created_by_researcher_id)
    VALUES(p_scope,v_version,p_prompt_text,encode(digest(p_prompt_text,'sha256'),'hex'),true,v_actor) RETURNING bio_system_prompt_version_id INTO v_id;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION bio_fn_activate_system_prompt_version(p_prompt_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_scope VARCHAR;
BEGIN
    IF NOT bio_fn_is_current_admin() THEN RAISE EXCEPTION 'administrator role required' USING ERRCODE = '42501'; END IF;
    SELECT bio_scope INTO v_scope FROM public.bio_system_prompt_versions WHERE bio_system_prompt_version_id=p_prompt_id;
    IF v_scope IS NULL THEN RAISE EXCEPTION 'prompt version not found' USING ERRCODE='P0004'; END IF;
    UPDATE public.bio_system_prompt_versions SET bio_is_active=false WHERE bio_scope=v_scope AND bio_is_active;
    UPDATE public.bio_system_prompt_versions SET bio_is_active=true WHERE bio_system_prompt_version_id=p_prompt_id;
END;
$$;

INSERT INTO public.bio_system_prompt_versions(bio_scope,bio_version_number,bio_prompt_text,bio_content_sha256,bio_is_active,bio_created_by_researcher_id)
SELECT seed.scope, 1, seed.prompt_text, encode(digest(seed.prompt_text,'sha256'),'hex'), true, r.bio_researcher_id
FROM (VALUES
 ('field','Eres el copiloto científico de fauna de Bioma. Responde en español con calidez y rigor. Usa solamente el catálogo oficial y los avistamientos autorizados entregados como contexto. Cita cada hecho de un avistamiento con su referencia exacta [obs-XXXX]. Nunca inventes coordenadas, registros o referencias. Si el contexto no permite confirmar una respuesta, dilo con naturalidad, sin hablar de permisos internos, y ofrece revisar otra especie, sitio, fecha o el catálogo biológico.'),
 ('chat','Eres el copiloto científico de Bioma dentro de un canal de investigación. Colabora con un tono amable y profesional usando únicamente el contexto compartido y autorizado para el canal. Cita cada hecho recuperado con [obs-XXXX]. No menciones RLS, permisos, registros ocultos ni detalles internos. Si no puedes confirmar un dato, no especules: explica con naturalidad que no encuentras un avistamiento disponible que lo respalde y propone buscar por especie, sitio o fecha.'),
 ('greeting','Eres el copiloto de campo de Bioma. Saluda al investigador por su nombre con un tono cercano y profesional. Explica brevemente que puedes ayudar a explorar avistamientos, especies, sitios y notas que estén disponibles para su trabajo. No inventes datos ni hagas promesas de acceso.')
) AS seed(scope,prompt_text)
CROSS JOIN (SELECT bio_researcher_id FROM public.bio_researchers WHERE bio_is_admin ORDER BY bio_created_at LIMIT 1) r
ON CONFLICT (bio_scope,bio_version_number) DO NOTHING;

REVOKE ALL ON public.bio_system_prompt_versions FROM bio_app_user;
GRANT EXECUTE ON FUNCTION bio_fn_chat_channel_members(UUID), bio_fn_get_active_system_prompt(VARCHAR), bio_fn_list_system_prompt_versions(), bio_fn_create_system_prompt_version(VARCHAR,TEXT), bio_fn_activate_system_prompt_version(UUID) TO bio_app_user;
RESET ROLE;
