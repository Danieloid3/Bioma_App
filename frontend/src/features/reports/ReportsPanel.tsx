import { FileBarChart, MapPin, Sprout } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { DashboardResponse } from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";

export function ReportsPanel({ api }: { api: ApiClient }) {
  const { t } = useTranslation();
  const report = useQuery({ queryKey: ["dashboard"], queryFn: () => api.get<DashboardResponse>("/v1/dashboard") });
  if (report.isLoading) return <div className="skeleton panel" />;
  if (report.isError || !report.data) return <section className="panel-state"><FileBarChart aria-hidden="true" /><p>{t("reports.error")}</p><button className="button secondary" type="button" onClick={() => void report.refetch()}>{t("common.retry")}</button></section>;
  const { summary, classification } = report.data;
  return <section className="reports-page"><div className="section-heading"><div><p className="eyebrow">{t("reports.eyebrow")}</p><h2>{t("reports.title")}</h2><p>{t("reports.description")}</p></div></div><div className="report-summary"><article><FileBarChart aria-hidden="true" /><strong>{summary.visible_sightings}</strong><span>{t("dashboard.metrics.sightings")}</span></article><article><Sprout aria-hidden="true" /><strong>{summary.registered_species}</strong><span>{t("dashboard.metrics.species")}</span></article><article><MapPin aria-hidden="true" /><strong>{summary.monitored_sites}</strong><span>{t("dashboard.metrics.sites")}</span></article></div><article className="report-classification"><h3>{t("dashboard.classificationTitle")}</h3>{classification.map((item) => { const label = ["public", "restricted", "confidential"][item.classification_level - 1]; const percentage = summary.visible_sightings ? Math.round((item.total / summary.visible_sightings) * 100) : 0; return <div className="report-bar" key={item.classification_level}><span>{t(`classification.${label}`)}</span><div><i className={label} style={{ width: `${percentage}%` }} /></div><strong>{item.total}</strong></div>; })}</article></section>;
}
