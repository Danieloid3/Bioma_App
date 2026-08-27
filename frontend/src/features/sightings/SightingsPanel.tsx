import { FormEvent, useMemo, useState } from "react";
import { ChevronDown, LoaderCircle, MapPin, Plus, Search, Trash2, X } from "lucide-react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { CatalogItem, CatalogResponse, Sighting, SightingDetail, SightingPage } from "../../domain/contracts";
import { ApiClient, ApiError } from "../../shared/api/client";

type Cursor = { observedAt: string; sightingId: string } | undefined;
type Props = { api: ApiClient; compact?: boolean; onViewAll?: () => void };

const className = (level: number) => ["public", "restricted", "confidential"][level - 1] ?? "public";

export function SightingsPanel({ api, compact = false, onViewAll }: Props) {
  const { i18n, t } = useTranslation();
  const client = useQueryClient();
  const [speciesId, setSpeciesId] = useState("");
  const [siteId, setSiteId] = useState("");
  const [term, setTerm] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [selectedSightingId, setSelectedSightingId] = useState<string | null>(null);
  const catalog = useQuery({ queryKey: ["catalog"], queryFn: async () => ({ species: await api.get<CatalogResponse>("/v1/species"), sites: await api.get<CatalogResponse>("/v1/sites") }) });
  const filters = useMemo(() => ({ speciesId, siteId }), [speciesId, siteId]);
  const history = useInfiniteQuery({
    queryKey: ["sightings", filters],
    initialPageParam: undefined as Cursor,
    queryFn: ({ pageParam }) => listSightings(api, filters, pageParam),
    getNextPageParam: (page) => page.items.length === 20 ? cursorFor(page.items) : undefined,
  });
  const search = useQuery({ queryKey: ["sighting-search", term], enabled: term.trim().length > 0, queryFn: () => api.get<SightingPage>("/v1/sightings/search", new URLSearchParams({ term: term.trim() })) });
  const invalidate = () => client.invalidateQueries({ queryKey: ["sightings"] });
  const voidSighting = useMutation({ mutationFn: (sighting: Sighting) => api.post<void>(`/v1/sightings/${sighting.sighting_id}/void`, { reason: t("sightings.voidReason") }), onSuccess: invalidate });
  const items = term.trim() ? search.data?.items ?? [] : history.data?.pages.flatMap((page) => page.items) ?? [];
  const speciesByName = useMemo(() => new Map((catalog.data?.species.items ?? []).filter((species) => species.common_name).map((species) => [species.common_name!.toLocaleLowerCase(), species])), [catalog.data?.species.items]);
  const error = (term.trim() ? search.error : history.error) instanceof ApiError ? ((term.trim() ? search.error : history.error) as ApiError).message : undefined;

  return <section className={`sightings-card ${compact ? "compact" : ""}`} aria-label={t("sightings.title") }>
    <div className="section-heading"><div><p className="eyebrow">{t("sightings.eyebrow")}</p><h2>{t("sightings.title")}</h2></div>{compact && onViewAll ? <button className="button text compact-action" type="button" onClick={onViewAll}>{t("sightings.viewAll")}</button> : !compact && <button className="button primary" type="button" onClick={() => setShowForm((value) => !value)}><Plus aria-hidden="true" />{t("sightings.new")}</button>}</div>
    {!compact && <div className="filters"><label className="search-field"><Search aria-hidden="true" /><input value={term} onChange={(event) => setTerm(event.target.value)} placeholder={t("sightings.search")} /></label><Select value={speciesId} onChange={setSpeciesId} label={t("sightings.allSpecies")} items={catalog.data?.species.items ?? []} idKey="species_id" nameKey="common_name" /><Select value={siteId} onChange={setSiteId} label={t("sightings.allSites")} items={catalog.data?.sites.items ?? []} idKey="site_id" nameKey="site_name" /></div>}
    {showForm && <RegisterForm api={api} species={catalog.data?.species.items ?? []} sites={catalog.data?.sites.items ?? []} onDone={() => { setShowForm(false); invalidate(); }} />}
    {error && <p className="form-error" role="alert">{error}</p>}
    <div className="sighting-list">{(history.isLoading || search.isLoading) && <p className="loading"><LoaderCircle aria-hidden="true" />{t("common.loading")}</p>}{!history.isLoading && !search.isLoading && items.length === 0 && <p className="empty-state">{t("sightings.empty")}</p>}{items.map((sighting) => <SightingRow key={sighting.sighting_id} sighting={sighting} onVoid={() => voidSighting.mutate(sighting)} onOpen={() => setSelectedSightingId(sighting.sighting_id)} compact={compact} image={speciesByName.get(sighting.species_common_name.toLocaleLowerCase())} language={i18n.language} />)}</div>
    {!compact && history.hasNextPage && !term.trim() && <button className="button secondary load-more" type="button" onClick={() => history.fetchNextPage()} disabled={history.isFetchingNextPage}>{history.isFetchingNextPage ? t("common.loading") : t("sightings.loadMore")}</button>}
    {selectedSightingId && <SightingDetailDialog api={api} sightingId={selectedSightingId} onClose={() => setSelectedSightingId(null)} />}
  </section>;
}

