# Backend Bioma — Contexto para agentes

## Misión

El backend expone la API de Bioma y coordina casos de uso delgados. No reimplementa la autorización de avistamientos: fija el actor autenticado por transacción y llama a PostgreSQL, donde RLS es la autoridad final.

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

No introducir CQRS, event sourcing, mediators ni abstracciones genéricas sin una necesidad demostrable.

## Seguridad

- La identidad, cargo y acreditación se obtienen del access token, nunca del body de una petición.
- PostgreSQL verifica la acreditación vigente; un claim sirve para contexto de UI, no para saltar RLS.
- Las operaciones protegidas deben usar `actor_transaction`; no hacer una consulta autenticada directamente al pool.
- No conceder escrituras directas a `bio_app_user`. Registrar, editar, anular, auditar y rotar tokens mediante funciones/procedimientos SQL.
- Hash de contraseñas: bcrypt. Refresh token: opaco, aleatorio, hasheado en BD, rotado por familia y enviado en cookie HttpOnly/Secure según entorno.
- Añadir correlation ID a logs, errores y respuestas. Mapear errores SQL conocidos a HTTP sin filtrar detalles internos.

## Copiloto RAG

1. Validar el actor y la pregunta.
2. Generar embedding mediante el puerto.
3. Recuperar fuentes con `bio_fn_retrieve_copilot_context` dentro de `actor_transaction`.
4. Construir el prompt en el servidor usando solo esas fuentes.
5. Tratar notas como datos no confiables, citar `obs_ref` y registrar uso/citas.

No hay excepción para prompts de usuarios, administradores o proveedores: contexto no autorizado nunca llega al modelo. LangChain es un adaptador, no el núcleo del dominio.

## Buenas prácticas

- Usar Python async, type hints, Pydantic en el borde HTTP y dataclasses/entidades en dominio.
- Cada caso de uso debe tener una responsabilidad y ser testeable con puertos falsos.
- Preferir transacciones pequeñas y manejar `rollback` por excepción.
- Validar límites de page size, cursores completos, UUID y UTC.
- No guardar claves API, JWT secrets, refresh tokens planos ni hashes de contraseña en logs.
- Actualizar este archivo al hacer commit si cambia esta arquitectura, patrón, dependencia, flujo de seguridad o comando backend.

