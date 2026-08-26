# Decisiones de arquitectura

## ADR-001 — FastAPI, React y PostgreSQL

Se usa Python/FastAPI para el API, React/TypeScript para el cliente y PostgreSQL 16 con pgvector. FastAPI ofrece inyección de dependencias y ciclo de vida async para administrar el pool; React mantiene separada la interfaz de la lógica de autorización.

## ADR-002 — Clean Architecture y SOLID

Los casos de uso dependen de puertos (`Protocol`) del dominio. PostgreSQL, JWT y LangChain son adaptadores intercambiables. Esto aplica inversión de dependencias; cada repositorio, proveedor IA y router mantiene una sola responsabilidad.

## ADR-003 — Patrones elegidos

- **Repository:** encapsula llamadas SQL parametrizadas.
- **Unit of Work:** delimita la transacción y el actor RLS por petición.
- **Adapter / Strategy:** cada proveedor de chat y embeddings implementa los mismos puertos.
- **Factory:** selecciona el adaptador de IA desde configuración sin contaminar casos de uso.

No se añade CQRS, event sourcing o un bus de comandos: elevarían la complejidad sin resolver un requisito actual. El historial científico se resuelve con una tabla de revisiones y triggers de PostgreSQL.

## ADR-004 — Autorización en PostgreSQL

El JWT identifica al investigador, pero PostgreSQL lee la acreditación vigente desde `bio_researchers`. Así, reducir una acreditación o desactivar la cuenta toma efecto en la siguiente transacción aunque el token aún no expire.

## ADR-005 — RAG seguro

El contexto se filtra en SQL con RLS antes de invocar LangChain. Las notas se delimitan como datos no confiables en el system prompt. Las citas se almacenan en `bio_copilot_citations` para demostrar qué fuentes autorizadas sustentaron cada respuesta.

## ADR-006 — Tiempo real

Un trigger emite `NOTIFY` con solo el UUID del avistamiento. Un adaptador SSE/WebSocket del backend consumirá ese evento; el cliente debe volver a pedir datos a la API, donde RLS decide qué puede ver.

