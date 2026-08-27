# Decisiones de arquitectura

## PostgreSQL es la capa de autorización

Se eligió RLS con `app.current_user_id` en transacciones locales. Así, una consulta directa, la API y el RAG obedecen la misma regla de acreditación o autoría. El frontend y el LLM no deciden permisos.

## Identificadores UUID y anulación lógica

Las entidades usan UUID subrogados para no exponer claves de negocio mutables. Los avistamientos no se eliminan: se anulan y cada edición/anulación conserva una revisión para trazabilidad científica.

## Clean Architecture con puertos y adaptadores

Los puertos `EmbeddingProvider` y `CopilotProvider` aíslan LangChain/OpenAI. `Repository` encapsula SQL parametrizado; `Unit of Work` establece actor y transacción; `Factory` construye el adaptador IA. No se introdujo CQRS ni event sourcing porque no son necesarios para este alcance.

## RAG con transacciones separadas

La recuperación de contexto y la auditoría usan transacciones independientes. La red del proveedor IA nunca mantiene una conexión PostgreSQL abierta. El caso de uso solo expone y persiste las fuentes recuperadas por RLS que el texto cita exactamente como `[obs-ref]`; si el modelo omite citas válidas, se sustituye por una negativa verificable y se auditan cero citas.

## Denegación sin contexto autorizado

Cuando RLS no devuelve fuentes, Bioma responde de forma determinista que no dispone de contexto autorizado suficiente. Evita que el modelo invente, aproxime ubicaciones o revele indirectamente datos sensibles.

## Redis para rate limiting distribuido

Redis permite aplicar el límite entre réplicas. Las cuentas de login se representan con HMAC, no con el correo en claro; las operaciones atómicas devuelven `429` y `Retry-After`.

## Dashboard filtrado y revisiones protegidas

Los conteos y la actividad no se calculan con privilegios de propietario ni se entregan como datos globales: sus funciones parten de `bio_sightings` dentro de la transacción del actor. Como una revisión conserva notas y coordenadas previas, también tiene RLS y solo se puede leer al poder ver su avistamiento actual.

## Imágenes icónicas como catálogo curado

Las fotos representativas viven en `bio_species_images` y `bio_site_images`, no en las entidades científicas principales ni en los avistamientos. La separación permite mantener licencia, atribución, idioma y reemplazos sin contaminar la taxonomía ni confundir una imagen institucional con evidencia de campo. Solo se expone una imagen destacada activa por especie o sitio, garantizada con un índice parcial. Para los sitios se usan paisajes públicos representativos: nunca rutas, coordenadas ni evidencia de un registro.

Las imágenes de sitios deben identificar el área concreta y conservar URL de origen, autor y términos de uso. No se aceptan fotografías genéricas de banco como sustituto; si no existe una imagen verificable y atribuible, se muestra el estado sin imagen hasta que curaduría aporte una.

## Avatares de investigador con biblioteca cerrada

Un avatar es una clave persistida y limitada por una restricción SQL, no una imagen o URL libre. Esto mantiene la presentación consistente y evita incorporar contenido no curado. El alta pública sigue deshabilitada: una futura creación de cuenta deberá usar `secrets.choice` sobre la misma biblioteca después de verificación institucional, con acreditación inicial mínima y auditoría.

## Ficha individual con denegación uniforme

La ficha incluye coordenadas exactas, por lo que no se deriva del listado ni se compone en el cliente. Una función invocada bajo el actor deja que RLS autorice el registro completo; si no hay fila, la API retorna 404 igual que para un UUID inexistente. Esto evita filtrar la existencia de un avistamiento confidencial.

## Enriquecimiento del catálogo científico e inyección en RAG

Se amplió `bio_species` y `bio_sites` con descripción científica, hábitat, dieta, bioma y estado de conservación (Migración `027`). Este catálogo se inyecta formalmente en el contexto del copiloto a través de `bio_fn_get_knowledge_catalog()`, permitiendo que el LLM responda con rigor biológico sobre las especies y áreas protegidas de la Fundación Yarumo mientras sigue citando avistamientos reales `[obs-XXXX]` recuperados bajo RLS.

## Fichas científicas modales con degradado panorámico

El frontend presenta las especies y sitios mediante modales interactivos con imágenes de 21rem y degradado orgánico difuminado hacia el fondo marfil (`var(--surface)`). Los títulos y categorías UICN reposan sobre el degradado, permitiendo una lectura fluida de la ficha taxonómica y ecológica sin romper el diseño sobrio y científico de Bioma.

## Pipeline CI/CD en GitHub Actions

Se automatizó la verificación continua en `.github/workflows/ci.yml`. Toda integración comprueba la compilación TypeScript de frontend, la validez del Compose y ejecuta las pruebas de aserción de seguridad PostgreSQL RLS/RAG con contenedores reales, garantizando que ninguna regresión de seguridad o de tipos llegue a producción.

