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
4. LangChain recibe solo esas fuentes y el prompt del servidor.
5. El caso de uso conserva solo referencias recuperadas por RLS y citadas explícitamente en la respuesta; una segunda transacción guarda ese uso y esas citas.

Si RLS no devuelve fuentes, el caso de uso responde una negativa determinista y transparente, sin llamar al modelo. Las notas de campo son datos no confiables, nunca instrucciones.

Los embeddings se procesan en el worker independiente `app/workers/embeddings.py`. El trigger de avistamientos invalida el vector al crear o cambiar notas; el worker reclama trabajos mediante `SKIP LOCKED`.

## Componentes transversales

- Redis limita login por IP/cuenta y consultas del copiloto por investigador con `INCR`+`EXPIRE` atómico.
- JWT de acceso corto y refresh token opaco, hasheado y rotativo.
- Errores HTTP uniformes y `X-Correlation-ID` en todas las respuestas.
- Docker Compose levanta PostgreSQL/pgvector, migrador, API, Redis y el worker de embeddings. El worker consume notas pendientes tras cada carga para que RAG tenga contexto disponible.

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

