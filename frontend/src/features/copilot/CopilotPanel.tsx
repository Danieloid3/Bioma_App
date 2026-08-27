import { FormEvent, useState } from "react";
import { Bot, Send } from "lucide-react";
import { useMutation } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { CopilotAnswer } from "../../domain/contracts";
import { ApiClient, ApiError } from "../../shared/api/client";

export function CopilotPanel({ api }: { api: ApiClient }) {
  const { t } = useTranslation();
  const [question, setQuestion] = useState("");
  const ask = useMutation({ mutationFn: (value: string) => api.post<CopilotAnswer>("/v1/copilot/ask", { question: value }) });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (question.trim()) ask.mutate(question.trim());
  }

  const message = ask.error instanceof ApiError ? ask.error.message : ask.error ? t("errors.network") : undefined;
  return (
    <section className="copilot-card" aria-label={t("copilot.title") }>
      <div className="section-heading"><span className="icon-disc"><Bot aria-hidden="true" /></span><div><h2>{t("copilot.title")}</h2><p>{t("copilot.subtitle")}</p></div></div>
      <form className="copilot-form" onSubmit={submit}>
        <label className="sr-only" htmlFor="copilot-question">{t("copilot.question")}</label>
        <textarea id="copilot-question" value={question} onChange={(event) => setQuestion(event.target.value)} placeholder={t("copilot.placeholder")} maxLength={2000} />
        <button className="button primary" type="submit" disabled={ask.isPending}><Send aria-hidden="true" />{ask.isPending ? t("copilot.thinking") : t("copilot.ask")}</button>
      </form>
      {message && <p className="form-error" role="alert">{message}</p>}
      {ask.data && <article className="copilot-answer"><p>{ask.data.answer}</p>{ask.data.sources.length > 0 && <div className="sources"><h3>{t("copilot.sources")}</h3>{ask.data.sources.map((source) => <div className="source" key={source.sighting_id}><strong>{source.observation_reference}</strong><span>{source.species_common_name}</span></div>)}</div>}</article>}
    </section>
  );
}
