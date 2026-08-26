import { useTranslation } from "react-i18next";

import { SightingsPanel } from "../features/sightings/SightingsPanel";

export function App() {
  const { i18n, t } = useTranslation();
  const nextLanguage = i18n.language.startsWith("es") ? "en" : "es";

  return (
    <main className="app-shell">
      <header className="app-header">
        <div>
          <p className="eyebrow">Fundación Yarumo</p>
          <h1>{t("app.title")}</h1>
        </div>
        <button type="button" onClick={() => void i18n.changeLanguage(nextLanguage)}>
          {t("app.changeLanguage")}
        </button>
      </header>
      <section className="workspace" aria-label={t("app.workspace") }>
        <SightingsPanel />
        <section className="panel" aria-label={t("copilot.title") }>
          <h2>{t("copilot.title")}</h2>
          <p>{t("copilot.placeholder")}</p>
        </section>
        <section className="panel" aria-label={t("profile.title") }>
          <h2>{t("profile.title")}</h2>
          <p>{t("profile.placeholder")}</p>
        </section>
      </section>
    </main>
  );
}

