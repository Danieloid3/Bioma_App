import { FileBarChart, MapPin, Sprout } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { DashboardResponse } from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";

type ReportDestination = "sightings" | "species" | "sites";

export function ReportsPanel({ api, onNavigate }: { api: ApiClient; onNavigate: (destination: ReportDestination) => void }) {
  const { t } = useTranslation();
  const report = useQuery({ queryKey: ["dashboard"], queryFn: () => api.get<DashboardResponse>("/v1/dashboard") });

  if (report.isLoading) return <div className="skeleton panel" />;
  if (report.isError || !report.data) return <section className="panel-state"><FileBarChart aria-hidden="true" /><p>{t("reports.error")}</p><button className="button secondary" type="button" onClick={() => void report.refetch()}>{t("common.retry")}</button></section>;

  const { summary, classification } = report.data;
  const metrics: { icon: typeof FileBarChart; value: number; label: string; destination: ReportDestination }[] = [
    { icon: FileBarChart, value: summary.visible_sightings, label: t("dashboard.metrics.sightings"), destination: "sightings" },
    { icon: Sprout, value: summary.registered_species, label: t("dashboard.metrics.species"), destination: "species" },
    { icon: MapPin, value: summary.monitored_sites, label: t("dashboard.metrics.sites"), destination: "sites" },
  ];

  return <section className="reports-page">
    <div className="section-heading"><div><p className="eyebrow">{t("reports.eyebrow")}</p><h2>{t("reports.title")}</h2><p>{t("reports.description")}</p></div></div>
    <div className="report-summary">
      {metrics.map(({ icon: Icon, value, label, destination }) => <button className="report-metric" type="button" key={destination} onClick={() => onNavigate(destination)}><Icon aria-hidden="true" /><strong>{value.toLocaleString()}</strong><span>{label}</span></button>)}
    </div>
    <article className="report-classification">
      <h3>{t("dashboard.classificationTitle")}</h3>
      <div className="report-scroll" tabIndex={0} aria-label={t("reports.classificationLabel")}>
        {classification.map((item) => {
          const label = ["public", "restricted", "confidential"][item.classification_level - 1];
          const percentage = summary.visible_sightings ? Math.round((item.total / summary.visible_sightings) * 100) : 0;
          return <div className="report-bar" key={item.classification_level}><span>{t(`classification.${label}`)}</span><div><i className={label} style={{ width: `${percentage}%` }} /></div><strong>{item.total}</strong></div>;
        })}
      </div>
    </article>
  </section>;
}
