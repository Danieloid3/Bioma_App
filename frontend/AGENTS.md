# Frontend Bioma — Contexto para agentes

## Misión

El frontend es una aplicación React/TypeScript para exploración de avistamientos, copiloto y perfil. Debe ser sobrio, cálido y científico; la referencia visual es un dashboard natural con navegación lateral verde, tarjetas marfil, acentos dorados y una versión móvil clara.

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

## Calidad

- TypeScript estricto, componentes con responsabilidad única, hooks para lógica de estado y pruebas para flujos críticos.
- Usar TanStack Query para cache, keyset/infinite loading y mutaciones; invalidar por evento SSE sin incluir datos sensibles en el evento.
- Verificar navegación por teclado, foco, contraste, etiquetas y vista móvil antes de commit.
- Actualizar este archivo al hacer commit cuando cambie la estética, componentes compartidos, estructura, contratos API, dependencias o reglas de seguridad.

