# Arquitectura de Bioma

## Flujo de dependencias

```text
presentation (FastAPI / React)
            ↓
application (casos de uso)
            ↓
domain (entidades, reglas y puertos)
            ↑
infrastructure (PostgreSQL, JWT, LangChain, HTTP)
```

El dominio no importa FastAPI, asyncpg, LangChain ni React. La infraestructura implementa puertos definidos por el dominio y se conecta en el borde de la aplicación.

## Backend

```text
backend/app/
├── domain/                 # Entidades y Protocols (puertos)
├── application/use_cases/  # Orquestación del negocio, sin SQL ni HTTP
├── infrastructure/         # Adaptadores PostgreSQL, JWT y LangChain
└── presentation/api/       # Routers, esquemas HTTP y dependencias FastAPI
```

`Database.actor_transaction()` es el Unit of Work. Establece el actor con `set_config('app.current_user_id', ..., true)` dentro de una transacción; las políticas RLS aplican incluso cuando una función SQL hace el trabajo de escritura.

## Base de datos

`bio_owner` es dueño no iniciable de los objetos. `bio_app_user` es el usuario de runtime y no posee `BYPASSRLS`. El migrador usa el administrador de PostgreSQL, nunca el usuario de runtime.

Las escrituras de avistamientos pasan por funciones o procedimientos `SECURITY DEFINER` de `bio_owner`. Como la tabla usa `FORCE ROW LEVEL SECURITY` y las políticas también aplican a `bio_owner`, esas funciones siguen obligadas a respetar el actor de la transacción.

## Copiloto

El caso de uso obtiene un embedding de la pregunta, invoca `bio_fn_retrieve_copilot_context` y solo después pasa las notas resultantes al proveedor. La RLS queda antes del LLM, no como una instrucción del prompt.

`EmbeddingProvider` y `CopilotProvider` son puertos. `LangChainOpenAIGateway` es el adaptador inicial; `build_ai_gateway()` es la fábrica que elegirá otro adaptador cuando se añada un proveedor.

## Frontend

```text
frontend/src/
├── app/       # composición y proveedores globales
├── domain/    # contratos puros del negocio
├── features/  # casos de interacción: avistamientos, copiloto, perfil
└── shared/    # HTTP, i18n y piezas reutilizables
```

El frontend nunca decide visibilidad: representa exclusivamente lo que devuelve la API.

