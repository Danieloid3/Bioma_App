import i18n from "i18next";
import { initReactI18next } from "react-i18next";

const resources = {
  es: { translation: {
    app: { brand: "Bioma", greeting: "Hola, {{name}}", changeLanguage: "English" }, common: { loading: "Cargando…", select: "Selecciona una opción" }, errors: { network: "No fue posible conectar con el servicio." },
    login: { brandCopy: "Registro y análisis seguro de fauna silvestre.", eyebrow: "Fundación Yarumo", title: "Bienvenida a Bioma", subtitle: "Ingresa con tu cuenta de investigación.", email: "Correo electrónico", password: "Contraseña", submit: "Iniciar sesión" },
    nav: { label: "Navegación principal", menu: "Abrir menú", dashboard: "Inicio", sightings: "Avistamientos", search: "Búsqueda", copilot: "Copiloto IA", profile: "Perfil" },
    views: { dashboard: { title: "Resumen de actividad" }, sightings: { title: "Avistamientos" }, search: { title: "Búsqueda de avistamientos" }, copilot: { title: "Copiloto de campo" }, profile: { title: "Tu perfil" } },
    dashboard: { subtitle: "Información científica visible según tu acreditación.", visible: "Registros visibles", live: "En tiempo real", catalog: "Catálogo", realData: "Datos autorizados", copilot: "Copiloto", ready: "Disponible" },
    sightings: { eyebrow: "Historial de campo", title: "Avistamientos recientes", new: "Registrar", search: "Buscar en notas de campo…", allSpecies: "Todas las especies", allSites: "Todos los sitios", empty: "No hay avistamientos disponibles.", loadMore: "Cargar más", void: "Anular avistamiento", voidReason: "Anulación solicitada desde la interfaz", formTitle: "Nuevo avistamiento", reference: "Referencia", species: "Especie", site: "Sitio", observedAt: "Fecha y hora", latitude: "Latitud", longitude: "Longitud", classification: "Clasificación", notes: "Notas de campo", submit: "Guardar avistamiento", pending: "Enviando…" },
    classification: { public: "Público", restricted: "Restringido", confidential: "Confidencial" },
    copilot: { title: "Copiloto IA", subtitle: "Consulta solo el historial autorizado.", question: "Pregunta para el copiloto", placeholder: "Pregunta por observaciones, especies o notas de campo…", ask: "Consultar", thinking: "Consultando…", sources: "Fuentes autorizadas" },
    profile: { title: "Perfil de investigación", signedIn: "Sesión activa", level: "Nivel {{level}}", logout: "Cerrar sesión" },
  } },
  en: { translation: {
    app: { brand: "Bioma", greeting: "Hello, {{name}}", changeLanguage: "Español" }, common: { loading: "Loading…", select: "Select an option" }, errors: { network: "The service could not be reached." },
    login: { brandCopy: "Secure wildlife monitoring and analysis.", eyebrow: "Yarumo Foundation", title: "Welcome to Bioma", subtitle: "Sign in with your research account.", email: "Email address", password: "Password", submit: "Sign in" },
    nav: { label: "Main navigation", menu: "Open menu", dashboard: "Home", sightings: "Sightings", search: "Search", copilot: "AI Copilot", profile: "Profile" },
    views: { dashboard: { title: "Activity summary" }, sightings: { title: "Sightings" }, search: { title: "Search sightings" }, copilot: { title: "Field copilot" }, profile: { title: "Your profile" } },
    dashboard: { subtitle: "Scientific information visible at your accreditation level.", visible: "Visible records", live: "Live", catalog: "Catalogue", realData: "Authorized data", copilot: "Copilot", ready: "Available" },
    sightings: { eyebrow: "Field history", title: "Recent sightings", new: "Register", search: "Search field notes…", allSpecies: "All species", allSites: "All sites", empty: "No sightings are available.", loadMore: "Load more", void: "Void sighting", voidReason: "Void requested from the interface", formTitle: "New sighting", reference: "Reference", species: "Species", site: "Site", observedAt: "Date and time", latitude: "Latitude", longitude: "Longitude", classification: "Classification", notes: "Field notes", submit: "Save sighting", pending: "Sending…" },
    classification: { public: "Public", restricted: "Restricted", confidential: "Confidential" },
    copilot: { title: "AI Copilot", subtitle: "Query authorized field history only.", question: "Question for the copilot", placeholder: "Ask about observations, species, or field notes…", ask: "Ask", thinking: "Thinking…", sources: "Authorized sources" },
    profile: { title: "Research profile", signedIn: "Signed in", level: "Level {{level}}", logout: "Sign out" },
  } },
};

void i18n.use(initReactI18next).init({ resources, lng: "es", fallbackLng: "es", interpolation: { escapeValue: false } });
export default i18n;
