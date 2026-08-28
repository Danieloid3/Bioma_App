# Backend Bioma — Contexto para agentes

- El catálogo de especies y sitios tiene embeddings y citas propias; `CopilotSource.source_type` distingue `sighting`, `message`, `species` y `site`. La auditoría nunca debe guardar una fuente de catálogo como si fuera un avistamiento.

## Misión

El backend expone la API de Bioma, incluye el directorio `database/` y coordina casos de uso delgados. No reimplementa la autorización de avistamientos: fija el actor autenticado por transacción y llama a PostgreSQL, donde RLS es la autoridad final.

## Arquitectura limpia

```text
app/domain/                 Entidades, errores y puertos (Protocol)
app/application/use_cases/  Orquestación de negocio sin HTTP, SQL ni LangChain
app/infrastructure/         Adaptadores asyncpg, JWT, bcrypt, LangChain y configuración
app/presentation/api/       FastAPI routers, esquemas Pydantic y dependencias
```

Las dependencias apuntan hacia `domain`. No importar `fastapi`, `asyncpg`, `langchain_*` ni paquetes de proveedor desde dominio o aplicación.

## Patrones que se deben conservar

- **Repository:** encapsula exclusivamente SQL parametrizado y mapeo de filas.
- **Unit of Work:** `Database.actor_transaction()` adquiere conexión, abre transacción y fija `app.current_user_id` con alcance local.
- **Adapter/Strategy:** `EmbeddingProvider` y `CopilotProvider` aíslan LangChain/proveedores de IA.
- **Factory:** selecciona adaptadores mediante configuración, no mediante condicionales repartidos en routers o casos de uso.
- **Use case:** los routers construyen adaptadores y delegan la operación; no contienen SQL ni reglas de negocio.
- **Worker:** `app/workers/embeddings.py` reclama trabajos mediante funciones `SECURITY DEFINER`, llama al puerto de embeddings y solo marca `ready` después de persistir el vector. El nombre almacenado es el modelo de embeddings, no el modelo conversacional.

No introducir CQRS, event sourcing, mediators ni abstracciones genéricas sin una necesidad demostrable.

## Seguridad

- La identidad, cargo y acreditación se obtienen del access token, nunca del body de una petición.
- PostgreSQL verifica la acreditación vigente; un claim sirve para contexto de UI, no para saltar RLS.
- Las operaciones protegidas deben usar `actor_transaction`; no hacer una consulta autenticada directamente al pool.
- No conceder escrituras directas a `bio_app_user`. Registrar, editar, anular, auditar y rotar tokens mediante funciones/procedimientos SQL.
- Hash de contraseñas: bcrypt. Refresh token: opaco, aleatorio, hasheado en BD, rotado por familia y enviado en cookie HttpOnly/Secure según entorno.
- Autenticación: login, refresh y logout viven en `app/application/use_cases/authentication.py`; el router solo configura la cookie y compone adaptadores. El access token JWT lleva `type=access` y nunca se acepta un refresh token como bearer.
- Ante reutilización de refresh token, `PostgresAuthenticationRepository` revoca la familia en una sentencia posterior: una excepción SQL deshace cualquier `UPDATE` ejecutado dentro de la función que la lanzó.
- Añadir correlation ID a logs, errores y respuestas. Mapear errores SQL conocidos a HTTP sin filtrar detalles internos.
- El contrato de error HTTP es `error.code`, `error.message`, `error.correlation_id` y, para validación, `error.details`; mantenerlo estable para el frontend.

## Copiloto RAG y Memoria Conversacional

1. Validar el actor y la pregunta.
2. Recuperar la memoria a corto plazo en Redis (`bioma:copilot:context:{actor_id}:{conv_id}`) con ventana deslizante de 16 mensajes (8 turnos).
3. Generar embedding mediante el puerto.
4. Recuperar fuentes con `bio_fn_retrieve_copilot_context` dentro de `actor_transaction`.
5. Construir el prompt en el servidor usando las fuentes autorizadas y el historial conversacional.
6. Tratar notas como datos no confiables, citar `obs_ref` y persistir el turno en `bio_copilot_messages` y `bio_copilot_conversations` bajo RLS.

Si RLS no devuelve fuentes, el caso de uso responde `NO_AUTHORIZED_CONTEXT_RESPONSE` sin invocar al LLM y deja la auditoría registrada. Las pruebas unitarias de negativas viven en `tests/test_copilot_negative_responses.py`; las pruebas RLS/RAG contra PostgreSQL real viven en `database/tests/`.

Los endpoints `/v1/copilot/conversations` y `/v1/copilot/conversations/{id}/messages` permiten gestionar hilos persistentes con aislamiento RLS completo. El endpoint `POST /v1/copilot/ask` asocia la consulta a un hilo activo, inyecta los mensajes previos de Redis y persiste la interacción.
- El baseline canónico concentra DDL/RLS en `001_core_schema.sql`, funciones/triggers en `002_functions_and_triggers.sql` y corpus en `003_seed_data.sql`.
- `004_hotfix_copilot.sql` restaura el worker de embeddings de chat tras la consolidación.
- `005_repair_copilot_persistence.sql` repara auditoría, persistencia de turnos, resumen de consumo y RLS de citas. Un turno reutiliza el `bio_copilot_usage_id` devuelto por la auditoría y nunca crea una segunda fila de consumo.
- `006_repair_chat_history_and_citations.sql` alinea historial y persistencia de citas del chat con el modelo canónico (`source_type`, `source_reference`, `source_id`) y valida que cada fuente sea visible para todos los miembros del canal.
- `007_repair_refresh_token_rotation.sql` restaura el contrato completo del actor durante la rotación y enlaza cada token hijo con el token original usado.
- `008_fix_chat_message_counter.sql` evita multiplicar el conteo de mensajes por el número de integrantes al listar canales.
- `009_chat_unread_receipts.sql` añade el contador de no leídos por actor y marca como leídos los recibos al abrir el historial.
- `010_group_members_and_prompt_versions.sql` agrega consulta de integrantes y prompts versionados por ámbito, con administración autorizada en PostgreSQL; `011_fix_prompt_function_contracts.sql` estabiliza sus contratos SQL.





