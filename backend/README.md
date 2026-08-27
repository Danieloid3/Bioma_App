# Bioma Backend

API FastAPI, PostgreSQL/pgvector y migraciones de Bioma. La autorización de avistamientos se impone dentro de PostgreSQL mediante Row Level Security; la API solo propaga el actor autenticado a una transacción local.

## Desarrollo local

```bash
Copy-Item .env.example .env
docker compose up --build
```

API y OpenAPI: `http://localhost:8001/docs`.

`GET /health` comprueba que el proceso está activo y `GET /ready` verifica la conexión a PostgreSQL. Todas las respuestas incluyen `X-Correlation-ID`; los errores usan el contrato `error.code`, `error.message`, `error.correlation_id` y, en errores de validación, `error.details`.

## Autenticación

- `POST /v1/auth/login` recibe `email` y `password`, devuelve un JWT de acceso corto y fija un refresh token opaco en cookie HttpOnly.
- `POST /v1/auth/refresh` rota esa cookie; la reutilización de una cookie previa revoca toda su familia de sesión.
- `POST /v1/auth/logout` revoca la familia y elimina la cookie.

El seed de desarrollo usa la contraseña `Bioma2026!`. No cargar ese seed ni permitir `REFRESH_COOKIE_SECURE=false` en producción.

## Avistamientos y catálogo

Con access token bearer, `GET /v1/species`, `GET /v1/sites`, `GET /v1/sightings` y `GET /v1/sightings/search?term=...` solo entregan filas autorizadas por RLS. `POST /v1/sightings`, `PATCH /v1/sightings/{id}` y `POST /v1/sightings/{id}/void` delegan las escrituras a funciones y procedimientos de PostgreSQL; editar o anular exige un motivo y conserva la revisión previa.

`POST /v1/copilot/ask` recibe únicamente la pregunta del investigador; el servidor recupera el contexto autorizado, genera la respuesta y devuelve sus fuentes. Si RLS no recupera fuentes autorizadas, responde una negativa transparente sin llamar al LLM. `GET /v1/copilot/usage` devuelve el resumen de uso visible para el actor autenticado.

Redis implementa rate limiting distribuido: una clave con TTL por IP+correo para login y otra por investigador para el copiloto, con `INCR` atómico mediante Lua, respuesta `429` y `Retry-After`. El correo se normaliza y se convierte en un identificador HMAC para no almacenarlo en claro.

Para validar RLS y RAG con PostgreSQL real:

```bash
docker compose --profile test run --rm database-tests
```

El worker de embeddings se ejecuta como proceso separado y reclama trabajos con bloqueo `SKIP LOCKED`. Para arrancarlo con la clave configurada: `docker compose --profile worker up --build embedding-worker`; para procesar un único trabajo: `docker compose run --rm --no-deps embedding-worker python -m app.workers.embeddings --once`. Los trabajos fallidos se reintentan hasta cinco veces; los trabajos atascados en `processing` se recuperan después de quince minutos.

Para ejecutar las pruebas de la API en un entorno con las dependencias de desarrollo:

```bash
pip install -e ".[dev]"
pytest
ruff check --select E,F,I app tests
```

Cada push y pull request ejecuta automáticamente lint, pruebas y construcción del contenedor mediante GitHub Actions.

## Secretos

Completa `OPENAI_API_KEY`, `BIO_LLM_MODEL` y `BIO_EMBEDDING_MODEL` únicamente en `.env`. Ese archivo está ignorado por Git. Nunca subir claves, tokens, dumps de producción ni datos personales.

Consulta `AGENTS.md` antes de modificar la API, SQL, autenticación o integración LangChain. La arquitectura y las decisiones justificadas están en `ARCHITECTURE.md` y `DECISIONS.md`.
