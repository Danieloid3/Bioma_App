# Bioma

Plataforma de monitoreo de fauna silvestre de la Fundación Yarumo. La seguridad de los avistamientos se aplica en PostgreSQL mediante Row Level Security: un investigador solo recibe registros con clasificación menor o igual a su acreditación, salvo los que él mismo registró.

## Arquitectura

- `database/`: migraciones SQL, corpus y pruebas de seguridad.
- `backend/`: FastAPI siguiendo Clean Architecture.
- `frontend/`: React + TypeScript organizado por aplicación, dominio, funcionalidades y servicios compartidos.
- `docs/`: decisiones y arquitectura.

El servicio `migrator` lleva un registro con checksum de cada migración. No se deben editar migraciones ya aplicadas: se agrega una nueva.

## Inicio local

1. Copia `.env.example` como `.env` y cambia todas las claves de ejemplo.
2. Inicia Docker Desktop.
3. Ejecuta `docker compose up --build`.
4. Abre `http://localhost:8001/docs` para OpenAPI y `http://localhost:5174` para la interfaz.

El usuario semilla usa la contraseña `Bioma2026!` únicamente para demostración local. No debe conservarse en entornos compartidos.

Para ejecutar las pruebas de RLS y RAG contra PostgreSQL real:

```sh
docker compose --profile test run --rm database-tests
```

## Reglas de seguridad

- El API usa `bio_app_user`, sin `BYPASSRLS` ni permisos directos de escritura en tablas de negocio.
- Cada operación protegida fija `app.current_user_id` con alcance local de transacción.
- Las funciones SQL registran, editan, anulan y auditan; no hay `DELETE` físico de avistamientos.
- El copiloto recibe solo el contexto retornado por `bio_fn_retrieve_copilot_context`, que pasa por RLS antes de llegar a LangChain.

## Estado actual

El monorepo contiene la base de datos, API FastAPI y cliente React. El backend incluye autenticación JWT con refresh rotativo, RLS por acreditación/autoría, CRUD de avistamientos con revisiones, búsqueda textual y RAG con pgvector/LangChain. Redis aplica rate limiting y el worker de embeddings se inicia junto con el resto de servicios para que el copiloto disponga de contexto después de la carga inicial.

El dashboard usa `GET /v1/dashboard` para mostrar métricas, clasificación y actividad autorizadas. También están disponibles `GET /v1/species`, `GET /v1/sites` y `GET /v1/researchers`; las especies entregan una fotografía icónica curada junto a texto alternativo, autoría y licencia. Las fotos de catálogo no son evidencias de campo.

Cada fila de avistamiento abre `GET /v1/sightings/{id}`. La ficha se autoriza en PostgreSQL y solo entonces muestra la nota y las coordenadas exactas; un registro no visible responde igual que uno inexistente.

Las pruebas unitarias y las aserciones RLS/RAG contra PostgreSQL real están automatizadas. Las evidencias audiovisuales y el transporte de tiempo real hacia la interfaz quedan pendientes.