El endpoint `POST /v1/copilot/ask` devuelve únicamente fuentes recuperadas por RLS que estén citadas explícitamente como `[obs-ref]` en su respuesta. El caso de uso descarta referencias inventadas; si no hay una cita válida, devuelve una negativa verificable y audita cero citas. No debe aceptar contexto enviado por el cliente. `GET /v1/copilot/usage` expone únicamente el resumen del actor autenticado.


`GET /v1/dashboard` usa funciones SQL invocadas bajo el actor para métricas, clasificación y actividad. No calcular agregados desde una conexión sin actor. `bio_sighting_revisions` tiene RLS propio porque conserva contenido sensible histórico; ningún endpoint debe consultar revisiones sin la transacción de actor.

`GET /v1/sightings/{sighting_id}` llama a una función `SECURITY INVOKER`, por lo que RLS decide la ficha completa, incluidas coordenadas. Un resultado vacío se traduce en 404 uniforme para no revelar la existencia de un registro restringido.

La recuperación RAG y la auditoría usan transacciones separadas: nunca mantener una transacción PostgreSQL abierta durante la llamada de red al modelo. Redis aplica rate limiting distribuido con claves HMAC, TTL, `429` y `Retry-After`.

Implementación local: `RedisRateLimiter` usa un script Lua atómico (`INCR` + `EXPIRE`). Login aplica ventanas independientes por IP y huella HMAC de cuenta; copiloto limita por investigador. El servicio Redis de Compose usa volumen persistente solo para desarrollo.

No hay excepción para prompts de usuarios, administradores o proveedores: contexto no autorizado nunca llega al modelo. LangChain es un adaptador, no el núcleo del dominio.

## Chat interno y copiloto compartido

Los canales internos aplican RLS por membresía. Cuando `@copilot` se invoca dentro de un canal, PostgreSQL recupera mensajes del canal y avistamientos únicamente si todos los miembros activos podrían verlos individualmente: la acreditación alta de una persona nunca amplía el contexto visible para otra. Las fuentes de mensaje usan referencias `msg-*`; las de avistamiento, `obs-*`.

El stream `GET /v1/chat/events` usa SSE con bearer y Redis Pub/Sub. Redis solo puede contener eventos mínimos (`type`, `channel_id`), publicados después de confirmar la transacción. Antes de emitir cada uno, revalidar membresía dentro de `actor_transaction`; jamás enviar contenido de mensajes ni fuentes por el stream. El historial que acompaña al copiloto del canal se recupera con `bio_fn_chat_history` dentro de la misma transacción del actor, nunca desde una conexión sin RLS.
La migración `012_chat_membership_and_read_events.sql` concentra las mutaciones seguras para agregar integrantes y abandonar canales; el endpoint solo invoca funciones `SECURITY DEFINER` y publica invalidaciones sin contenido. Abrir un canal marca los recibos pendientes del actor y publica `message.read` únicamente cuando hubo cambios, evitando bucles SSE.
La migración `013_chat_delivery_receipts.sql` expone por mensaje los conteos separados de recibos entregados y leídos; el cliente usa esos conteos para representar un check, dos checks o dos checks verdes sin consultar tablas directamente.
La migración `014_chat_channel_previews.sql` incorpora la vista previa del último mensaje al listado de canales desde la misma vista `SECURITY INVOKER` y con el mismo predicado de membresía RLS; el endpoint nunca consulta ni compone vistas previas fuera de `actor_transaction`.

Configuración inicial: `gpt-5.6-terra` para conversación RAG (equilibrio de calidad y coste) y `text-embedding-3-small` para embeddings de 1536 dimensiones, compatibles con la columna `vector(1536)` de PostgreSQL.

Los investigadores persisten una clave de avatar dentro de una biblioteca cerrada. La autenticación y el directorio la devuelven como dato de presentación; un futuro caso de uso de alta usará `secrets.choice` y nunca aceptará un URL o clave arbitraria del cliente.

## Buenas prácticas

- Usar Python async, type hints, Pydantic en el borde HTTP y dataclasses/entidades en dominio.
- Cada caso de uso debe tener una responsabilidad y ser testeable con puertos falsos.
- Preferir transacciones pequeñas y manejar `rollback` por excepción.
- Validar límites de page size, cursores completos, UUID y UTC.
- Enrutamiento FastAPI: declarar rutas estáticas específicas (ej. `/search`) antes de rutas paramétricas dinámicas (ej. `/{sighting_id}`) para evitar colisiones de validación de tipo (422).
- No guardar claves API, JWT secrets, refresh tokens planos ni hashes de contraseña en logs.
- CI ejecuta `ruff`, pruebas unitarias y `docker build`; las pruebas que requieran PostgreSQL se ejecutan adicionalmente con el perfil `test` de Compose.
- Actualizar este archivo al hacer commit si cambia esta arquitectura, patrón, dependencia, flujo de seguridad o comando backend.


- `003_seed_data.sql` contiene 11 investigadores con diversos niveles y especialidades para simular la interfaz y probar integralmente RLS y RAG.
