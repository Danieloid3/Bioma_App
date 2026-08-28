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

El baseline amplía `bio_species` y `bio_sites` con descripción científica, hábitat, dieta, bioma y estado de conservación. Las migraciones `015` y `016` añaden embeddings y citas propias del catálogo: la recuperación híbrida prioriza coincidencias semánticas y mantiene el catálogo oficial como respaldo. Especies y sitios se citan como `[species-UUID]` y `[site-UUID]`; los avistamientos continúan citándose como `[obs-XXXX]` y son los únicos sujetos a la regla de acreditación/autoría RLS.

## Fichas científicas modales con degradado panorámico

El frontend presenta las especies y sitios mediante modales interactivos con imágenes de 21rem y degradado orgánico difuminado hacia el fondo marfil (`var(--surface)`). Los títulos y categorías UICN reposan sobre el degradado, permitiendo una lectura fluida de la ficha taxonómica y ecológica sin romper el diseño sobrio y científico de Bioma.

## Mensajería interna: módulo PostgreSQL, no microservicio MongoDB

La mensajería interna vive junto a Bioma en PostgreSQL y FastAPI. Las membresías de canal, historial, búsqueda semántica y recuperación RAG se gobiernan con el mismo actor transaccional y RLS que protege los avistamientos. Redis queda reservado para señales efímeras de tiempo real; no es fuente de verdad. Esta decisión evita duplicar identidad/permisos en una base no relacional y permite probar que un no miembro no puede listar, buscar ni recuperar mensajes de un canal privado.

## Tiempo real de chat con SSE autenticado y Redis Pub/Sub

Se eligió Server-Sent Events sobre WebSocket porque la mensajería conserva comandos REST y requiere solo notificación servidor-cliente. Redis Pub/Sub permite que una escritura confirmada en una réplica despierte a clientes conectados a otra sin convertir Redis en almacenamiento de mensajes. El navegador abre el stream con `fetch` para adjuntar el bearer que permanece solo en memoria; no se admite token en URL. Cada señal se trata como una invalidación sin contenido y se filtra justo antes de emitirse mediante una nueva transacción con `app.current_user_id`, por lo que una membresía revocada no conserva una suscripción efectiva. El cliente recarga el recurso mediante REST+RLS y puede perder una señal sin perder consistencia al reconectar.

## Pipeline CI/CD en GitHub Actions

Se automatizó la verificación continua en `.github/workflows/ci.yml`. Toda integración comprueba la compilación TypeScript de frontend, la validez del Compose y ejecuta las pruebas de aserción de seguridad PostgreSQL RLS/RAG con contenedores reales, garantizando que ninguna regresión de seguridad o de tipos llegue a producción.

## Eliminación lógica tombstone y versionado inmutable en chat

Para cumplir la regla innegociable de no usar `DELETE` físico y mantener auditoría forense, los mensajes de chat eliminados se marcan con `bio_is_deleted = true` y `bio_deleted_at = clock_timestamp()`. El trigger inmutable `trg_bio_chat_messages_10_archive` archiva el snapshot del mensaje en `bio_chat_message_versions` antes de la mutación. En consultas (`bio_fn_chat_history`), los mensajes eliminados devuelven `message_text = 'Este mensaje fue eliminado'` y `is_deleted = true`, presentándose en UI con icono de prohibido y deshabilitando edición, preservando la inmutabilidad histórica.

## Procedimientos almacenados para gestión de investigadores

La administración y consulta de investigadores activos se estandarizó mediante procedimientos almacenados en PostgreSQL. `bio_sp_get_active_researchers` devuelve un cursor tipado (`REFCURSOR`) con el directorio de usuarios activos. `bio_sp_manage_researcher` encapsula la actualización y baja lógica (`bio_is_active = false`), validando que el actor ejecutor posea acreditación de nivel 3 y rechazando transaccionalmente cualquier intento de auto-desactivación o modificación no autorizada.

