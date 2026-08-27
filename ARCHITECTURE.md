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
5. Una segunda transacción guarda uso y citas.

Si RLS no devuelve fuentes, el caso de uso responde una negativa determinista y transparente, sin llamar al modelo. Las notas de campo son datos no confiables, nunca instrucciones.

Los embeddings se procesan en el worker independiente `app/workers/embeddings.py`. El trigger de avistamientos invalida el vector al crear o cambiar notas; el worker reclama trabajos mediante `SKIP LOCKED`.

## Componentes transversales

- Redis limita login por IP/cuenta y consultas del copiloto por investigador con `INCR`+`EXPIRE` atómico.
- JWT de acceso corto y refresh token opaco, hasheado y rotativo.
- Errores HTTP uniformes y `X-Correlation-ID` en todas las respuestas.
- Docker Compose levanta PostgreSQL/pgvector, migrador, API, Redis y el worker de embeddings. El worker consume notas pendientes tras cada carga para que RAG tenga contexto disponible.

## Dashboard y catálogo

El dashboard llama a funciones `SECURITY INVOKER` que agregan únicamente filas de `bio_sightings` visibles bajo RLS. La actividad une creación y revisiones, y `bio_sighting_revisions` posee su propia política RLS antes de poder leerse. Las imágenes de especie y sitio son catálogos curados en `bio_species_images` y `bio_site_images`: conservan fuente, licencia y textos alternativos; no sustituyen ni comparten el modelo de evidencias de avistamiento.

La ficha de un avistamiento se obtiene con `bio_fn_get_sighting_detail`, también `SECURITY INVOKER`. El API devuelve 404 para una fila inexistente o no visible y evita que el cliente pueda distinguir ambos escenarios.

## Pendiente de integración

El backend emite `pg_notify` ante cambios de avistamientos, pero aún no expone WebSocket ni SSE. La entrega de tiempo real queda pendiente junto con el frontend.