function SightingRow({ sighting, onVoid, onOpen, compact, image, language }: { sighting: Sighting; onVoid: () => void; onOpen: () => void; compact: boolean; image?: CatalogItem; language: string }) {
  const { t, i18n } = useTranslation();
  const imageAlt = language.startsWith("es") ? image?.image_alt_text_es : image?.image_alt_text_en;
  const resolvedImage = sighting.image_url ? { image_url: sighting.image_url, image_alt_text_es: sighting.image_alt_text_es } : image;
  return <article className="sighting-row"><button className="sighting-open" type="button" onClick={onOpen} aria-label={t("sightings.open", { species: sighting.species_common_name })}>{resolvedImage?.image_url ? <img className="species-orb species-photo" src={resolvedImage.image_url} alt={imageAlt || sighting.species_common_name} /> : <div className="species-orb" aria-hidden="true">{sighting.species_common_name.slice(0, 1)}</div>}<div className="sighting-main"><h3>{sighting.species_common_name}</h3><p>{sighting.site_name}</p><small>{new Intl.DateTimeFormat(i18n.language, { dateStyle: "medium" }).format(new Date(sighting.observed_at))}</small></div></button><span className={`classification ${className(sighting.classification_level)}`}>{t(`classification.${className(sighting.classification_level)}`)}</span>{!compact && <button className="icon-button" type="button" aria-label={t("sightings.void")} onClick={onVoid}><Trash2 aria-hidden="true" /></button>}</article>;
}

function SightingDetailDialog({ api, sightingId, onClose }: { api: ApiClient; sightingId: string; onClose: () => void }) {
  const { i18n, t } = useTranslation();
  const detail = useQuery({ queryKey: ["sighting", sightingId], queryFn: () => api.get<SightingDetail>(`/v1/sightings/${sightingId}`) });
  return <div className="detail-backdrop" role="presentation" onMouseDown={onClose}><section className="detail-dialog" role="dialog" aria-modal="true" aria-label={t("sightings.detailTitle")} onMouseDown={(event) => event.stopPropagation()}><button className="detail-close" type="button" onClick={onClose} aria-label={t("common.close")}><X /></button>{detail.isLoading && <p className="loading"><LoaderCircle />{t("common.loading")}</p>}{detail.isError && <p className="form-error">{t("sightings.detailError")}</p>}{detail.data && <><header className="detail-header">{detail.data.image_url && <img src={detail.data.image_url} alt={detail.data.image_alt_text_es || detail.data.species_common_name} />}<div><span className={`classification ${className(detail.data.classification_level)}`}>{t(`classification.${className(detail.data.classification_level)}`)}</span><h2>{detail.data.species_common_name}</h2><i>{detail.data.species_scientific_name}</i></div></header><div className="detail-meta"><div><span>{t("sightings.detail.reference")}</span><strong>{detail.data.observation_reference}</strong></div><div><span>{t("sightings.detail.site")}</span><strong>{detail.data.site_name}, {detail.data.region}</strong></div><div><span>{t("sightings.detail.observedAt")}</span><strong>{new Intl.DateTimeFormat(i18n.language, { dateStyle: "long", timeStyle: "short" }).format(new Date(detail.data.observed_at))}</strong></div><div><span>{t("sightings.detail.researcher")}</span><strong>{detail.data.researcher_name}</strong></div></div><section className="detail-notes"><h3>{t("sightings.detail.notes")}</h3><p>{detail.data.field_notes}</p></section><section className="detail-location"><MapPin aria-hidden="true" /><div><h3>{t("sightings.detail.coordinates")}</h3><p>{detail.data.exact_latitude.toFixed(6)}, {detail.data.exact_longitude.toFixed(6)}</p></div></section></>}</section></div>;
}

