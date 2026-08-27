import { Fragment, FormEvent, KeyboardEvent, type ReactNode, useEffect, useRef, useState } from "react";
import { Leaf, Send, Sparkles } from "lucide-react";
import { useMutation } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { CopilotAnswer } from "../../domain/contracts";
import { ApiClient, ApiError } from "../../shared/api/client";
import styles from "./CopilotPanel.module.css";

type ChatMessage =
  | { id: string; role: "user"; text: string }
  | { id: string; role: "assistant"; text: string; sources: CopilotAnswer["sources"] }
  | { id: string; role: "error"; text: string };

function createMessageId() {
  return crypto.randomUUID();
}

export function CopilotPanel({ api, onOpenSighting }: { api: ApiClient; onOpenSighting: (sightingId: string) => void }) {
  const { t } = useTranslation();
  const [question, setQuestion] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const transcriptRef = useRef<HTMLDivElement>(null);
  const ask = useMutation({ mutationFn: (value: string) => api.post<CopilotAnswer>("/v1/copilot/ask", { question: value }) });

  useEffect(() => {
    transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, ask.isPending]);

  async function sendQuestion(value: string) {
    const normalizedQuestion = value.trim();
    if (!normalizedQuestion || ask.isPending) return;

    setQuestion("");
    setMessages((current) => [...current, { id: createMessageId(), role: "user", text: normalizedQuestion }]);
    try {
      const answer = await ask.mutateAsync(normalizedQuestion);
      setMessages((current) => [...current, { id: createMessageId(), role: "assistant", text: answer.answer, sources: answer.sources }]);
    } catch (error) {
      const text = error instanceof ApiError ? error.message : t("errors.network");
      setMessages((current) => [...current, { id: createMessageId(), role: "error", text }]);
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void sendQuestion(question);
  }

  function handleQuestionKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void sendQuestion(question);
    }
  }

  return (
    <section className={styles.panel} aria-label={t("copilot.title")}>
      <header className={styles.header}>
        <div className={styles.mascot} aria-hidden="true"><Leaf /></div>
        <div>
          <p className={styles.eyebrow}>{t("copilot.eyebrow")}</p>
          <h2>{t("copilot.title")}</h2>
          <p>{t("copilot.subtitle")}</p>
        </div>
      </header>

      <div ref={transcriptRef} className={styles.transcript} aria-live="polite" aria-busy={ask.isPending}>
        {messages.length === 0 && (
          <div className={styles.emptyChat}>
            <Sparkles aria-hidden="true" />
            <p>{t("copilot.welcome")}</p>
            <span>{t("copilot.welcomeHint")}</span>
          </div>
        )}
        {messages.map((message) => (
          <article key={message.id} className={`${styles.message} ${styles[message.role]}`}>
            {message.role === "assistant" && <span className={styles.messageMark} aria-hidden="true"><Leaf /></span>}
            <div className={styles.bubble}>
              {message.role === "assistant" ? <FormattedAnswer text={message.text} sources={message.sources} onOpenSighting={onOpenSighting} /> : <p>{message.text}</p>}
              {message.role === "assistant" && message.sources.length > 0 && (
                <div className={styles.sources}>
                  <h3>{t("copilot.sources")}</h3>
                  {message.sources.map((source, index) => (
                    <button className={styles.source} type="button" key={`${source.sighting_id}-${index}`} onClick={() => onOpenSighting(source.sighting_id)}>
                      <strong>{source.observation_reference}</strong>
                      <span>{source.species_common_name}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </article>
        ))}
        {ask.isPending && (
          <article className={`${styles.message} ${styles.assistant}`} aria-label={t("copilot.thinking")}>
            <span className={styles.messageMark} aria-hidden="true"><Leaf /></span>
            <div className={`${styles.bubble} ${styles.typing}`}><i /><i /><i /></div>
          </article>
        )}
      </div>

      <form className={styles.composer} onSubmit={submit}>
        <label className="sr-only" htmlFor="copilot-question">{t("copilot.question")}</label>
        <textarea
          id="copilot-question"
          value={question}
          onChange={(event) => setQuestion(event.target.value)}
          onKeyDown={handleQuestionKeyDown}
          placeholder={t("copilot.placeholder")}
          maxLength={2000}
          rows={2}
          disabled={ask.isPending}
        />
        <div className={styles.composerFooter}>
          <span>{t("copilot.enterHint")}</span>
          <button className="button primary" type="submit" disabled={ask.isPending || !question.trim()}>
            <Send aria-hidden="true" />
            {ask.isPending ? t("copilot.thinking") : t("copilot.ask")}
          </button>
        </div>
      </form>
    </section>
  );
}

function FormattedAnswer({ text, sources, onOpenSighting }: { text: string; sources: CopilotAnswer["sources"]; onOpenSighting: (sightingId: string) => void }) {
  const sourceByReference = new Map(sources.map((source) => [source.observation_reference.toLowerCase(), source]));
  const blocks = text.trim().split(/\n{2,}/).filter(Boolean);
  return <div className={styles.formattedAnswer}>{blocks.map((block, index) => {
    const lines = block.split("\n").filter(Boolean);
    if (lines.every((line) => /^[-•]\s+/.test(line))) return <ul key={index}>{lines.map((line, lineIndex) => <li key={lineIndex}>{linkAuthorizedReferences(line.replace(/^[-•]\s+/, ""), sourceByReference, onOpenSighting)}</li>)}</ul>;
    return <p key={index}>{linkAuthorizedReferences(block, sourceByReference, onOpenSighting)}</p>;
  })}</div>;
}

function linkAuthorizedReferences(text: string, sourceByReference: Map<string, CopilotAnswer["sources"][number]>, onOpenSighting: (sightingId: string) => void): ReactNode[] {
  return text.split(/(\[?obs-[A-Za-z0-9-]+\]?)/g).map((part, index) => {
    const reference = part.replaceAll("[", "").replaceAll("]", "").toLowerCase();
    const source = sourceByReference.get(reference);
    return source ? <button className={styles.inlineReference} type="button" key={index} onClick={() => onOpenSighting(source.sighting_id)}>{part}</button> : <Fragment key={index}>{part}</Fragment>;
  });
}
