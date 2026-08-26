# 🌿 Proyecto Integrador Full-Stack — Plataforma "Bioma"
## Base de datos, seguridad por nivel de acceso y copiloto con IA (RAG)

---

> **Modalidad:** Individual. Proyecto integrador de fin de bloque.
> **Alcance:** Full-stack (base de datos + backend + frontend + copiloto de IA).
> **Énfasis:** La lógica crítica vive en PostgreSQL. La IA respeta la sensibilidad del dato.

---

## 🎯 Contexto de negocio

La **Fundación Yarumo** monitorea fauna silvestre en Colombia. Sus investigadores registran **avistamientos** de especies con sus **notas de campo** y **coordenadas exactas**. La plataforma **Bioma** debe administrar investigadores, especies, sitios, avistamientos, búsqueda y un **copiloto de IA** que ayude a consultar el historial de campo.

El problema central es de **seguridad de la información**: la **ubicación exacta de especies amenazadas** es un dato peligroso. Si se filtra, facilita el **tráfico de fauna y la caza furtiva**. Por eso el acceso a cada avistamiento **no** depende de pertenecer a ningún grupo, sino de **dos condiciones**:

> **Un investigador puede ver un avistamiento si su _nivel de acreditación_ es mayor o igual a la _clasificación_ del avistamiento, O si él mismo es el autor del registro.**

Los niveles son ordinales: **1 = público**, **2 = restringido**, **3 = confidencial**. Una técnica de campo (nivel 1) ve los avistamientos públicos y los suyos propios; una coordinadora científica (nivel 3) ve todo. El requisito **no negociable** es que **nadie** —ni por consulta directa, ni por búsqueda, ni a través del copiloto— acceda a un avistamiento por encima de su acreditación que no sea suyo.

Los avistamientos deben poder **editarse o anularse conservando el registro original** (en ciencia no se borra evidencia).

> Tienes un corpus crudo y **desnormalizado** en `seed.json`. Es tu punto de partida: de ahí sacas el modelo.

---

## 🧱 Entorno

Corre en **tu propio entorno Docker**, porque configurarás seguridad a nivel de fila con un rol de aplicación propio y una extensión vectorial.

- PostgreSQL **15 o superior** con la extensión **`pgvector`**.
- `docker compose up` debe levantar **base de datos + backend + frontend**.

---

## 📋 Requerimientos técnicos

### 1 · Análisis, normalización y modelo de datos

- A partir de `seed.json`, identifica **entidades, relaciones y reglas de negocio implícitas**. Documenta la normalización hasta **1FN, 2FN y 3FN** (muestra el antes y el después de cada forma). Fíjate en las redundancias: un mismo investigador, una misma especie y un mismo sitio aparecen repetidos en muchas filas.
- Construye un **Modelo Entidad-Relación** con entidades, atributos, **PK**, **FK**, **cardinalidades** y **justificación del tipo de clave** (natural vs. subrogada).

### 2 · Base de datos en PostgreSQL

- Base de datos llamada **`bioma_nombre_apellido`** (usa tus datos).
- **Todos** los nombres de tablas y columnas en **inglés** y con prefijo **`bio_`**.
- DDL completo con: **PK**, **FK con `ON DELETE` explícito y justificado**, **UNIQUE**, al menos **un índice único parcial** (pista: un investigador no debería registrar la misma especie en el mismo sitio el mismo día dos veces mientras el registro esté activo), **NOT NULL**, **CHECK** (p. ej. la acreditación y la clasificación solo aceptan valores válidos; la latitud/longitud en rango), y todas las fechas como **`timestamptz` en UTC**.

### 3 · Lógica de negocio en la base de datos

- **Funciones transaccionales**: registrar un avistamiento (validando datos y permisos) debe ser **todo o nada**, sin rastro parcial ante un error.
- **Row Level Security (RLS)** activo sobre **avistamientos**, usando un **rol de aplicación sin `BYPASSRLS`** y un **actor fijado por transacción** mediante `app.current_user_id`. La política implementa la regla del contexto: **`clasificación <= acreditación_del_actor` OR `autor = actor`**.
- Una **vista** de "avistamientos visibles para el actor" que encapsule esa regla.
- Mínimo **dos procedimientos almacenados**: uno de **consulta de investigadores** y otro para la **edición y anulación** de avistamientos (anulación **lógica**, nunca física).

### 4 · Búsqueda, recuperación de contexto y seguridad

