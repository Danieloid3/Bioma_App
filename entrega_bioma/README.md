# Entrega técnica — Bioma

Esta carpeta reúne los artefactos de la solución para revisión y evaluación. Se excluyeron secretos, archivos `.env` reales, dependencias instaladas y artefactos temporales.

## Contenido

- `database/migrations/`: DDL, DML de seed, funciones, triggers, vistas, procedimientos y políticas RLS.
- `database/tests/`: pruebas SQL de RLS, RAG, chat, no leídos, refresh tokens y prompts.
- `mer/`: MER fuente en Mermaid y representaciones PNG/SVG.
- `seed.json`: corpus semilla original utilizado por el backend.
- `api/openapi.json`: contrato OpenAPI exportado desde `/openapi.json`; Swagger UI está disponible en `/docs`.
- `docs/`: README, arquitectura y decisiones del proyecto.
- `backend/` y `frontend/`: archivos fuente utilizados para implementar la solución.
- `compose.yaml` y `.env.example`: ejecución reproducible sin secretos.
- `evidencias/`: resultados resumidos de las validaciones ejecutadas.
- `backend/app/infrastructure/chat_events.py` y `backend/tests/test_api_chat_realtime_http.py`: tiempo real SSE autenticado, Redis Pub/Sub y prueba de aislamiento entre miembros y no miembros.

## Ejecución

Desde la raíz: `docker compose up --build`. Para seguridad: `docker compose --profile test run --rm database-tests`.
