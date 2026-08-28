import { useState } from "react";
import {
  BadgeInfo,
  ChevronRight,
  Compass,
  FileText,
  ImageOff,
  Leaf,
  MapPinned,
  Mountain,
  ShieldAlert,
  TreePine,
  UsersRound,
  Utensils,
  X,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { BiomaLoader } from "../../shared/components/BiomaLoader";
import { useTranslation } from "react-i18next";

import type {
  CatalogResponse,
  ResearcherDirectoryResponse,
  SiteCatalogItem,
  SiteCatalogResponse,
  SpeciesCatalogItem,
} from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";
import { AnimalAvatar } from "../../shared/components/AnimalAvatar";

export function SpeciesPanel({ api }: { api: ApiClient }) {
  const { i18n, t } = useTranslation();
  const [selectedSpecies, setSelectedSpecies] = useState<SpeciesCatalogItem | null>(null);

  const query = useQuery({
    queryKey: ["species"],
    queryFn: () => api.get<CatalogResponse>("/v1/species"),
  });

  if (query.isLoading) return <LoadingGrid />;
  if (query.isError) return <ErrorState retry={() => void query.refetch()} />;

  return (
    <section className="catalog-page">
      <div className="section-heading">
        <div>
          <p className="eyebrow">{t("catalog.eyebrow")}</p>
          <h2>{t("catalog.speciesTitle")}</h2>
        </div>
      </div>

      <div className="species-grid">
        {query.data?.items.map((species) => {
          const altText =
            (i18n.language.startsWith("es") ? species.image_alt_text_es : species.image_alt_text_en) ??
            species.common_name;

          return (
            <article
              className="species-card interactive"
              key={species.species_id}
              onClick={() => setSelectedSpecies(species)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  setSelectedSpecies(species);
                }
              }}
              tabIndex={0}
              role="button"
              aria-label={`${species.common_name} (${species.scientific_name})`}
            >
              {species.image_url ? (
                <img src={species.image_url} alt={altText} />
              ) : (
                <div className="image-fallback">
                  <ImageOff />
                </div>
              )}
              <div className="species-copy">
                <div className="card-top-tags">
                  <span className="iucn-pill">{species.iucn_category}</span>
                </div>
                <h3>{species.common_name}</h3>
                <i>{species.scientific_name}</i>

                <div className="card-action-hint">
                  <span>{t("catalog.viewDetails")}</span>
                  <ChevronRight aria-hidden="true" />
                </div>
              </div>
            </article>
          );
        })}
      </div>

      {selectedSpecies && (
        <SpeciesDetailModal
          species={selectedSpecies}
          onClose={() => setSelectedSpecies(null)}
        />
      )}
    </section>
  );
}