- Define **cómo el copiloto recupera** los avistamientos: **solo** los que el actor puede ver según su acreditación (o los propios). **Nunca** avistamientos por encima de su nivel que no sean suyos.
- Usa una **base vectorial** (`pgvector`) para almacenar las **notas de campo** de los avistamientos y un **motor de embeddings** para recuperarlas junto con el LLM.
- Incorpora **al menos un trigger** que mantenga el **vector de búsqueda consistente** cuando un avistamiento se crea o edita.
- **Prohibido:** el **borrado físico** de avistamientos, el **SQL por concatenación** (usa consultas parametrizadas) y la **paginación con `OFFSET`** (usa keyset).

### 5 · Backend y API REST

- **Clean Architecture** con capas explícitas; las dependencias apuntan al **dominio**, que **no** depende del framework web ni del driver de base de datos.
- **Casos de uso delgados**: validan entrada, invocan funciones de base de datos y mapean resultados.
- **SOLID** demostrable. Evalúa si hace falta un **patrón de diseño**; si lo aplicas, **justifícalo**.
- API REST con **códigos de estado correctos**, **manejo uniforme de errores**, **identificador de correlación** y **paginación por keyset**.

### 6 · Autenticación y autorización

- Inicio de sesión verificando contraseñas contra un **hash seguro** (bcrypt/argon2).
- **JWT** con **token de acceso de vida corta** y **refresh token con rotación**, almacenado de forma segura.
- Rutas protegidas; el identificador del investigador y su **nivel de acreditación** se toman **del token**, nunca del cuerpo de la petición.
- Propaga el **actor autenticado** a las funciones de base de datos y a las políticas RLS.

### 7 · Frontend

- Interfaz con **mínimo tres zonas**: **mapa/lista de avistamientos**, **panel del copiloto** y **perfil del investigador**.
- Registro de avistamientos con estados **pendiente, enviado y fallido**.
- Carga del historial **diferida** (lazy) preservando la posición del scroll, con estados de **carga, vacío y error**.
- **Responsiva** en móvil y escritorio, disponible en **español e inglés** (i18n), sin cadenas incrustadas en los componentes.
- **Detalle de seguridad en la UI:** a un investigador nunca se le muestran coordenadas exactas de avistamientos por encima de su acreditación; para los que no puede ver, o no aparecen, o se muestran con la ubicación **ofuscada** (según definas en tus decisiones).

### 8 · Copiloto de IA (RAG)

- Copiloto con enfoque **RAG**, recuperando contexto **exclusivamente** de avistamientos que el actor puede ver.
- Cada respuesta incluye **citas a los avistamientos fuente** y responde con **honestidad** cuando no hay contexto suficiente.
- El copiloto **conoce al investigador autenticado** (nombre y cargo), construyendo ese contexto **en el servidor desde el token**.
- El proveedor de IA debe ser **intercambiable** mediante una interfaz común (p. ej. el **OpenAI SDK**).
- **System prompt versionado**; las notas de campo se tratan como **dato no confiable**; deben existir **negativas explícitas** por falta de acreditación, fuera de alcance o contexto insuficiente. En particular, si preguntan por la ubicación de una especie que el actor no puede ver, el copiloto **niega con transparencia**, no inventa ni aproxima.

### 9 · QA y evidencias

- Mínimo **dos pruebas automatizadas contra PostgreSQL real**:
  1. Que un investigador de **acreditación baja** **no** obtiene avistamientos **confidenciales ajenos** (ni por consulta ni por el copiloto).
  2. Que un investigador **sí** ve sus **propios** avistamientos aunque estén por encima de su acreditación (la regla de autoría funciona).
- Evidencias en **capturas o video de máx. 5 minutos** mostrando: inicio de sesión, registro de avistamiento, búsqueda, respuesta del copiloto **con citas**, y **negativa correcta** ante una consulta sin acreditación. Enfócalo como un **pitch** de producto.

### 10 · Despliegue

- `docker compose up` levanta **db + backend + frontend**.
- Un **comando documentado** ejecuta migraciones y **carga el corpus completo**.
- `.env.example` **sin secretos reales**; el proyecto debe levantarse en una **máquina limpia** siguiendo solo el README.

### 11 · Consultas y funciones SQL requeridas

