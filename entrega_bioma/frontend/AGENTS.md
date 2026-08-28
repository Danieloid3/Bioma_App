# Frontend Bioma — Contexto para agentes

## Misión

El frontend es una aplicación React/TypeScript para exploración de avistamientos, copiloto y perfil. Debe ser sobrio, cálido y científico; la referencia visual es un dashboard natural con navegación lateral verde, tarjetas marfil, acentos dorados y una versión móvil clara. Este repositorio se ejecuta de forma independiente y consume el API configurado por `VITE_API_BASE_URL`.

El cliente representa permisos que ya resolvió la API. Nunca calcula acreditaciones, deofusca coordenadas, conserva registros sensibles en caché compartida ni intenta consultar datos que la API no entregó.

## Estructura

```text
src/app/       Composición de rutas, providers y layout global
src/domain/    Tipos y contratos puros del negocio
src/features/  Flujos de usuario: auth, sightings, copilot, profile
src/shared/    Cliente API, i18n, componentes reutilizables, utilidades y estilos
```

Mantener componentes pequeños y accesibles. Las features no deben importar detalles internos de otras features; compartir contratos o piezas estables desde `domain` o `shared`.

## Lenguaje visual

### Paleta oficial

```text
#7d684b  marrón profundo / texto y acento serio
#897253  marrón secundario
#977d5b  dorado terroso primario
#a68a64  dorado suave / foco y botones
#b6ad90  arena / bordes y fondos suaves
#c2c5aa  salvia pálida
#a4ac86  salvia media
#879263  verde orgánico
#616b4c  verde lateral oscuro
#526241  verde lateral profundo
```

Usar fondos marfil cálidos y neutros oscuros de contraste cuando sea necesario para WCAG; no sacrificar legibilidad por reproducir la imagen. Definir tokens CSS, no dispersar valores hexadecimales en componentes.

El lienzo de las vistas de escritorio usa `public/organic-workspace-background.png` como ambientación detrás del contenido, con una capa marfil que preserva contraste. El selector de idioma vive únicamente en la barra lateral. Los listados de avistamientos deben comunicar con `:hover` y `:focus-visible` que abren su ficha.

El access token permanece solo en memoria. Al recargar, la aplicación restaura la sesión una sola vez usando la cookie HttpOnly y el refresh token rotativo; no duplicar esa petición, incluso bajo React Strict Mode.

### Estética y responsive

- Escritorio: sidebar verde fija, cabecera ligera, métricas en tarjetas, contenido espacioso y sombras muy sutiles.
- Móvil: cabecera compacta, tarjetas apiladas, navegación inferior; no intentar comprimir el sidebar de escritorio.
- Títulos y navegación: Poppins. Texto, tablas y formularios: Inter.
- Iconografía lineal coherente, preferiblemente Lucide; no mezclar familias de iconos.
- Estados de clasificación: público salvia, restringido arena/dorado, confidencial marrón profundo. Nunca comunicar sensibilidad únicamente con color.
- Incluir estados loading, vacío, error, reintento, pendiente/enviado/fallido y preservación de scroll durante lazy/keyset loading.

## Reglas funcionales y de seguridad

- Español e inglés desde i18next: no escribir cadenas visibles directamente en componentes.
- Access token en memoria; refresh token en cookie HttpOnly manejada por API. No persistir tokens en `localStorage`.
- Todos los `fetch` pasan por `shared/api`; incluir correlation ID, `credentials: 'include'` cuando corresponda y manejo uniforme de errores.
- No renderizar HTML de `ts_headline` ni contenido del copiloto sin sanitización. Las citas son enlaces/identificadores de datos ya autorizados.
- Si una coordenada no viene en la respuesta, mostrar estado de acceso limitado u omitir el registro conforme al contrato de la API; nunca inferir ni aproximar ubicación.
- El panel de Copiloto IA gestiona hilos de conversación persistentes (`/v1/copilot/conversations`) y su historial de mensajes, permitiendo crear nuevas consultas, alternar entre hilos y mantener la sesión activa sin pérdida de contexto.


## Calidad

- TypeScript estricto, componentes con responsabilidad única, hooks para lógica de estado y pruebas para flujos críticos.
- Usar TanStack Query para cache, keyset/infinite loading y mutaciones; invalidar por evento SSE sin incluir datos sensibles en el evento.
- Verificar navegación por teclado, foco, contraste, etiquetas y vista móvil antes de commit.
- Actualizar este archivo al hacer commit cuando cambie la estética, componentes compartidos, estructura, contratos API, dependencias o reglas de seguridad.

## Estado implementado

