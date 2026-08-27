# Bioma Frontend

Cliente React/TypeScript para explorar avistamientos, usar el copiloto y gestionar el perfil del investigador.

## Desarrollo local

```bash
Copy-Item .env.example .env
docker compose up --build
```

La app queda disponible en `http://localhost:5174` y espera el backend de Bioma en `VITE_API_BASE_URL`.

## Flujos disponibles

- Inicio y restauración de sesión mediante JWT en memoria y refresh cookie HttpOnly.
- Listado de avistamientos con filtros, búsqueda y carga por cursor.
- Registro y anulación lógica de avistamientos.
- Copiloto RAG con fuentes autorizadas visibles.
- Perfil, cierre de sesión, interfaz bilingüe y navegación responsive.

La aplicación no calcula permisos ni guarda tokens en `localStorage`; representa exclusivamente los datos autorizados por el API.

## Calidad

```bash
npm run build
npm run lint
```

Antes de cambiar componentes, estilos o contratos de API, consulta `AGENTS.md`. Allí están la paleta, responsive, i18n, accesibilidad y reglas de seguridad de UI.
