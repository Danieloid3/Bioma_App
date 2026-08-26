# Modelo de datos y normalización

El corpus plano mezcla los atributos del investigador, especie, sitio y avistamiento en cada fila. Ya contiene valores atómicos, por lo que cumple 1FN; sin embargo, repite datos de las tres entidades maestras.

En 2FN se separan las entidades dependientes de su identidad propia. En 3FN se eliminan dependencias transitivas: los atributos del investigador dependen de `bio_researcher_id`, los de especie de `bio_species_id`, los del sitio de `bio_site_id`, y el avistamiento conserva solo sus referencias y datos del evento.

`bio_observation_reference`, correo y nombre científico permanecen como claves naturales alternativas con `UNIQUE`; los UUID son claves sustitutas porque los nombres, correos y taxonomía pueden corregirse sin romper referencias.

Las revisiones, tokens y citas son entidades operativas añadidas fuera del corpus para cumplir trazabilidad científica, autenticación rotativa y auditoría del RAG.

