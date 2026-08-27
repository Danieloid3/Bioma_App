import { FormEvent, useState } from "react";
import { Leaf } from "lucide-react";
import { useTranslation } from "react-i18next";

import { ApiError } from "../../shared/api/client";

type Props = { onLogin: (email: string, password: string) => Promise<void> };

export function LoginPage({ onLogin }: Props) {
  const { t } = useTranslation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string>();
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(undefined);
    try {
      await onLogin(email, password);
    } catch (reason) {
      setError(reason instanceof ApiError ? reason.message : t("errors.network"));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="login-page">
      <section className="login-brand" aria-label={t("app.brand") }>
        <div className="brand-mark"><Leaf aria-hidden="true" /><span>bioma</span></div>
        <p>{t("login.brandCopy")}</p>
      </section>
      <form className="login-card" onSubmit={submit}>
        <p className="eyebrow">{t("login.eyebrow")}</p>
        <h1>{t("login.title")}</h1>
        <p>{t("login.subtitle")}</p>
        <label>{t("login.email")}<input value={email} onChange={(event) => setEmail(event.target.value)} type="email" autoComplete="email" required /></label>
        <label>{t("login.password")}<input value={password} onChange={(event) => setPassword(event.target.value)} type="password" autoComplete="current-password" required /></label>
        {error && <p className="form-error" role="alert">{error}</p>}
        <button className="button primary" disabled={submitting} type="submit">{submitting ? t("common.loading") : t("login.submit")}</button>
      </form>
    </main>
  );
}
