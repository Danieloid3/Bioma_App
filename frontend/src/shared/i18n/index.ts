import i18n from "i18next";
import { initReactI18next } from "react-i18next";

void i18n.use(initReactI18next).init({
  resources: {
    es: {
      translation: {
        app: { title: "Bioma", changeLanguage: "English", workspace: "Espacio de trabajo" },
        sightings: {
          title: "Avistamientos",
          placeholder: "El mapa y la lista paginada aparecerán aquí.",
          security: "Las coordenadas se muestran únicamente cuando PostgreSQL autoriza el avistamiento.",
        },
        copilot: { title: "Copiloto", placeholder: "Consulta el historial de campo con fuentes citadas." },
        profile: { title: "Perfil", placeholder: "Tu acreditación proviene de tu sesión autenticada." },
      },
    },
    en: {
      translation: {
        app: { title: "Bioma", changeLanguage: "Español", workspace: "Workspace" },
        sightings: {
          title: "Sightings",
          placeholder: "The map and keyset-paginated list will appear here.",
          security: "Coordinates are displayed only when PostgreSQL authorizes the sighting.",
        },
        copilot: { title: "Copilot", placeholder: "Query field history with cited sources." },
        profile: { title: "Profile", placeholder: "Your accreditation comes from your authenticated session." },
      },
    },
  },
  lng: "es",
  fallbackLng: "es",
  interpolation: { escapeValue: false },
});

export default i18n;

