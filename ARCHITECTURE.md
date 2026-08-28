# Arquitectura del backend Bioma

## Objetivo

El backend registra y consulta avistamientos sin convertir la API ni el modelo de IA en una capa de autorización. PostgreSQL es la autoridad final: RLS permite leer un avistamiento solo a su autor o a un investigador con acreditación suficiente.

## Capas

```text
presentation/api  -> FastAPI: HTTP, Pydantic, JWT y códigos de respuesta
application       -> casos de uso y orquestación de transacciones cortas
domain            -> modelos, errores y puertos; no depende de frameworks
infrastructure    -> asyncpg, bcrypt, JWT, Redis, LangChain/OpenAI y configuración
database          -> DDL, RLS, funciones, triggers, migraciones y pruebas SQL
```

Las dependencias apuntan hacia el dominio. Los adaptadores implementan puertos del dominio; los casos de uso no importan FastAPI, asyncpg ni LangChain.

## Flujo protegido de avistamientos

1. El bearer JWT identifica al investigador.
2. `Database.actor_transaction()` fija `app.current_user_id` con alcance local.
3. La API llama a funciones SQL parametrizadas.
4. PostgreSQL aplica RLS en listados, búsqueda y recuperación RAG.

No hay borrado físico: la anulación es lógica y un trigger conserva revisiones.

## RAG y auditoría

1. Se genera el embedding de la pregunta.
2. Una transacción corta recupera fuentes vectoriales visibles por RLS.
3. La conexión se cierra antes de llamar al proveedor IA.
4. LangChain recibe solo esas fuentes y el prompt activo resuelto desde PostgreSQL.
5. El caso de uso conserva solo referencias recuperadas por RLS y citadas explícitamente en la respuesta; una segunda transacción guarda una única auditoría y sus citas.
6. La persistencia del hilo enlaza el mensaje de asistente a esa misma auditoría; PostgreSQL vuelve a comprobar autorización y evita duplicar consumo.

Si RLS no devuelve fuentes, el caso de uso responde una negativa determinista y transparente, sin llamar al modelo. Las notas de campo son datos no confiables, nunca instrucciones.

Los embeddings se procesan en el worker independiente `app/workers/embeddings.py`. Los avistamientos, mensajes y fichas de especies/sitios tienen colas separadas reclamadas mediante `SKIP LOCKED`; el catálogo se recupera semánticamente sin mezclarse con las tablas protegidas por RLS. Las citas de catálogo se auditan en `bio_copilot_catalog_citations`, mientras las citas de avistamiento conservan su revalidación de acreditación o autoría.

## Mensajería interna protegida

El módulo `/v1/chat` crea canales directos o grupales, sus membresías, mensajes, recibos de lectura y versiones inmutables. Las mutaciones pasan por funciones SQL (`bio_fn_create_chat_channel`, `bio_fn_send_chat_message`, `bio_fn_chat_history`). Editar un mensaje registra la versión anterior en `bio_chat_message_versions` y marca `is_edited = true`. Eliminar un mensaje es lógico: actualiza `bio_is_deleted = true`, preserva la versión previa mediante el trigger `trg_bio_chat_messages_10_archive` y devuelve el texto tombstone *"Este mensaje fue eliminado"*, deshabilitando opciones de edición en la interfaz.

`bio_chat_channel_members` determina RLS para canal, mensaje, búsqueda, historial y recuperación vectorial. Los cursores de historial usan `(bio_created_at, bio_chat_message_id)`. Cuando el copiloto es consultado dentro de una conversación, `bio_fn_chat_shared_sightings()` recupera exclusivamente los avistamientos accesibles simultáneamente por todos los miembros del canal (intersección de acreditaciones RLS y autorías). Las citas persistidas usan el contrato canónico `source_type`, `source_reference` y `source_id`, y la función de escritura vuelve a verificar esa visibilidad compartida.

La sincronización en tiempo real usa SSE autenticado en `GET /v1/chat/events` y Redis Pub/Sub solamente como señal efímera entre réplicas. Un evento contiene solo `type` y `channel_id`: nunca texto, autor, citas ni datos de avistamientos. Antes de emitirlo, la API abre una transacción del actor y revalida la membresía mediante la misma función protegida por RLS. Tras recibirlo, el cliente vuelve a solicitar por REST el canal o historial afectado; esas respuestas siguen siendo la fuente de verdad y marcan como leído únicamente el canal abierto. Las mutaciones publican la señal tras confirmar la transacción PostgreSQL, con heartbeat y reconexión del cliente.

## Gestión de investigadores y procedimientos almacenados

La administración de usuarios se centraliza en procedimientos almacenados PostgreSQL definidos en `002_functions_and_triggers.sql`:
- `bio_sp_get_active_researchers(INOUT p_cursor REFCURSOR)`: Retorna un cursor tipado con el directorio de investigadores activos.
- `bio_sp_manage_researcher(p_researcher_id, p_full_name, p_role_title, p_is_active, p_accreditation_level)`: Valida la acreditación de nivel 3 del actor y ejecuta de forma atómica la edición o baja lógica (`bio_is_active = false`), impidiendo auto-bloqueos.


## Componentes transversales

- Redis limita login por IP/cuenta y consultas del copiloto por investigador con `INCR`+`EXPIRE` atómico.
- JWT de acceso corto y refresh token opaco, hasheado y rotativo.
- Errores HTTP uniformes y `X-Correlation-ID` en todas las respuestas.
- Docker Compose levanta PostgreSQL/pgvector, migrador, API, Redis y el worker de embeddings. El worker consume notas pendientes tras cada carga para que RAG tenga contexto disponible.
- Los prompts de campo, chat y saludo se guardan como versiones inmutables en PostgreSQL. Solo un investigador administrador puede crear o activar una versión; el backend obtiene la activa dentro de la transacción del actor y audita su identificador con cada respuesta.

## Dashboard, catálogo enriquecido y fichas científicas

El dashboard llama a funciones `SECURITY INVOKER` que agregan únicamente filas de `bio_sightings` visibles bajo RLS. La actividad une creación y revisiones, y `bio_sighting_revisions` posee su propia política RLS antes de poder leerse.

El catálogo oficial de especies (`bio_species`) y sitios (`bio_sites`) almacena fichas científicas curadas con descripción, hábitat, dieta, bioma y estado de conservación UICN, además de imágenes destacadas con fuente, licencia y textos alternativos. Estas fichas se consultan mediante `GET /v1/species` y `GET /v1/sites`, y se renderizan interactivamente en el cliente sin exponer ubicaciones sensibles.

La ficha de un avistamiento se obtiene con `bio_fn_get_sighting_detail`, también `SECURITY INVOKER`. El API devuelve 404 para una fila inexistente o no visible y evita que el cliente pueda distinguir ambos escenarios.

Los investigadores almacenan una clave de avatar de una biblioteca cerrada. Se entrega en login, refresh y directorio, pero no participa en el JWT como autorización ni habilita escrituras arbitrarias.

## CI/CD y Automatización

El repositorio cuenta con integración continua en GitHub Actions (`.github/workflows/ci.yml`):
- Validación de tipos TypeScript (`npx tsc --noEmit`) y compilación Vite de frontend.
- Validación de configuración `docker compose config`.
- Ejecución de migraciones y pruebas de seguridad RLS/RAG reales contra contenedor PostgreSQL (`docker compose --profile test run --rm database-tests`).
