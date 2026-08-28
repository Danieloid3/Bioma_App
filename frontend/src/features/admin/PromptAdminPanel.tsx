import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { Bot, Check, CheckCircle2, ChevronDown, History, MessageCircle, Save, ShieldAlert, Sparkles } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { ApiClient } from "../../shared/api/client";

type PromptVersion = {
  prompt_id: string;
  scope: "field" | "chat" | "greeting";
  version_key: string;
  prompt_text: string;
  content_sha256: string;
  is_active: boolean;
  created_at: string;
  created_by: string;
};

function friendlyVersionName(version: PromptVersion, scopeLabel: string) {
  const match = version.version_key.match(/-v(\d+)$/i);
  return `${scopeLabel} · versión ${match?.[1] ?? version.version_key}`;
}

export function PromptAdminPanel({ api }: { api: ApiClient }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [scope, setScope] = useState<PromptVersion["scope"]>("field");
  const [text, setText] = useState("");
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const scopeOptions: { value: PromptVersion["scope"]; label: string; icon: typeof Bot }[] = useMemo(
    () => [
      { value: "field", label: t("adminPrompts.field"), icon: Bot },
      { value: "chat", label: t("adminPrompts.chat"), icon: MessageCircle },
      { value: "greeting", label: t("adminPrompts.greeting"), icon: Sparkles },
    ],
    [t],
  );

  const selectedScopeOption = scopeOptions.find((opt) => opt.value === scope) ?? scopeOptions[0];
  const ScopeIcon = selectedScopeOption.icon;
  const scopeLabel = selectedScopeOption.label;

  const prompts = useQuery({
    queryKey: ["admin-system-prompts"],
    queryFn: () => api.get<PromptVersion[]>("/v1/admin/system-prompts"),
  });
  const active = useMemo(() => prompts.data?.find((item) => item.scope === scope && item.is_active), [prompts.data, scope]);
  const create = useMutation({
    mutationFn: () => api.post<string>("/v1/admin/system-prompts", { scope, prompt_text: text }),
    onSuccess: () => {
      setText("");
      void queryClient.invalidateQueries({ queryKey: ["admin-system-prompts"] });
    },
  });
  const activate = useMutation({
    mutationFn: (id: string) => api.post<void>(`/v1/admin/system-prompts/${id}/activate`),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["admin-system-prompts"] }),
  });

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsDropdownOpen(false);
      }
    }
    if (isDropdownOpen) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [isDropdownOpen]);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (text.trim().length >= 40) create.mutate();
  }

  if (prompts.isError) {
    return (
      <section className="admin-prompts">
        <ShieldAlert />
        <h2>{t("adminPrompts.restrictedTitle")}</h2>
        <p>{t("adminPrompts.restrictedDescription")}</p>
      </section>
    );
  }

  return (
    <section className="admin-prompts">
      <header>
        <div>
          <p className="eyebrow">{t("nav.admin")}</p>
          <h2>{t("adminPrompts.title")}</h2>
          <p>{t("adminPrompts.description")}</p>
        </div>
        <ShieldAlert />
      </header>
      <form onSubmit={submit} className="admin-prompt-editor">
        <div className="admin-scope-field">
          <label className="admin-scope-label" id="scope-select-label">
            {t("adminPrompts.scope")}
          </label>
          <div className="admin-custom-select" ref={dropdownRef}>
            <button
              type="button"
              className={`admin-select-trigger ${isDropdownOpen ? "open" : ""}`}
              onClick={() => setIsDropdownOpen((prev) => !prev)}
              aria-haspopup="listbox"
              aria-expanded={isDropdownOpen}
              aria-labelledby="scope-select-label"
            >
              <span className="admin-select-trigger-content">
                <ScopeIcon className="scope-icon" aria-hidden="true" />
                <span className="scope-text">{scopeLabel}</span>
              </span>
              <ChevronDown className={`admin-chevron ${isDropdownOpen ? "open" : ""}`} aria-hidden="true" />
            </button>

            {isDropdownOpen && (
              <ul className="admin-select-menu" role="listbox" tabIndex={-1}>
                {scopeOptions.map((opt) => {
                  const OptionIcon = opt.icon;
                  const isSelected = scope === opt.value;
                  return (
                    <li
                      key={opt.value}
                      role="option"
                      aria-selected={isSelected}
                      className={`admin-select-option ${isSelected ? "selected" : ""}`}
                      onClick={() => {
                        setScope(opt.value);
                        setIsDropdownOpen(false);
                      }}
                    >
                      <div className="admin-option-info">
                        <OptionIcon className="scope-icon" aria-hidden="true" />
                        <span className="admin-option-label">{opt.label}</span>
                      </div>
                      {isSelected && <Check className="admin-option-check" aria-hidden="true" />}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </div>
        <textarea
          value={text}
          onChange={(event) => setText(event.target.value)}
          placeholder={active?.prompt_text ?? t("adminPrompts.placeholder")}
          minLength={40}
          maxLength={20000}
        />
        <button className="button primary" type="submit" disabled={create.isPending || text.trim().length < 40}>
          <Save />
          {t("adminPrompts.save")}
        </button>
      </form>
      <div className="admin-prompt-history">
        <h3>
          <History /> {t("adminPrompts.history")}
        </h3>
        <div className="admin-prompt-history-list">
          {prompts.data?.filter((item) => item.scope === scope).map((item) => (
            <article key={item.prompt_id} className={item.is_active ? "active" : ""}>
              <div>
                <strong>{friendlyVersionName(item, scopeLabel)}</strong>
                <span>{item.is_active ? t("adminPrompts.active") : t("adminPrompts.createdBy", { name: item.created_by })}</span>
                <small>{t("adminPrompts.auditCode", { code: item.content_sha256.slice(0, 12) })}</small>
              </div>
              {item.is_active ? (
                <CheckCircle2 aria-label={t("adminPrompts.active")} />
              ) : (
                <button type="button" className="button text" onClick={() => activate.mutate(item.prompt_id)}>
                  {t("adminPrompts.restore")}
                </button>
              )}
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