- `App` conserva únicamente el access token en memoria y recupera sesión con la cookie HttpOnly al iniciar.
- `shared/api/client.ts` es el único acceso HTTP; adjunta bearer, cookies y `X-Correlation-ID`, y convierte el contrato de error del API en `ApiError`.
- `SightingsPanel` usa TanStack Query e historial por keyset; `CopilotPanel` muestra únicamente las fuentes retornadas por el API.
- La navegación actual no usa un router externo: las vistas dashboard, avistamientos, búsqueda, copiloto y perfil se componen dentro de `App` para este alcance.
- El dashboard consume exclusivamente `GET /v1/dashboard`; las tarjetas y el gráfico no usan cifras de relleno. Especies recibe su foto icónica, texto alternativo y atribución desde el API; abrir la licencia en una nueva pestaña y no tratarla como evidencia de campo.
- Las filas de avistamientos son abribles y solicitan su ficha al API; no usar datos de lista para reconstruir detalles o coordenadas. El copiloto conserva solamente el historial de la sesión en memoria, renderiza texto sin HTML y envía con Enter (Shift+Enter añade salto).
- Las referencias `obs-*` dentro de una respuesta del copiloto solo se convierten en controles clicables si coinciden con `sources` devueltas por el API; el control abre la ficha protegida global, nunca una URL o identificador generado por el modelo.
- El copiloto consulta `GET /v1/copilot/usage` para mostrar exclusivamente el total autorizado del actor (consultas, tokens procesados y última consulta); invalida el resumen después de una respuesta y no estima consumo en el cliente.
- In desktop, the main content area is constrained to viewport height with `overflow: hidden`. The view-frame scrolls internally without visible scrollbars. This prevents any full-page scroll on desktop. (Superficies acotadas con scroll interno).
- The sidebar has an organic curved shape with rounded corners on top-right (1.5rem) and bottom-right (2.75rem), stopping short of full viewport height to reveal the organic background beneath.
- `shared/components/AnimalAvatar.tsx` representa investigadores con iconografía animal de Lucide. Consume `animal_avatar_key` opcional cuando el API lo entrega y, mientras no exista, deriva un icono estable desde `researcher_id`; no persiste ni inventa perfiles de investigador.
- Toda acción destructiva o de anulación (anular avistamiento, eliminar conversación del copiloto) requiere siempre confirmación explícita mediante un modal / popup con advertencia y detalles antes de ejecutar la mutación.
- Los botones de edición y anulación de avistamientos solo se muestran y ejecutan para los registros creados por el propio investigador autenticado (`isOwner`).
- Las conversaciones del copiloto tienen ciclo de vida explícito: al presionar "Nueva consulta" se crea un nuevo registro en PostgreSQL (`POST /v1/copilot/conversations`), se selecciona como activo y se limpia la vista; al enviar la primera pregunta, el título se actualiza automáticamente; al eliminar, se archiva (`DELETE`) y se conmuta a la siguiente conversación activa.
- Las respuestas del copiloto formatean Markdown completo (`## ` H2, `### ` H3, cursivas científicas `*Tremarctos ornatus*`, negritas y listas con viñetas) y renderizan citas interactivas protegidas `[obs-XXXX]`.
- Las vistas de catálogo de Especies y Sitios cuentan con fichas científicas modales interactivas (`SpeciesDetailModal`, `SiteDetailModal`) con imagen panorámica hero (`21rem`), degradado difuminado marfil, insignias UICN y tarjetas de descripción, hábitat, dieta y estado de conservación.
- El panel de Mensajería Interna (`ChatPanel.tsx`) implementa interfaz en dos paneles (contactos/canales a la izquierda y conversación al centro con tuerca de consumo e invocación a `@copilot`), modal interactivo de creación de grupos de investigación (`CreateGroupModal` con búsqueda, selección múltiple de colegas y validación), menú flotante de tres puntos en hover, edición inline con persistencia versionada e indicador de lápiz, y estado de mensaje eliminado con icono de prohibido y texto tombstone *"Este mensaje fue eliminado"*.
- Identidad visual oficial: el logotipo de Bioma se compone con assets de alta definición (`bioma-pajaro.png` y `bioma-letras.png`) con paleta orgánica cálida y tipografía dorada/arena, garantizando nitidez tipográfica en la barra lateral y login, y exponiendo el isotipo cuadrado del ave centrado como favicon del navegador (`favicon.png` / `favicon.svg`).
- Terminología accesible: la interfaz elimina cualquier tecnicismo interno de base de datos como "RLS" de las vistas de usuario, utilizando expresiones claras para el investigador como *"Canal seguro y confidencial"* y *"Nivel de acceso"*.
- Pipeline de CI/CD activo en `.github/workflows/ci.yml` que valida TypeScript (`npx tsc --noEmit`), empaqueta Vite y ejecuta pruebas automatizadas en GitHub Actions.

- Registration plan documented in `docs/registration-plan.md` (pending institutional verification before implementation).


- La pantalla de login presenta una estética orgánica dividida en dos paneles a pantalla completa: un hero visual botánico con el lema *"Cada avistamiento cuenta."* y un panel cálido marfil con una tarjeta de ingreso limpia, bordes redondeados, selector de idioma e iconos en los campos de texto; no muestra cuentas de demo ni opción de recordar sesión.
- Las citas autorizadas [obs-XXXX] se visualizan como insignias (pills) amigables e interactivas con el icono de una hoja y la especie o referencia, y las menciones a '@copilot' en el chat resaltan visualmente con un badge verde orgánico y destellos.
- Los grupos exponen a sus miembros mediante `GET /v1/chat/channels/{channel_id}/members`, que el panel presenta en un modal. La vista Administración consume `/v1/admin/system-prompts`: la autorización se aplica en PostgreSQL y permite crear o restaurar versiones inmutables de los prompts.
- El chat sustituye polling por SSE autenticado desde `ApiClient.stream`. Los eventos solo invalidan (`type`, `channel_id`); al recibirlos, `ChatPanel` vuelve a leer canales o el historial activo mediante la API protegida. Debe conservarse la reconexión, el scroll del lector y la regla de no incluir contenido sensible en eventos.
- Las consultas de TanStack Query del `CopilotPanel` incluyen el `researcher_id` autenticado en su clave y limpian la conversación activa al cambiar de sesión; así el caché de una cuenta nunca aparece en otra.
- Los textos visibles y etiquetas accesibles de los modales del chat usan claves `chat.*` de i18next en español e inglés; no añadir cadenas de interfaz directamente al componente.
