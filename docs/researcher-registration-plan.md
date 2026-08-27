# Plan de registro de investigadores

El registro público no está habilitado. La cuenta representa una identidad de investigación con un nivel de acreditación que decide PostgreSQL mediante RLS; por ello no puede autodeclararse ni activarse desde un formulario abierto.

## Flujo propuesto

1. Un solicitante envía nombre, correo institucional y la evidencia requerida mediante un flujo de solicitud separado, limitado por Redis y protegido contra enumeración de correos.
2. Un coordinador autorizado verifica la solicitud y crea/activa la cuenta mediante un caso de uso administrativo. El nivel inicial debe ser `1`; elevarlo a `2` o `3` requiere decisión explícita y auditoría.
3. El caso de uso normaliza el correo, valida la contraseña con la política definida y almacena únicamente su hash bcrypt. La escritura debe ir por una función SQL parametrizada de mínimo privilegio; `bio_app_user` no recibe `INSERT` directo sobre investigadores.
4. Antes de insertar, el backend selecciona `secrets.choice` de la biblioteca cerrada de claves de avatar (`spectacled_bear`, `andean_condor`, `golden_poison_frog`, `jaguar`, `hummingbird`, `cotton_top_tamarin`, `green_iguana`, `mountain_tapir`). La restricción `ck_bio_researchers_avatar_key` vuelve inválida cualquier clave fuera de esa lista.
5. La cuenta queda activa solo tras verificación institucional. Login emite JWT de acceso corto y refresh token opaco, hasheado y rotativo; el avatar es un dato de presentación, nunca una autorización.

## Entregables antes de habilitarlo

- Migración para solicitud/auditoría y una función SQL administrativa con permisos restringidos.
- Puerto/repositorio, caso de uso y router administrativo separados, más pruebas de duplicados, activación, nivel de acreditación y RLS.
- Mecanismo de verificación de correo institucional y política de restablecimiento de contraseña.
- Actualización de OpenAPI, contrato frontend y revisión de amenazas.
