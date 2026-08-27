# Scripts SQL

El baseline canónico está en `001_core_schema.sql`, `002_functions_and_triggers.sql` y `003_seed_data.sql`. Las migraciones `004`–`011` son reparaciones hacia adelante y deben conservarse en orden.

| Archivo | Responsabilidad |
|---|---|
| `001_core_schema.sql` | Extensiones, roles, tablas, índices y restricciones DDL |
| `002_functions_and_triggers.sql` | Funciones DML, triggers, vistas, procedimientos y políticas RLS |
| `003_seed_data.sql` | Carga del corpus y datos iniciales |
| `004`–`009` | Reparaciones de copiloto, chat, auditoría, refresh y recibos |
| `010_group_members_and_prompt_versions.sql` | Rol admin, integrantes de grupos y prompts versionados |
| `011_fix_prompt_function_contracts.sql` | Corrección de contratos SQL de prompts |

Los scripts de `tests/` se ejecutan contra PostgreSQL real.
