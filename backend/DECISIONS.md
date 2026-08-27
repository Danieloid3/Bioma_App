# Decisiones de arquitectura

## PostgreSQL es la capa de autorización

Se eligió RLS con `app.current_user_id` en transacciones locales. Así, una consulta directa, la API y el RAG obedecen la misma regla de acreditación o autoría. El frontend y el LLM no deciden permisos.

## Identificadores UUID y anulación lógica

Las entidades usan UUID subrogados para no exponer claves de negocio mutables. Los avistamientos no se eliminan: se anulan y cada edición/anulación conserva una revisión para trazabilidad científica.

## Clean Architecture con puertos y adaptadores

Los puertos `EmbeddingProvider` y `CopilotProvider` aíslan LangChain/OpenAI. `Repository` encapsula SQL parametrizado; `Unit of Work` establece actor y transacción; `Factory` construye el adaptador IA. No se introdujo CQRS ni event sourcing porque no son necesarios para este alcance.

## RAG con transacciones separadas

La recuperación de contexto y la auditoría usan transacciones independientes. La red del proveedor IA nunca mantiene una conexión PostgreSQL abierta. Las citas se persisten junto con el uso del copiloto.

## Denegación sin contexto autorizado

Cuando RLS no devuelve fuentes, Bioma responde de forma determinista que no dispone de contexto autorizado suficiente. Evita que el modelo invente, aproxime ubicaciones o revele indirectamente datos sensibles.

## Redis para rate limiting distribuido

Redis permite aplicar el límite entre réplicas. Las cuentas de login se representan con HMAC, no con el correo en claro; las operaciones atómicas devuelven `429` y `Retry-After`.

## Pendientes aceptados

Las evidencias audiovisuales y la entrega en tiempo real al frontend quedan fuera de este cierre de backend. PostgreSQL ya publica eventos `pg_notify`; el transporte WebSocket/SSE se decidirá durante la integración frontend.
