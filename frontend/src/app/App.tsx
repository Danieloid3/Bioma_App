import { useEffect, useMemo, useRef, useState } from "react";
import { Bird, Bot, FileBarChart, House, Languages, Leaf, MapPin, Menu, Search, Settings, UsersRound, X } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { AuthenticationResponse, Researcher } from "../domain/contracts";
import { LoginPage } from "../features/auth/LoginPage";
import { ResearchersPanel, SitesPanel, SpeciesPanel } from "../features/catalog/CatalogPanels";
import { CopilotPanel } from "../features/copilot/CopilotPanel";
import { DashboardPanel } from "../features/dashboard/DashboardPanel";
import { ProfilePanel } from "../features/profile/ProfilePanel";
import { ReportsPanel } from "../features/reports/ReportsPanel";
import { SightingDetailDialog, SightingsPanel } from "../features/sightings/SightingsPanel";
import { ApiClient } from "../shared/api/client";
import { AnimalAvatar } from "../shared/components/AnimalAvatar";

type View = "dashboard" | "sightings" | "species" | "sites" | "researchers" | "search" | "copilot" | "reports" | "profile";

export function App() {
  const { i18n, t } = useTranslation();
  const [token, setToken] = useState<string | null>(null);
  const [researcher, setResearcher] = useState<Researcher | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [view, setView] = useState<View>("dashboard");
  const [menuOpen, setMenuOpen] = useState(false);
  const [selectedSightingId, setSelectedSightingId] = useState<string | null>(null);
  const sessionRestoreStarted = useRef(false);
  const api = useMemo(() => new ApiClient(() => token), [token]);
  const nextLanguage = i18n.language.startsWith("es") ? "en" : "es";

  useEffect(() => {
    // React Strict Mode deliberately re-runs effects in development. A refresh
    // token is rotated on use, so issuing two concurrent restores would make
    // the second request look like token reuse and revoke the session family.
    if (sessionRestoreStarted.current) return;
    sessionRestoreStarted.current = true;

    async function restoreSession() {
      try {
        const response = await new ApiClient(() => null).post<AuthenticationResponse>("/v1/auth/refresh");
        setToken(response.access_token);
        setResearcher(response.researcher);
      } catch {
        setToken(null);
        setResearcher(null);
      } finally {
        setCheckingSession(false);
      }
    }
    void restoreSession();
  }, []);
  async function saveSession(response: AuthenticationResponse) { setToken(response.access_token); setResearcher(response.researcher); }
  async function login(email: string, password: string) { await saveSession(await new ApiClient(() => null).post<AuthenticationResponse>("/v1/auth/login", { email, password })); }
  async function logout() { try { await api.post<void>("/v1/auth/logout"); } finally { setToken(null); setResearcher(null); setView("dashboard"); } }
  if (checkingSession) return <main className="startup"><span className="leaf-loader" />{t("common.loading")}</main>;
  if (!researcher) return <LoginPage onLogin={login} />;
  const nav: { view: View; icon: typeof House; label: string }[] = [
    { view: "dashboard", icon: House, label: t("nav.dashboard") }, { view: "sightings", icon: Bird, label: t("nav.sightings") },
    { view: "species", icon: Leaf, label: t("nav.species") }, { view: "sites", icon: MapPin, label: t("nav.sites") },
    { view: "researchers", icon: UsersRound, label: t("nav.researchers") }, { view: "search", icon: Search, label: t("nav.search") },
    { view: "copilot", icon: Bot, label: t("nav.copilot") }, { view: "reports", icon: FileBarChart, label: t("nav.reports") },
    { view: "profile", icon: Settings, label: t("nav.profile") },
  ];
  const selectView = (value: View) => { setView(value); setMenuOpen(false); };
  return <main className="product-shell"><aside className={`sidebar ${menuOpen ? "open" : ""}`}><div className="brand-mark"><Bird aria-hidden="true" /><span>bioma</span></div><div className="sidebar-profile"><AnimalAvatar avatarKey={researcher.animal_avatar_key} seed={researcher.researcher_id} /><div><strong>{researcher.full_name}</strong><span>{researcher.role_title}</span></div></div><nav aria-label={t("nav.label")}>{nav.map(({ view: itemView, icon: Icon, label }) => <button className={view === itemView ? "nav-item active" : "nav-item"} type="button" key={itemView} onClick={() => selectView(itemView)}><Icon aria-hidden="true" />{label}</button>)}</nav><button className="language-switch" type="button" onClick={() => void i18n.changeLanguage(nextLanguage)}><Languages aria-hidden="true" />{t("app.changeLanguage")}</button></aside><section className={`main-content view-${view}`}><header className={`topbar topbar-${view}`}><button className="menu-toggle" type="button" aria-label={t("nav.menu")} onClick={() => setMenuOpen((value) => !value)}>{menuOpen ? <X /> : <Menu />}</button><div>{view === "dashboard" && <p className="eyebrow">{t("app.greeting", { name: researcher.full_name })}</p>}<h1>{t(`views.${view}.title`)}</h1></div></header><div className="view-frame"><AppView view={view} api={api} researcher={researcher} onLogout={() => void logout()} onNavigate={selectView} onOpenSighting={setSelectedSightingId} /></div><nav className="mobile-nav" aria-label={t("nav.label")}>{nav.slice(0, 4).map(({ view: itemView, icon: Icon, label }) => <button key={itemView} className={view === itemView ? "active" : ""} type="button" onClick={() => selectView(itemView)}><Icon aria-hidden="true" /><span>{label}</span></button>)}</nav></section>{selectedSightingId && <SightingDetailDialog api={api} sightingId={selectedSightingId} onClose={() => setSelectedSightingId(null)} />}</main>;
}

function AppView({ view, api, researcher, onLogout, onNavigate, onOpenSighting }: { view: View; api: ApiClient; researcher: Researcher; onLogout: () => void; onNavigate: (view: View) => void; onOpenSighting: (sightingId: string) => void }) {
  if (view === "sightings" || view === "search") return <SightingsPanel api={api} currentResearcher={researcher} />;
  if (view === "species") return <SpeciesPanel api={api} />;
  if (view === "sites") return <SitesPanel api={api} />;
  if (view === "researchers") return <ResearchersPanel api={api} />;
  if (view === "copilot") return <div className="single-column"><CopilotPanel api={api} onOpenSighting={onOpenSighting} /></div>;
  if (view === "profile") return <div className="single-column"><ProfilePanel researcher={researcher} onLogout={onLogout} /></div>;
  if (view === "reports") return <ReportsPanel api={api} onNavigate={onNavigate} />;
  return <DashboardPanel api={api} onNavigate={onNavigate} />;
}
