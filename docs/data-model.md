# Modelo de datos y normalización

El corpus plano mezcla los atributos del investigador, especie, sitio y avistamiento en cada fila. Ya contiene valores atómicos, por lo que cumple 1FN; sin embargo, repite datos de las tres entidades maestras.

En 2FN se separan las entidades dependientes de su identidad propia. En 3FN se eliminan dependencias transitivas: los atributos del investigador dependen de `bio_researcher_id`, los de especie de `bio_species_id`, los del sitio de `bio_site_id`, y el avistamiento conserva solo sus referencias y datos del evento.

`bio_observation_reference`, correo y nombre científico permanecen como claves naturales alternativas con `UNIQUE`; los UUID son claves sustitutas porque los nombres, correos y taxonomía pueden corregirse sin romper referencias.

Las revisiones, tokens, conversaciones, mensajes y citas son entidades operativas añadidas fuera del corpus para cumplir trazabilidad científica, autenticación rotativa, mensajería y auditoría del RAG. Las membresías y recibos usan claves primarias compuestas porque su identidad es exactamente la pareja canal-investigador o mensaje-investigador.

El catálogo oficial amplía `bio_species` con `bio_description`, `bio_habitat`, `bio_diet` y `bio_conservation_status`, y `bio_sites` con `bio_description` y `bio_ecosystem`. Las imágenes y su licencia se normalizan en `bio_species_images` y `bio_site_images`, evitando grupos repetidos y dependencias transitivas.

El modelo canónico contiene 18 entidades. El estado de embeddings pertenece al registro que se vectoriza (`bio_sightings` o `bio_chat_messages`), por lo que no existe una tabla paralela `bio_embedding_jobs`; el worker reclama filas pendientes con `SKIP LOCKED`. El archivo fuente `modelo_entidad_relacion.mmd` se verifica contra las 18 tablas y 175 columnas reales del baseline.

