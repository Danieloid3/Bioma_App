import { useEffect, useMemo, useState } from "react";
import { Bird, Bot, FileBarChart, House, Languages, Leaf, MapPin, Menu, MessageCircle, Search, Settings, UsersRound, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useQuery } from "@tanstack/react-query";

import type { AuthenticationResponse, CatalogResponse, Researcher, SiteCatalogResponse } from "../domain/contracts";
import { LoginPage } from "../features/auth/LoginPage";
import { ResearchersPanel, SiteDetailModal, SitesPanel, SpeciesDetailModal, SpeciesPanel } from "../features/catalog/CatalogPanels";
import { CopilotPanel } from "../features/copilot/CopilotPanel";
import { ChatPanel } from "../features/chat/ChatPanel";
import { PromptAdminPanel } from "../features/admin/PromptAdminPanel";
import { DashboardPanel } from "../features/dashboard/DashboardPanel";
import { ProfilePanel } from "../features/profile/ProfilePanel";
import { ReportsPanel } from "../features/reports/ReportsPanel";
import { SightingDetailDialog, SightingsPanel } from "../features/sightings/SightingsPanel";
import { ApiClient } from "../shared/api/client";
import { restoreSession } from "../shared/auth/refreshSession";
import { AnimalAvatar } from "../shared/components/AnimalAvatar";
import { BiomaLoader } from "../shared/components/BiomaLoader";

type View = "dashboard" | "sightings" | "species" | "sites" | "researchers" | "search" | "chat" | "copilot" | "reports" | "profile" | "admin";

export function App() {
  const { i18n, t } = useTranslation();
  const [token, setToken] = useState<string | null>(null);
  const [researcher, setResearcher] = useState<Researcher | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [view, setView] = useState<View>(() => {
    const saved = typeof window !== "undefined" ? sessionStorage.getItem("bioma_active_view") : null;
    return (saved as View) || "dashboard";
  });
  const [menuOpen, setMenuOpen] = useState(false);
  const [selectedSightingId, setSelectedSightingId] = useState<string | null>(null);
  const [selectedSpeciesId, setSelectedSpeciesId] = useState<string | null>(null);
  const [selectedSiteId, setSelectedSiteId] = useState<string | null>(null);
  const api = useMemo(() => new ApiClient(() => token), [token]);
  const species = useQuery({ queryKey: ["catalog-species", token], queryFn: () => api.get<CatalogResponse>("/v1/species"), enabled: Boolean(token) });
  const sites = useQuery({ queryKey: ["catalog-sites", token], queryFn: () => api.get<SiteCatalogResponse>("/v1/sites"), enabled: Boolean(token) });
  const nextLanguage = i18n.language.startsWith("es") ? "en" : "es";

  useEffect(() => {
    async function loadSession() {
      try {
        const response = await restoreSession();
        setToken(response.access_token);
        setResearcher(response.researcher);
      } catch {
        setToken(null);
        setResearcher(null);
      } finally {
        setCheckingSession(false);
      }
    }
    void loadSession();
  }, []);
  async function saveSession(response: AuthenticationResponse) { setToken(response.access_token); setResearcher(response.researcher); }
  async function login(email: string, password: string) { await saveSession(await new ApiClient(() => null).post<AuthenticationResponse>("/v1/auth/login", { email, password })); }
  async function logout() { try { await api.post<void>("/v1/auth/logout"); } finally { setToken(null); setResearcher(null); setView("dashboard"); sessionStorage.removeItem("bioma_active_view"); } }
  if (checkingSession) return <main className="startup"><BiomaLoader label={t("common.loading")} /></main>;
  if (!researcher) return <LoginPage onLogin={login} />;
  const nav: { view: View; icon: typeof House; label: string }[] = [
    { view: "dashboard", icon: House, label: t("nav.dashboard") }, { view: "sightings", icon: Bird, label: t("nav.sightings") },
    { view: "species", icon: Leaf, label: t("nav.species") }, { view: "sites", icon: MapPin, label: t("nav.sites") },
    { view: "researchers", icon: UsersRound, label: t("nav.researchers") }, { view: "search", icon: Search, label: t("nav.search") },
    { view: "chat", icon: MessageCircle, label: t("nav.chat") }, { view: "copilot", icon: Bot, label: t("nav.copilot") }, { view: "reports", icon: FileBarChart, label: t("nav.reports") },
    { view: "profile", icon: Settings, label: t("nav.profile") },
  ];
  const selectView = (value: View) => {
    setView(value);
    sessionStorage.setItem("bioma_active_view", value);
    setMenuOpen(false);
  };

  const mobileNav = [...nav.slice(0, 3), nav.find((item) => item.view === "chat")!];
  return (
    <main className="product-shell">
      <aside className={`sidebar ${menuOpen ? "open" : ""}`}>
        <div className="brand-mark">
          <img src="/bioma-pajaro.png" alt="Bioma Mascot" className="brand-bird-img" />
          <img src="/bioma-letras.png" alt="Bioma" className="brand-letters-img" />
        </div>



        <div className="sidebar-profile">
          <AnimalAvatar avatarKey={researcher.animal_avatar_key} seed={researcher.researcher_id} />
          <div>
            <strong>{researcher.full_name}</strong>
            <span>{researcher.role_title}</span>
          </div>
        </div>
        <nav aria-label={t("nav.label")}>
          {nav.map(({ view: itemView, icon: Icon, label }) => (
            <button
              className={view === itemView ? "nav-item active" : "nav-item"}
              type="button"
              key={itemView}
              onClick={() => selectView(itemView)}
            >
              <Icon aria-hidden="true" />
              {label}
            </button>
          ))}
        </nav>
        <button
          className="language-switch"
          type="button"
          onClick={() => void i18n.changeLanguage(nextLanguage)}
        >
          <Languages aria-hidden="true" />
          {t("app.changeLanguage")}
        </button>
      </aside>
      <section className={`main-content view-${view}`}>
        <header className={`topbar topbar-${view}`}>
          <button
            className="menu-toggle"
            type="button"
            aria-label={t("nav.menu")}
            onClick={() => setMenuOpen((value) => !value)}
          >
            {menuOpen ? <X /> : <Menu />}
          </button>
          <div>
            {view === "dashboard" && (
              <p className="eyebrow">{t("app.greeting", { name: researcher.full_name })}</p>
            )}
            <h1>{t(`views.${view}.title`)}</h1>
          </div>
        </header>
        <div className="view-frame">
          <AppView
            view={view}
            api={api}
            researcher={researcher}
            onLogout={() => void logout()}
            onNavigate={selectView}
            onOpenSighting={setSelectedSightingId}
            onOpenSpecies={setSelectedSpeciesId}
            onOpenSite={setSelectedSiteId}
          />
        </div>
        <nav className="mobile-nav" aria-label={t("nav.label")}>
          {mobileNav.map(({ view: itemView, icon: Icon, label }) => (
            <button
              key={itemView}
              className={view === itemView ? "active" : ""}
              type="button"
              onClick={() => selectView(itemView)}
            >
              <Icon aria-hidden="true" />
              <span>{label}</span>
            </button>
          ))}
        </nav>
      </section>
      {selectedSightingId && (
        <SightingDetailDialog
          api={api}
          sightingId={selectedSightingId}
          onClose={() => setSelectedSightingId(null)}
        />
      )}
      {selectedSpeciesId && species.data?.items.find((item) => item.species_id === selectedSpeciesId) && <SpeciesDetailModal species={species.data.items.find((item) => item.species_id === selectedSpeciesId)!} onClose={() => setSelectedSpeciesId(null)} />}
      {selectedSiteId && sites.data?.items.find((item) => item.site_id === selectedSiteId) && <SiteDetailModal site={sites.data.items.find((item) => item.site_id === selectedSiteId)!} onClose={() => setSelectedSiteId(null)} />}
    </main>
  );
}


