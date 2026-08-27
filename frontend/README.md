# Bioma Frontend

Cliente React/TypeScript para explorar avistamientos, usar el copiloto y gestionar el perfil del investigador.

## Desarrollo local

```bash
Copy-Item .env.example .env
docker compose up --build
```

La app queda disponible en `http://localhost:5174` y espera el backend de Bioma en `VITE_API_BASE_URL`.

Antes de cambiar componentes, estilos o contratos de API, consulta `AGENTS.md`. Allí están la paleta, responsive, i18n, accesibilidad y reglas de seguridad de UI.

