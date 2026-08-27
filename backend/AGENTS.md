# Backend Bioma — Contexto para agentes

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

## Copiloto RAG

1. Validar el actor y la pregunta.
2. Generar embedding mediante el puerto.
3. Recuperar fuentes con `bio_fn_retrieve_copilot_context` dentro de `actor_transaction`.
4. Construir el prompt en el servidor usando solo esas fuentes.
5. Tratar notas como datos no confiables, citar `obs_ref` y registrar uso/citas.

Si RLS no devuelve fuentes, el caso de uso responde `NO_AUTHORIZED_CONTEXT_RESPONSE` sin invocar al LLM y deja la auditoría registrada. Las pruebas unitarias de negativas viven en `tests/test_copilot_negative_responses.py`; las pruebas RLS/RAG contra PostgreSQL real viven en `database/tests/`.

El endpoint `POST /v1/copilot/ask` devuelve siempre las fuentes recuperadas para que la interfaz pueda citarlas; no debe aceptar contexto enviado por el cliente. `GET /v1/copilot/usage` expone únicamente el resumen del actor autenticado.

La recuperación RAG y la auditoría usan transacciones separadas: nunca mantener una transacción PostgreSQL abierta durante la llamada de red al modelo. Redis aplica rate limiting distribuido con claves HMAC, TTL, `429` y `Retry-After`.

Implementación local: `RedisRateLimiter` usa un script Lua atómico (`INCR` + `EXPIRE`). Login aplica ventanas independientes por IP y huella HMAC de cuenta; copiloto limita por investigador. El servicio Redis de Compose usa volumen persistente solo para desarrollo.

No hay excepción para prompts de usuarios, administradores o proveedores: contexto no autorizado nunca llega al modelo. LangChain es un adaptador, no el núcleo del dominio.

Configuración inicial: `gpt-5.6-terra` para conversación RAG (equilibrio de calidad y coste) y `text-embedding-3-small` para embeddings de 1536 dimensiones, compatibles con la columna `vector(1536)` de PostgreSQL.

## Buenas prácticas

- Usar Python async, type hints, Pydantic en el borde HTTP y dataclasses/entidades en dominio.
- Cada caso de uso debe tener una responsabilidad y ser testeable con puertos falsos.
- Preferir transacciones pequeñas y manejar `rollback` por excepción.
- Validar límites de page size, cursores completos, UUID y UTC.
- No guardar claves API, JWT secrets, refresh tokens planos ni hashes de contraseña en logs.
- CI ejecuta `ruff`, pruebas unitarias y `docker build`; las pruebas que requieran PostgreSQL se ejecutan adicionalmente con el perfil `test` de Compose.
- Actualizar este archivo al hacer commit si cambia esta arquitectura, patrón, dependencia, flujo de seguridad o comando backend.
