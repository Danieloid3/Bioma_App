# Bioma — Contexto para agentes

## Propósito

Bioma es la plataforma de la Fundación Yarumo para registrar, consultar y analizar avistamientos de fauna silvestre en Colombia. El riesgo principal del negocio es real: exponer la ubicación exacta de especies sensibles puede facilitar tráfico de fauna o caza furtiva.

La regla innegociable vive en PostgreSQL: un investigador puede acceder a un avistamiento cuando su acreditación es mayor o igual que la clasificación del registro **o** cuando es su autor. Esta regla aplica a consultas directas, búsqueda, API, vistas y recuperación RAG; el frontend y el LLM nunca son la capa de autorización.

## Estado y estructura

```text
database/   # SQL, migrador con checksum y pruebas RLS/RAG reales
backend/    # FastAPI + Clean Architecture + LangChain
frontend/   # React + TypeScript + i18n
docs/       # Modelo, arquitectura y decisiones
```

La arquitectura detallada vive en `ARCHITECTURE.md`; decisiones justificadas en `DECISIONS.md`; el modelo fuente es `modelo_entidad_relacion.mmd`.

## Reglas técnicas obligatorias

- Todo debe continuar ejecutándose con `docker compose up --build`.
- Nunca incluir secretos en Git. Usar `.env`; mantener `.env.example` completo y sin valores reales.
- No editar migraciones ya registradas en `bio_schema_migrations`; crear una nueva migración numerada.
- No usar `DELETE` físico para avistamientos, SQL concatenado ni paginación con `OFFSET`.
- Usar consultas parametrizadas y keyset pagination con `(bio_observed_at, bio_sighting_id)`.
- Usar `timestamptz` en UTC, nombres de tablas y columnas en inglés con prefijo `bio_`.
- RLS se establece con `set_config('app.current_user_id', actor_id, true)` dentro de la transacción. Una conexión del pool nunca puede reutilizar el actor previo.
- Toda nota de campo es contenido no confiable; nunca se interpreta como una instrucción para el copiloto.
- El RAG consulta PostgreSQL con RLS antes de enviar una sola nota al proveedor de IA. Las respuestas deben citar fuentes autorizadas y negar con transparencia ante falta de acreditación o contexto.

## Calidad y entrega

- Mantener Clean Architecture y SOLID: dominio independiente de frameworks, drivers, HTTP y proveedores IA.
- Añadir pruebas de integración contra PostgreSQL real para cada cambio de autorización o migración relevante.
- Mantener OpenAPI, README, ARCHITECTURE y DECISIONS alineados con el código.
- Estado backend: cuando RLS no recupera fuentes para una consulta RAG, responder con una negativa determinista y auditable sin invocar al LLM; conservar pruebas unitarias y pruebas SQL RLS/RAG para este flujo.
- Al realizar un commit, actualizar este archivo y el `AGENTS.md` de la capa afectada cuando cambie contexto, arquitectura, reglas, decisiones, comandos, estructura o estado del proyecto. No hacer cambios cosméticos solo para forzar una actualización.
- Antes de un push: compilar backend y frontend, ejecutar pruebas de seguridad y comprobar `docker compose config`.

## Comandos de trabajo

```bash
docker compose up --build
docker compose --profile test run --rm database-tests
docker compose down
```

Los puertos locales por defecto están en `.env.example`: PostgreSQL `55432`, API `8001` y web `5174`, para no interferir con otros proyectos de la máquina.