function Select({ value, onChange, label, items, idKey, nameKey }: { value: string; onChange: (value: string) => void; label: string; items: CatalogItem[]; idKey: "species_id" | "site_id"; nameKey: "common_name" | "site_name" }) {
  return <label className="select-field"><span className="sr-only">{label}</span><select value={value} onChange={(event) => onChange(event.target.value)}><option value="">{label}</option>{items.map((item) => <option key={item[idKey]} value={item[idKey]}>{item[nameKey]}</option>)}</select><ChevronDown aria-hidden="true" /></label>;
}

function RegisterForm({ api, species, sites, onDone }: { api: ApiClient; species: CatalogItem[]; sites: CatalogItem[]; onDone: () => void }) {
  const { t } = useTranslation();
  const [status, setStatus] = useState<"idle" | "pending" | "failed">("idle");
  const [error, setError] = useState<string>();
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setStatus("pending"); setError(undefined);
    const data = new FormData(event.currentTarget);
    try { await api.post("/v1/sightings", { observation_reference: data.get("reference"), species_id: data.get("species"), site_id: data.get("site"), observed_at: new Date(String(data.get("observedAt"))).toISOString(), latitude: Number(data.get("latitude")), longitude: Number(data.get("longitude")), classification_level: Number(data.get("classification")), field_notes: data.get("notes") }); onDone(); } catch (reason) { setStatus("failed"); setError(reason instanceof ApiError ? reason.message : t("errors.network")); }
  }
  return <form className="register-form" onSubmit={submit}><h3>{t("sightings.formTitle")}</h3><label>{t("sightings.reference")}<input name="reference" required pattern="obs-[A-Za-z0-9-]+" /></label><label>{t("sightings.species")}<select name="species" required><option value="">{t("common.select")}</option>{species.map((item) => <option key={item.species_id} value={item.species_id}>{item.common_name}</option>)}</select></label><label>{t("sightings.site")}<select name="site" required><option value="">{t("common.select")}</option>{sites.map((item) => <option key={item.site_id} value={item.site_id}>{item.site_name}</option>)}</select></label><label>{t("sightings.observedAt")}<input name="observedAt" type="datetime-local" required /></label><label>{t("sightings.latitude")}<input name="latitude" type="number" min="-90" max="90" step="any" required /></label><label>{t("sightings.longitude")}<input name="longitude" type="number" min="-180" max="180" step="any" required /></label><label>{t("sightings.classification")}<select name="classification" defaultValue="1"><option value="1">{t("classification.public")}</option><option value="2">{t("classification.restricted")}</option><option value="3">{t("classification.confidential")}</option></select></label><label className="form-wide">{t("sightings.notes")}<textarea name="notes" required /></label>{error && <p className="form-error form-wide" role="alert">{error}</p>}<button className="button primary form-wide" type="submit" disabled={status === "pending"}>{status === "pending" ? t("sightings.pending") : t("sightings.submit")}</button></form>;
}

async function listSightings(api: ApiClient, filters: { speciesId: string; siteId: string }, cursor: Cursor): Promise<SightingPage> {
  const query = new URLSearchParams({ page_size: "20" }); if (filters.speciesId) query.set("species_id", filters.speciesId); if (filters.siteId) query.set("site_id", filters.siteId); if (cursor) { query.set("cursor_observed_at", cursor.observedAt); query.set("cursor_sighting_id", cursor.sightingId); } return api.get<SightingPage>("/v1/sightings", query);
}
function cursorFor(items: Sighting[]): Cursor { const last = items.at(-1); return last ? { observedAt: last.observed_at, sightingId: last.sighting_id } : undefined; }
