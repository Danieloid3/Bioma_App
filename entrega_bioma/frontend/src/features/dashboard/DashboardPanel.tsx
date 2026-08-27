import type { ReactNode } from "react";
import { BarChart3, Bird, FileText, MapPin, Sprout } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { DashboardResponse } from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";
import { SightingsPanel } from "../sightings/SightingsPanel";

export type DashboardDestination = "sightings" | "species" | "sites";

export function DashboardPanel({ api, onNavigate }: { api: ApiClient; onNavigate: (destination: DashboardDestination) => void }) {
  const { i18n, t } = useTranslation();
  const dashboard = useQuery({ queryKey: ["dashboard"], queryFn: () => api.get<DashboardResponse>("/v1/dashboard") });
  if (dashboard.isLoading) return <DashboardSkeleton />;
  if (dashboard.isError || !dashboard.data) return <section className="panel-state"><p>{t("dashboard.error")}</p><button className="button secondary" type="button" onClick={() => void dashboard.refetch()}>{t("common.retry")}</button></section>;
  const { summary, classification, activity } = dashboard.data;
  const total = classification.reduce((sum, item) => sum + item.total, 0);
  return <div className="dashboard">
    <section className="dashboard-intro"><p>{t("dashboard.subtitle")}</p><span className="date-chip">{new Intl.DateTimeFormat(i18n.language, { dateStyle: "long" }).format(new Date())}</span></section>
    <section className="metric-grid">
      <Metric icon={<Bird />} label={t("dashboard.metrics.sightings")} value={summary.visible_sightings} onClick={() => onNavigate("sightings")} />
      <Metric icon={<Sprout />} label={t("dashboard.metrics.species")} value={summary.registered_species} onClick={() => onNavigate("species")} />
      <Metric icon={<MapPin />} label={t("dashboard.metrics.sites")} value={summary.monitored_sites} onClick={() => onNavigate("sites")} />
      <Metric icon={<FileText />} label={t("dashboard.metrics.notes")} value={summary.field_notes} onClick={() => onNavigate("sightings")} />
    </section>
    <section className="dashboard-grid">
      <SightingsPanel api={api} compact onViewAll={() => onNavigate("sightings")} />
      <article className="insight-card"><div className="section-heading"><div><h2>{t("dashboard.classificationTitle")}</h2><p>{t("dashboard.classificationSubtitle")}</p></div><BarChart3 aria-hidden="true" /></div><ClassificationChart items={classification} total={total} /></article>
      <article className="activity-card"><div className="section-heading"><div><h2>{t("dashboard.activityTitle")}</h2><p>{t("dashboard.activitySubtitle")}</p></div></div><div className="activity-list">{activity.length ? activity.map((item) => <div className="activity-row" key={`${item.activity_type}-${item.observation_reference}-${item.occurred_at}`}><span className={`activity-dot ${item.activity_type}`} aria-hidden="true" /><p><strong>{item.researcher_name}</strong> {t(`dashboard.activity.${item.activity_type}`)} <em>{item.species_common_name}</em><small>{new Intl.DateTimeFormat(i18n.language, { dateStyle: "short", timeStyle: "short" }).format(new Date(item.occurred_at))}</small></p></div>) : <p className="empty-state">{t("dashboard.activityEmpty")}</p>}</div></article>
    </section>
  </div>;
}

function Metric({ icon, label, value, onClick }: { icon: ReactNode; label: string; value: number; onClick: () => void }) { return <button className="metric-card" type="button" onClick={onClick}><span className="metric-icon">{icon}</span><span><span className="metric-label">{label}</span><strong>{value.toLocaleString()}</strong></span></button>; }
function ClassificationChart({ items, total }: { items: DashboardResponse["classification"]; total: number }) { const { t } = useTranslation(); return <div className="classification-chart"><div className="chart-total"><strong>{total}</strong><span>{t("dashboard.total")}</span></div><div className="classification-legend">{[1, 2, 3].map((level) => { const count = items.find((item) => item.classification_level === level)?.total ?? 0; const label = ["public", "restricted", "confidential"][level - 1]; return <div key={level}><span className={`legend-dot ${label}`} /><p>{t(`classification.${label}`)}</p><strong>{count}</strong></div>; })}</div></div>; }
function DashboardSkeleton() { return <div className="dashboard"><div className="skeleton intro" /><section className="metric-grid">{Array.from({ length: 4 }, (_, index) => <div className="skeleton metric" key={index} />)}</section><section className="dashboard-grid"><div className="skeleton panel" /><div className="skeleton panel" /><div className="skeleton panel" /></section></div>; }
