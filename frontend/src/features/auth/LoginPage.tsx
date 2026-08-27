import { FormEvent, useState } from "react";
import { Mail, Lock, Eye, EyeOff, Globe } from "lucide-react";
import { useTranslation } from "react-i18next";

import { ApiError } from "../../shared/api/client";

type Props = { onLogin: (email: string, password: string) => Promise<void> };

export function LoginPage({ onLogin }: Props) {
  const { t, i18n } = useTranslation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
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

  const toggleLanguage = () => {
    i18n.changeLanguage(i18n.language === "es" ? "en" : "es");
  };

  return (
    <main className="login-page">
      <section className="login-hero">
        <div className="login-hero-bg" style={{ backgroundImage: "url('/login-bg-botanical.png')" }}></div>
        <div className="login-hero-content">
          <div className="brand-mark login-brand">
            <img src="/bioma-pajaro.png" alt="Bioma Mascot" className="brand-bird-img" />
            <img src="/bioma-letras.png" alt="Bioma" className="brand-letters-img" />
          </div>
          <div className="hero-center-art">
            <img src="/bioma-pajaro.png" alt="Bioma Isotype" className="hero-bird-large" />
            <p className="hero-motto">Cada avistamiento cuenta.</p>
          </div>
        </div>
      </section>

      <section className="login-panel">
        <div className="login-top-actions">
           <button type="button" className="language-toggle" onClick={toggleLanguage} aria-label="Toggle language">
             <Globe size={18} />
             <span>{i18n.language === 'es' ? 'EN' : 'ES'}</span>
           </button>
        </div>

        <div className="login-card-container">
          <form className="login-card" onSubmit={submit}>
            <header className="login-header">
              <h1>{t("login.title", "Bienvenida de nuevo")}</h1>
              <p className="login-desc">{t("login.subtitle", "Ingresa para continuar registrando la vida que observas.")}</p>
            </header>

            <div className="form-group">
              <label htmlFor="email">{t("login.email", "Correo electrónico")}</label>
              <div className="input-with-icon">
                <Mail className="input-icon" size={18} />
                <input
                  id="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  type="email"
                  autoComplete="email"
                  placeholder="ejemplo@fundacion.org"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label htmlFor="password">{t("login.password", "Contraseña")}</label>
              <div className="input-with-icon">
                <Lock className="input-icon" size={18} />
                <input
                  id="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  type={showPassword ? "text" : "password"}
                  autoComplete="current-password"
                  placeholder="••••••••"
                  required
                />
                <button type="button" className="password-toggle" onClick={() => setShowPassword(!showPassword)} aria-label="Toggle password visibility">
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            <div className="form-options">
              <a href="#forgot" className="forgot-link">{t("login.forgot", "¿Olvidaste tu contraseña?")}</a>
            </div>

        {error && <p className="form-error" role="alert">{error}</p>}

            <button className="solid-btn" disabled={submitting} type="submit">
              {submitting ? t("common.loading", "Cargando...") : t("login.submit", "Iniciar sesión")}
        </button>

          </form>
        </div>
      </section>
    </main>
  );
}