## Visibilidad compartida en copiloto RAG dentro de canales colaborativos

Cuando el copiloto es consultado en un canal compartido entre dos o más investigadores, la recuperación de contexto RAG no evalúa únicamente al emisor ni al receptor de forma aislada: ejecuta `bio_fn_chat_shared_sightings()` para calcular la intersección estricta de permisos entre todos los miembros activos del canal. El LLM solo recibe avistamientos que todos los participantes tienen derecho de ver, impidiendo cualquier fuga de información confidencial en espacios de trabajo colaborativos.

## Identidad visual y branding desacoplado

El isotipo del ave y la tipografía de la marca se desacoplaron en assets vectoriales independientes (`bioma-pajaro.svg` y `bioma-letras.svg`). Esto permite que el favicon del navegador exponga únicamente el isotipo cuadrado de alta definición, mientras que la barra lateral y la pantalla de inicio de sesión componen el logotipo completo con control milimétrico sobre escala, grosor tipográfico, espaciado y contraste contra fondos claros y oscuros.

### [2026-08-27] Enriquecimiento del corpus de prueba (Semilla)

**Contexto:** Para probar rigurosamente las políticas RLS y evaluar la respuesta del copiloto RAG bajo condiciones realistas de autorización, el corpus de prueba resultaba insuficiente con solo 3 investigadores. Además, el frontend necesitaba representar una mayor variedad de cargos, acreditaciones y avatares para validar las vistas de directorio y perfiles.
**Decisión:** `003_seed_data.sql` concentra los 11 investigadores representativos, con niveles de acreditación y roles variados, y sus avistamientos de demostración.
**Consecuencias:**
- Las pruebas automatizadas ls_assertions.sql y ag_security_assertions.sql contarán con más escenarios, robusteciendo la verificación.
- La interfaz visual de directorio presentará datos mucho más cercanos a producción, permitiendo evaluar problemas de renderizado o maquetación con los diferentes avatares (oso de anteojos, cndor, jaguar, etc.).
- Aumenta el volumen de embeddings que deberá procesar el worker local (o mock) tras levantar el ambiente inicial.

## Reparación hacia adelante del baseline del copiloto

Las migraciones ya registradas no se reescriben. `005_repair_copilot_persistence.sql` corrige las funciones consolidadas mediante una migración nueva: `bio_fn_log_copilot_usage` vuelve a ser el único punto autorizado de auditoría, revalida cada cita con acreditación o autoría, y `bio_fn_record_copilot_turn` enlaza el mensaje de asistente a esa misma fila. También se revoca DML directo sobre hilos, se protege `bio_copilot_citations` con RLS y se restaura el contrato de `bio_fn_copilot_usage_summary()` consumido por el frontend.

La misma política de reparación hacia adelante se aplica al chat y la sesión. `006_repair_chat_history_and_citations.sql` adapta `bio_fn_chat_history` y `bio_fn_record_chat_copilot_message` a las columnas canónicas de fuentes, impidiendo que una cita sobrepase la visibilidad compartida del canal. `007_repair_refresh_token_rotation.sql` restaura todos los atributos del actor y corrige la filiación de la cadena rotativa sin almacenar el token opaco en claro. `008_fix_chat_message_counter.sql` reemplaza el `JOIN` de membresías por `EXISTS`, evitando contar cada mensaje una vez por integrante. `009_chat_unread_receipts.sql` separa el total de mensajes del contador de no leídos y marca los recibos al abrir un canal.

## Prompts inmutables y administrables

Los prompts de campo, chat y saludo viven en `bio_system_prompt_versions`. Crear una versión calcula su SHA-256, conserva el texto histórico y activa esa versión; restaurar una anterior solo cambia cuál es la activa. La autorización se comprueba en PostgreSQL contra `bio_is_admin`, no en la interfaz. Cada uso audita el identificador de versión activo.