function AppView({ view, api, researcher, onLogout, onNavigate, onOpenSighting, onOpenSpecies, onOpenSite }: { view: View; api: ApiClient; researcher: Researcher; onLogout: () => void; onNavigate: (view: View) => void; onOpenSighting: (sightingId: string) => void; onOpenSpecies: (id: string) => void; onOpenSite: (id: string) => void }) {
  if (view === "sightings" || view === "search") return <SightingsPanel api={api} currentResearcher={researcher} />;
  if (view === "species") return <SpeciesPanel api={api} />;
  if (view === "sites") return <SitesPanel api={api} />;
  if (view === "researchers") return <ResearchersPanel api={api} />;
  if (view === "chat") return <ChatPanel api={api} researcher={researcher} onOpenSighting={onOpenSighting} onOpenSpecies={onOpenSpecies} onOpenSite={onOpenSite} />;
  if (view === "admin") return <div className="single-column"><PromptAdminPanel api={api} /></div>;

  if (view === "copilot") return <div className="single-column"><CopilotPanel api={api} researcherId={researcher.researcher_id} onOpenSighting={onOpenSighting} onOpenSpecies={onOpenSpecies} onOpenSite={onOpenSite} /></div>;
  if (view === "profile") return <div className="single-column"><ProfilePanel api={api} researcher={researcher} onLogout={onLogout} onNavigate={onNavigate} /></div>;
  if (view === "reports") return <ReportsPanel api={api} onNavigate={onNavigate} />;
  return <DashboardPanel api={api} onNavigate={onNavigate} />;
}