function SpeciesDetailModal({
  species,
  onClose,
}: {
  species: SpeciesCatalogItem;
  onClose: () => void;
}) {
  const { i18n, t } = useTranslation();
  const altText =
    (i18n.language.startsWith("es") ? species.image_alt_text_es : species.image_alt_text_en) ??
    species.common_name;

  return (
    <div className="catalog-modal-backdrop" onClick={onClose}>
      <div className="catalog-modal-dialog" onClick={(e) => e.stopPropagation()}>
        <button
          type="button"
          className="catalog-modal-close-sticky"
          onClick={onClose}
          title={t("catalog.close")}
        >
          <X aria-hidden="true" />
        </button>

        <div className="catalog-modal-hero">
          {species.image_url ? (
            <img src={species.image_url} alt={altText} className="catalog-hero-image" />
          ) : (
            <div className="image-fallback hero-fallback">
              <Leaf />
            </div>
          )}
          <div className="catalog-hero-gradient" />
          <div className="catalog-hero-caption">
            <span className="iucn-badge">{species.iucn_category}</span>
            <h2>{species.common_name}</h2>
            <i>{species.scientific_name}</i>
          </div>
        </div>

        <div className="catalog-modal-body">
          <div className="catalog-modal-sections">
            {species.description && (
              <div className="catalog-info-card">
                <div className="info-card-header">
                  <FileText aria-hidden="true" />
                  <span>{t("catalog.description")}</span>
                </div>
                <p>{species.description}</p>
              </div>
            )}

            {species.habitat && (
              <div className="catalog-info-card">
                <div className="info-card-header">
                  <Mountain aria-hidden="true" />
                  <span>{t("catalog.habitat")}</span>
                </div>
                <p>{species.habitat}</p>
              </div>
            )}

            {species.diet && (
              <div className="catalog-info-card">
                <div className="info-card-header">
                  <Utensils aria-hidden="true" />
                  <span>{t("catalog.diet")}</span>
                </div>
                <p>{species.diet}</p>
              </div>
            )}

            {species.conservation_status && (
              <div className="catalog-info-card alert-card">
                <div className="info-card-header">
                  <ShieldAlert aria-hidden="true" />
                  <span>{t("catalog.conservation")}</span>
                </div>
                <p>{species.conservation_status}</p>
              </div>
            )}
          </div>

          {species.image_attribution && (
            <div className="catalog-modal-attribution">
              {species.image_license_url ? (
                <a href={species.image_license_url} target="_blank" rel="noreferrer">
                  {t("catalog.photoCredit", {
                    attribution: species.image_attribution,
                    license: species.image_license_code,
                  })}
                </a>
              ) : (
                <small>
                  {t("catalog.photoCredit", {
                    attribution: species.image_attribution,
                    license: species.image_license_code,
                  })}
                </small>
              )}
            </div>
          )}

          <div className="catalog-modal-actions">
            <button type="button" className="button primary" onClick={onClose}>
              {t("catalog.close")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export function SitesPanel({ api }: { api: ApiClient }) {
  const { i18n, t } = useTranslation();
  const [selectedSite, setSelectedSite] = useState<SiteCatalogItem | null>(null);

  const query = useQuery({
    queryKey: ["sites"],
    queryFn: () => api.get<SiteCatalogResponse>("/v1/sites"),
  });

  if (query.isLoading) return <LoadingGrid />;
  if (query.isError) return <ErrorState retry={() => void query.refetch()} />;

  return (
    <section className="catalog-page">
      <div className="section-heading">
        <div>
          <p className="eyebrow">{t("catalog.eyebrow")}</p>
          <h2>{t("catalog.sitesTitle")}</h2>
        </div>
      </div>

      <div className="site-grid">
        {query.data?.items.map((site) => {
          const altText =
            (i18n.language.startsWith("es") ? site.image_alt_text_es : site.image_alt_text_en) ??
            site.site_name;

          return (
            <article
              className="species-card interactive"
              key={site.site_id}
              onClick={() => setSelectedSite(site)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  setSelectedSite(site);
                }
              }}
              tabIndex={0}
              role="button"
              aria-label={site.site_name}
            >
              {site.image_url ? (
                <img src={site.image_url} alt={altText} />
              ) : (
                <div
                  className="image-fallback"
                  role="img"
                  aria-label={t("catalog.siteImageFallback", { site: site.site_name })}
                >
                  <MapPinned aria-hidden="true" />
                </div>
              )}
              <div className="species-copy">
                <div className="card-top-tags">
                  <span className="iucn-pill">{t("catalog.siteLabel")}</span>
                </div>
                <h3>{site.site_name}</h3>
                <i>{site.region}</i>

                <div className="card-action-hint">
                  <span>{t("catalog.viewDetails")}</span>
                  <ChevronRight aria-hidden="true" />
                </div>
              </div>
            </article>
          );
        })}
      </div>

      {selectedSite && (
        <SiteDetailModal site={selectedSite} onClose={() => setSelectedSite(null)} />
      )}
    </section>
  );
}

function SiteDetailModal({
  site,
  onClose,
}: {
  site: SiteCatalogItem;
  onClose: () => void;
}) {
  const { i18n, t } = useTranslation();
  const altText =
    (i18n.language.startsWith("es") ? site.image_alt_text_es : site.image_alt_text_en) ??
    site.site_name;

  return (
    <div className="catalog-modal-backdrop" onClick={onClose}>
      <div className="catalog-modal-dialog" onClick={(e) => e.stopPropagation()}>
        <button
          type="button"
          className="catalog-modal-close-sticky"
          onClick={onClose}
          title={t("catalog.close")}
        >
          <X aria-hidden="true" />
        </button>

        <div className="catalog-modal-hero">
          {site.image_url ? (
            <img src={site.image_url} alt={altText} className="catalog-hero-image" />
          ) : (
            <div className="image-fallback hero-fallback">
              <MapPinned />
            </div>
          )}
          <div className="catalog-hero-gradient" />
          <div className="catalog-hero-caption">
            <span className="iucn-badge">{t("catalog.siteLabel")}</span>
            <h2>{site.site_name}</h2>
            <i>{site.region}</i>
          </div>
        </div>

        <div className="catalog-modal-body">
          <div className="catalog-modal-sections">
            <div className="catalog-info-grid">
              <div className="catalog-info-card">
                <div className="info-card-header">
                  <Compass aria-hidden="true" />
                  <span>{t("catalog.region")}</span>
                </div>
                <p>{site.region}</p>
              </div>

              {site.ecosystem && (
                <div className="catalog-info-card">
                  <div className="info-card-header">
                    <TreePine aria-hidden="true" />
                    <span>{t("catalog.ecosystem")}</span>
                  </div>
                  <p>{site.ecosystem}</p>
                </div>
              )}
            </div>

            {site.description && (
              <div className="catalog-info-card">
                <div className="info-card-header">
                  <FileText aria-hidden="true" />
                  <span>{t("catalog.siteDescription")}</span>
                </div>
                <p>{site.description}</p>
              </div>
            )}
          </div>

          {site.image_attribution && (
            <div className="catalog-modal-attribution">
              {site.image_license_url ? (
                <a href={site.image_license_url} target="_blank" rel="noreferrer">
                  {t("catalog.photoCredit", {
                    attribution: site.image_attribution,
                    license: site.image_license_code,
                  })}
                </a>
              ) : (
                <small>
                  {t("catalog.photoCredit", {
                    attribution: site.image_attribution,
                    license: site.image_license_code,
                  })}
                </small>
              )}
            </div>
          )}

          <div className="catalog-modal-actions">
            <button type="button" className="button primary" onClick={onClose}>
              {t("catalog.close")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export function ResearchersPanel({ api }: { api: ApiClient }) {
  const { t } = useTranslation();
  const query = useQuery({
    queryKey: ["researchers"],
    queryFn: () => api.get<ResearcherDirectoryResponse>("/v1/researchers"),
  });

  if (query.isLoading) return <LoadingGrid />;
  if (query.isError) return <ErrorState retry={() => void query.refetch()} />;

  return (
    <section className="catalog-page">
      <div className="section-heading">
        <div>
          <p className="eyebrow">{t("catalog.eyebrow")}</p>
          <h2>{t("catalog.researchersTitle")}</h2>
        </div>
      </div>
      <div className="researcher-grid">
        {query.data?.items.map((person) => (
          <article className="researcher-card" key={person.researcher_id}>
            <AnimalAvatar avatarKey={person.animal_avatar_key} seed={person.researcher_id} />
            <div>
              <h3>{person.full_name}</h3>
              <p>{person.role_title}</p>
              <span className="level-pill">
                <BadgeInfo aria-hidden="true" />
                {t("profile.level", { level: person.accreditation_level })}
              </span>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function LoadingGrid() {
  return (
    <div className="catalog-page">
      <BiomaLoader />
      <div className="skeleton intro" />
      <div className="species-grid">
        {Array.from({ length: 6 }, (_, index) => (
          <div className="skeleton species" key={index} />
        ))}
      </div>
    </div>
  );
}

function ErrorState({ retry }: { retry: () => void }) {
  const { t } = useTranslation();
  return (
    <section className="panel-state">
      <UsersRound aria-hidden="true" />
      <p>{t("catalog.error")}</p>
      <button className="button secondary" type="button" onClick={retry}>
        {t("common.retry")}
      </button>
    </section>
  );
}
