import { FormEvent, useMemo, useState } from "react";
import { CheckCircle2, ChevronDown, History, Save, ShieldAlert } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { ApiClient } from "../../shared/api/client";

type PromptVersion = { prompt_id: string; scope: "field" | "chat" | "greeting"; version_key: string; prompt_text: string; content_sha256: string; is_active: boolean; created_at: string; created_by: string };

function friendlyVersionName(version: PromptVersion, scopeLabel: string) {
  const match = version.version_key.match(/-v(\d+)$/i);
  return `${scopeLabel} · versión ${match?.[1] ?? version.version_key}`;
}

export function PromptAdminPanel({ api }: { api: ApiClient }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [scope, setScope] = useState<PromptVersion["scope"]>("field");
  const [text, setText] = useState("");
  const scopeLabel = scope === "field" ? t("adminPrompts.field") : scope === "chat" ? t("adminPrompts.chat") : t("adminPrompts.greeting");
  const prompts = useQuery({ queryKey: ["admin-system-prompts"], queryFn: () => api.get<PromptVersion[]>("/v1/admin/system-prompts") });
  const active = useMemo(() => prompts.data?.find((item) => item.scope === scope && item.is_active), [prompts.data, scope]);
  const create = useMutation({ mutationFn: () => api.post<string>("/v1/admin/system-prompts", { scope, prompt_text: text }), onSuccess: () => { setText(""); void queryClient.invalidateQueries({ queryKey: ["admin-system-prompts"] }); } });
  const activate = useMutation({ mutationFn: (id: string) => api.post<void>(`/v1/admin/system-prompts/${id}/activate`), onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["admin-system-prompts"] }) });
  function submit(event: FormEvent) { event.preventDefault(); if (text.trim().length >= 40) create.mutate(); }

  if (prompts.isError) return <section className="admin-prompts"><ShieldAlert /><h2>{t("adminPrompts.restrictedTitle")}</h2><p>{t("adminPrompts.restrictedDescription")}</p></section>;

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
        <label>
          {t("adminPrompts.scope")}
          <span className="admin-select">
            <select value={scope} onChange={(event) => setScope(event.target.value as PromptVersion["scope"])}>
              <option value="field">{t("adminPrompts.field")}</option>
              <option value="chat">{t("adminPrompts.chat")}</option>
              <option value="greeting">{t("adminPrompts.greeting")}</option>
            </select>
            <ChevronDown aria-hidden="true" />
          </span>
        </label>
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