1. **Historial** de avistamientos de una **especie** (o de un **sitio**) con **paginación por keyset**.
2. **Búsqueda** en las notas de campo con **resaltado** del término encontrado.
3. **Recuperación de contexto** para el copiloto, con la **regla de acreditación aplicada en SQL**.
4. **Consumo acumulado** del copiloto **por investigador**.

---

## 📦 Entregables

- Scripts **DDL**, de **carga**, **DML**, consultas SQL, **funciones, triggers, vistas, procedimientos y políticas RLS**.
- **Modelo Entidad-Relación** en PDF o imagen, el **`seed.json`** y los archivos usados para representar la solución.
- Documentación de API mediante **Swagger/OpenAPI** publicado o **colección Postman** exportada.
- **`README.md`**, **`ARCHITECTURE.md`**, **`DECISIONS.md`**, evidencias de ejecución y **URL del repositorio**.

---

## ✅ Criterios de aceptación

- El modelo representa correctamente el negocio y llega hasta **3FN**.
- La lógica crítica vive en **PostgreSQL** (transacciones, restricciones, **RLS**, funciones, vistas y procedimientos).
- La **carga del corpus** funciona.
- API, **JWT**, frontend responsivo, **i18n** y **copiloto** funcionan de punta a punta.
- El registro de avistamientos se refleja **en tiempo real**.

## ⛔ Condiciones que invalidan el proyecto

- Contraseñas almacenadas en **texto plano**.
- Existe **borrado físico** de avistamientos, **SQL por concatenación** o paginación con **`OFFSET`**.
- El copiloto **filtra** ubicaciones o notas de avistamientos por encima de la acreditación del actor.
- No puedes **explicar tu propio código** en la sustentación.

---

## 📊 Rúbrica (100 pts)

| Bloque | Criterio | Puntos |
|---|---|---|
| **Modelado** | Normalización 3FN documentada + MER justificado | 12 |
| **DDL** | Esquema completo con todas las restricciones e índices exigidos | 10 |
| **Lógica en BD** | Funciones transaccionales + vista + 2 procedimientos | 12 |
| **Seguridad (RLS)** | RLS por acreditación + autoría, con rol de aplicación + actor por transacción | 15 |
| **RAG** | pgvector + embeddings + trigger de consistencia + recuperación con permisos | 15 |
| **Backend** | Clean Architecture + SOLID + API REST (keyset, correlación, errores) | 10 |
| **Auth** | JWT access + refresh con rotación + hash seguro + actor del token | 8 |
| **Frontend** | 3 zonas + estados + lazy load + responsivo + i18n | 8 |
| **QA** | 2 pruebas contra Postgres real (acreditación / autoría) | 6 |
| **Despliegue + Docs** | docker compose + migraciones + README/ARCHITECTURE/DECISIONS | 4 |

**Puntos extra (hasta +8):**
- +4 — El copiloto cita correctamente y niega con transparencia en los tres casos (sin acreditación / fuera de alcance / sin contexto).
- +4 — Evidencia (video) con calidad de pitch comercial.

---

## 🗺️ Ruta sugerida (para no perderte)

1. **Modela primero.** No escribas código de app hasta tener el MER y el DDL.
2. **Base de datos blindada.** DDL → RLS (acreditación + autoría) → funciones/procedimientos → trigger de vector. Prueba la seguridad **desde psql** cambiando `app.current_user_id` entre investigadores de distinta acreditación, antes de tener backend.
3. **Backend delgado.** Los casos de uso solo llaman a la BD y mapean. La seguridad ya está en la BD; el backend no la reimplementa.
4. **Auth y actor.** JWT → propagar `app.current_user_id` a cada transacción.
5. **Copiloto.** Recuperación con permisos (reutiliza la consulta 3) → embeddings → LLM con system prompt versionado y citas.
6. **Frontend.** Tres zonas, estados, i18n, ofuscación de ubicaciones sin acceso.
7. **Cierre.** Docker, pruebas, docs, evidencias.

> **Consejo:** documenta cada recorte o decisión en `DECISIONS.md` a medida que avanzas. Un MVP sólido con decisiones justificadas vale más que un proyecto inflado a medias.

---

## 📚 Recursos

- PostgreSQL RLS: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- pgvector: https://github.com/pgvector/pgvector
- Keyset pagination: https://use-the-index-luke.com/no-offset
- JWT refresh rotation, Clean Architecture, OpenAI SDK (documentación oficial de cada uno).

**¡A construir! 🛠️**
