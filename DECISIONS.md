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

## Dashboard filtrado y revisiones protegidas

Los conteos y la actividad no se calculan con privilegios de propietario ni se entregan como datos globales: sus funciones parten de `bio_sightings` dentro de la transacción del actor. Como una revisión conserva notas y coordenadas previas, también tiene RLS y solo se puede leer al poder ver su avistamiento actual.

## Imágenes icónicas como catálogo curado

Las fotos representativas viven en `bio_species_images`, no en `bio_species` ni en los avistamientos. La separación permite mantener licencia, atribución, idioma y reemplazos sin contaminar la taxonomía ni confundir una imagen institucional con evidencia de campo. Solo se expone una imagen destacada activa por especie, garantizada con un índice parcial.

## Ficha individual con denegación uniforme

La ficha incluye coordenadas exactas, por lo que no se deriva del listado ni se compone en el cliente. Una función invocada bajo el actor deja que RLS autorice el registro completo; si no hay fila, la API retorna 404 igual que para un UUID inexistente. Esto evita filtrar la existencia de un avistamiento confidencial.

## Pendientes aceptados

Las evidencias audiovisuales y la entrega en tiempo real al frontend quedan fuera de este cierre de backend. PostgreSQL ya publica eventos `pg_notify`; el transporte WebSocket/SSE se decidirá durante la integración frontend.
