import { useTranslation } from "react-i18next";

export function SightingsPanel() {
  const { t } = useTranslation();
  return (
    <section className="panel" aria-label={t("sightings.title") }>
      <h2>{t("sightings.title")}</h2>
      <p>{t("sightings.placeholder")}</p>
      <p className="security-note">{t("sightings.security")}</p>
    </section>
  );
}

