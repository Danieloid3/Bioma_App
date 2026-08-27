import { Fragment, FormEvent, KeyboardEvent, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { Activity, Clock3, Leaf, MessageSquare, Plus, Send, Settings, ShieldCheck, Sparkles, Trash2, X, Zap } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type {
  CopilotAnswer,
  CopilotConversationItem,
  CopilotConversationListResponse,
  CopilotMessage,
  CopilotMessageListResponse,
  CopilotUsageResponse,
} from "../../domain/contracts";
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
  const { i18n, t } = useTranslation();
  const [question, setQuestion] = useState("");
  const [activeConversationId, setActiveConversationId] = useState<string | null>(null);
  const [pendingUserMessage, setPendingUserMessage] = useState<ChatMessage | null>(null);
  const [showUsageModal, setShowUsageModal] = useState(false);
  const [conversationToDelete, setConversationToDelete] = useState<CopilotConversationItem | null>(null);
  const transcriptRef = useRef<HTMLDivElement>(null);
  const queryClient = useQueryClient();

  const conversationsQuery = useQuery({
    queryKey: ["copilot-conversations"],
    queryFn: () => api.get<CopilotConversationListResponse>("/v1/copilot/conversations"),
  });

  // Si no hay conversación activa y la lista de conversaciones carga, seleccionar la primera
  useEffect(() => {
    if (!activeConversationId && conversationsQuery.data?.items && conversationsQuery.data.items.length > 0) {
      setActiveConversationId(conversationsQuery.data.items[0].conversation_id);
    }
  }, [conversationsQuery.data?.items, activeConversationId]);

  const messagesQuery = useQuery({
    queryKey: ["copilot-messages", activeConversationId],
    queryFn: () =>
      activeConversationId
        ? api.get<CopilotMessageListResponse>(`/v1/copilot/conversations/${activeConversationId}/messages`)
        : Promise.resolve({ items: [] }),
    enabled: !!activeConversationId,
  });

  const usage = useQuery({
    queryKey: ["copilot-usage"],
    queryFn: () => api.get<CopilotUsageResponse>("/v1/copilot/usage"),
  });

  // Mutación explícita para crear una nueva conversación
  const createConversation = useMutation({
    mutationFn: (title?: string) =>
      api.post<CopilotConversationItem>("/v1/copilot/conversations", {
        title: title ?? t("copilot.newConversation"),
      }),
    onSuccess: (newConv) => {
      setActiveConversationId(newConv.conversation_id);
      setPendingUserMessage(null);
      setQuestion("");
      queryClient.setQueryData<CopilotConversationListResponse>(["copilot-conversations"], (old) => {
        if (!old) return { items: [newConv] };
        return { items: [newConv, ...old.items.filter((c) => c.conversation_id !== newConv.conversation_id)] };
      });
    },
  });

  const ask = useMutation({
    mutationFn: (payload: { text: string; conversationId: string | null }) =>
      api.post<CopilotAnswer>("/v1/copilot/ask", {
        question: payload.text,
        conversation_id: payload.conversationId,
      }),
    onSuccess: (data) => {
      setPendingUserMessage(null);
      if (data.conversation_id) {
        setActiveConversationId(data.conversation_id);
        void queryClient.invalidateQueries({ queryKey: ["copilot-messages", data.conversation_id] });
      }
      void queryClient.invalidateQueries({ queryKey: ["copilot-conversations"] });
      void queryClient.invalidateQueries({ queryKey: ["copilot-usage"] });
    },
    onError: (error) => {
      setPendingUserMessage(null);
      const text = error instanceof ApiError ? error.message : t("errors.network");
      void queryClient.setQueryData<CopilotMessageListResponse>(
        ["copilot-messages", activeConversationId],
        (old) => {
          const items = old?.items ?? [];
          return {
            items: [
              ...items,
              {
                message_id: createMessageId(),
                conversation_id: activeConversationId ?? "",
                sender_role: "error",
                message_text: text,
                created_at: new Date().toISOString(),
                citations: [],
              },
            ],
          };
        }
      );
    },
  });

  const deleteConversation = useMutation({
    mutationFn: async (convId: string) => {
      await api.delete<void>(`/v1/copilot/conversations/${convId}`);
      return convId;
    },
    onMutate: async (deletedId) => {
      await queryClient.cancelQueries({ queryKey: ["copilot-conversations"] });
      const previous = queryClient.getQueryData<CopilotConversationListResponse>(["copilot-conversations"]);
      
      const updatedItems = (previous?.items ?? []).filter((c) => c.conversation_id !== deletedId);
      queryClient.setQueryData<CopilotConversationListResponse>(["copilot-conversations"], {
        items: updatedItems,
      });

      if (activeConversationId === deletedId) {
        if (updatedItems.length > 0) {
          setActiveConversationId(updatedItems[0].conversation_id);
        } else {
          setActiveConversationId(null);
        }
        setPendingUserMessage(null);
      }
      return { previous };
    },
    onError: (err, _, context) => {
      console.error("Error deleting conversation:", err);
      if (context?.previous) {
        queryClient.setQueryData(["copilot-conversations"], context.previous);
      }
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["copilot-conversations"] });
    },
  });

  const displayedMessages = useMemo(() => {
    const serverMessages: ChatMessage[] = (messagesQuery.data?.items ?? []).map((m: CopilotMessage) => ({
      id: m.message_id,
      role: m.sender_role,
      text: m.message_text,
      sources: m.citations ?? [],
    }));

    if (pendingUserMessage) {
      return [...serverMessages, pendingUserMessage];
    }
    return serverMessages;
  }, [messagesQuery.data?.items, pendingUserMessage]);

  useEffect(() => {
    transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: "smooth" });
  }, [displayedMessages, ask.isPending]);

  async function sendQuestion(value: string) {
    const normalizedQuestion = value.trim();
    if (!normalizedQuestion || ask.isPending) return;

    setQuestion("");
    const tempUserId = createMessageId();
    setPendingUserMessage({ id: tempUserId, role: "user", text: normalizedQuestion });

    try {
      await ask.mutateAsync({
        text: normalizedQuestion,
        conversationId: activeConversationId,
      });
    } catch {
      // Handled in onError
    }
  }

  function handleStartNewConversation() {
    createConversation.mutate(t("copilot.newConversation"));
  }

  function handleSelectConversation(convId: string) {
    setActiveConversationId(convId);
    setPendingUserMessage(null);
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

  const conversations = conversationsQuery.data?.items ?? [];

  return (
    <section className={styles.container} aria-label={t("copilot.title")}>
      {/* Panel vertical izquierdo de conversaciones */}
      <aside className={styles.sidebar} aria-label={t("copilot.conversations")}>
        <div className={styles.sidebarHeader}>
          <button
            type="button"
            className={styles.newChatButton}
            onClick={handleStartNewConversation}
            disabled={createConversation.isPending}
            title={t("copilot.newConversation")}
          >
            <Plus aria-hidden="true" />
            <span>{createConversation.isPending ? t("common.loading") : t("copilot.newConversation")}</span>
          </button>
        </div>

        <div className={styles.conversationList}>
          {conversations.length === 0 ? (
            <div className={styles.emptyConversations}>
              <Sparkles aria-hidden="true" />
              <span>{t("copilot.noConversations")}</span>
            </div>
          ) : (
            conversations.map((c) => {
              const isSelected = c.conversation_id === activeConversationId;
              return (
                <div
                  key={c.conversation_id}
                  className={`${styles.conversationItem} ${isSelected ? styles.itemActive : ""}`}
                >
                  <button
                    type="button"
                    className={styles.itemSelect}
                    onClick={() => handleSelectConversation(c.conversation_id)}
                    title={c.title}
                  >
                    <MessageSquare aria-hidden="true" />
                    <span className={styles.itemTitle}>{c.title}</span>
                  </button>
                  <button
                    type="button"
                    className={styles.itemDelete}
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      setConversationToDelete(c);
                    }}
                    title={t("copilot.deleteConversation")}
                  >
                    <Trash2 aria-hidden="true" />
                  </button>
                </div>
              );
            })
          )}
        </div>
      </aside>

      {/* Área principal de chat */}
      <main className={styles.chatArea}>
        <header className={styles.header}>
          <div className={styles.mascot} aria-hidden="true"><Leaf /></div>
          <div className={styles.headerInfo}>
            <p className={styles.eyebrow}>{t("copilot.eyebrow")}</p>
            <h2>{t("copilot.title")}</h2>
            <p>{t("copilot.subtitle")}</p>
          </div>
          <button
            type="button"
            className={styles.settingsButton}
            onClick={() => setShowUsageModal(true)}
            title={t("copilot.usageTitle")}
          >
            <Settings aria-hidden="true" />
          </button>
        </header>

        <div ref={transcriptRef} className={styles.transcript} aria-live="polite" aria-busy={ask.isPending}>
          {displayedMessages.length === 0 && !ask.isPending && (
            <div className={styles.emptyChat}>
              <Sparkles aria-hidden="true" />
              <p>{t("copilot.welcome")}</p>
              <span>{t("copilot.welcomeHint")}</span>
            </div>
          )}
          {displayedMessages.map((message) => (
            <article key={message.id} className={`${styles.message} ${styles[message.role]}`}>
              {message.role === "assistant" && <span className={styles.messageMark} aria-hidden="true"><Leaf /></span>}
              <div className={styles.bubble}>
                {message.role === "assistant" ? (
                  <FormattedAnswer text={message.text} sources={message.sources} onOpenSighting={onOpenSighting} />
                ) : (
                  <p>{message.text}</p>
                )}
                {message.role === "assistant" && message.sources.length > 0 && (
                  <div className={styles.sources}>
                    <h3>{t("copilot.sources")}</h3>
                    {message.sources.map((source, index) => (
                      <button
                        className={styles.source}
                        type="button"
                        key={`${source.sighting_id}-${index}`}
                        onClick={() => onOpenSighting(source.sighting_id)}
                      >
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
      </main>

      {/* Modal Orgánico de Telemetría */}
      {showUsageModal && (
        <div className={styles.modalBackdrop} onClick={() => setShowUsageModal(false)}>
          <div className={styles.modalContent} onClick={(e) => e.stopPropagation()}>
            <div className={styles.modalHeader}>
              <div className={styles.modalIconDisc}>
                <Activity aria-hidden="true" />
              </div>
              <div className={styles.modalHeaderTitles}>
                <h3>{t("copilot.usageTitle")}</h3>
                <p>{t("copilot.usageSubtitle")}</p>
              </div>
              <button
                type="button"
                className={styles.modalClose}
                onClick={() => setShowUsageModal(false)}
                title={t("common.close")}
              >
                <X aria-hidden="true" />
              </button>
            </div>

            <div className={styles.modalBody}>
              {usage.isLoading && (
                <div className={styles.modalStateMessage}>
                  <Clock3 className={styles.spinnerIcon} />
                  <span>{t("common.loading")}</span>
                </div>
              )}
              {usage.isError && (
                <div className={styles.modalStateMessage}>
                  <span>{t("copilot.usageUnavailable")}</span>
                </div>
              )}
              {usage.data?.item ? (
                <div className={styles.modalCardGrid}>
                  {/* Tarjeta 1: Consultas */}
                  <div className={`${styles.usageCard} ${styles.cardQueries}`}>
                    <div className={styles.cardIconWrapper}>
                      <MessageSquare />
                    </div>
                    <div className={styles.cardContent}>
                      <span className={styles.cardLabel}>{t("copilot.usageQueries")}</span>
                      <strong className={styles.cardValue}>{usage.data.item.total_queries.toLocaleString()}</strong>
                      <span className={styles.cardHint}>{t("copilot.usageQueriesHint")}</span>
                    </div>
                  </div>

                  {/* Tarjeta 2: Tokens */}
                  <div className={`${styles.usageCard} ${styles.cardTokens}`}>
                    <div className={styles.cardIconWrapper}>
                      <Zap />
                    </div>
                    <div className={styles.cardContent}>
                      <span className={styles.cardLabel}>{t("copilot.usageTokens")}</span>
                      <strong className={styles.cardValue}>{usage.data.item.total_tokens.toLocaleString()}</strong>
                      <span className={styles.cardHint}>{t("copilot.usageTokensHint")}</span>
                    </div>
                  </div>

                  {/* Tarjeta 3: Última Actividad */}
                  <div className={`${styles.usageCard} ${styles.cardTime}`}>
                    <div className={styles.cardIconWrapper}>
                      <Clock3 />
                    </div>
                    <div className={styles.cardContent}>
                      <span className={styles.cardLabel}>{t("copilot.usageLastQuery")}</span>
                      <strong className={styles.cardTimeValue}>
                        {new Intl.DateTimeFormat(i18n.language, {
                          dateStyle: "medium",
                          timeStyle: "short",
                        }).format(new Date(usage.data.item.last_query_at))}
                      </strong>
                      <span className={styles.cardHint}>{t("copilot.usageLastQueryHint")}</span>
                    </div>
                  </div>
                </div>
              ) : (
                usage.isSuccess && (
                  <div className={styles.modalStateMessage}>
                    <Sparkles aria-hidden="true" />
                    <span>{t("copilot.usageEmpty")}</span>
                  </div>
                )
              )}

              {/* Banner de Consulta Autorizada */}
              <div className={styles.modalSecurityNotice}>
                <ShieldCheck aria-hidden="true" />
                <p>{t("copilot.usageSecurityNotice")}</p>
              </div>
            </div>

            <div className={styles.modalFooter}>
              <button
                type="button"
                className="button primary"
                onClick={() => setShowUsageModal(false)}
              >
                {t("common.close")}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Pop up modal armónico y cálido de confirmación para eliminar conversación */}
      {conversationToDelete && (
        <div className={styles.modalBackdrop} onClick={() => setConversationToDelete(null)}>
          <div
            className={styles.confirmDialog}
            onClick={(e) => e.stopPropagation()}
          >
            <div className={styles.confirmHeader}>
              <div className={styles.confirmIconDisc}>
                <Trash2 aria-hidden="true" />
              </div>
              <div className={styles.confirmTitles}>
                <h3>{t("copilot.confirmDeleteTitle")}</h3>
                <p>
                  {t("copilot.confirmDeleteMessage", { title: conversationToDelete.title })}
                </p>
              </div>
            </div>

            <div className={styles.confirmActions}>
              <button
                type="button"
                className="button secondary"
                onClick={() => setConversationToDelete(null)}
                disabled={deleteConversation.isPending}
              >
                {t("common.cancel")}
              </button>
              <button
                type="button"
                className={styles.deleteConfirmButton}
                onClick={() => {
                  if (conversationToDelete) {
                    const targetId = conversationToDelete.conversation_id;
                    setConversationToDelete(null);
                    deleteConversation.mutate(targetId);
                  }
                }}
                disabled={deleteConversation.isPending}
              >
                {deleteConversation.isPending ? t("common.loading") : t("copilot.confirmDeleteButton")}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

function formatInlineContent(
  text: string,
  sourceByReference: Map<string, CopilotAnswer["sources"][number]>,
  onOpenSighting: (sightingId: string) => void
): ReactNode[] {
  const tokens = text.split(/(\[?obs-[A-Za-z0-9-]+\]?|\*\*[^*]+\*\*|\*[^*\n]+\*|_[^_\n]+_|`[^`]+`)/gi);

  return tokens.map((token, index) => {
    if (!token) return null;

    // Cita autorizada [obs-XXXX]
    if (/^\[?obs-[A-Za-z0-9-]+\]?$/i.test(token)) {
      const reference = token.replaceAll("[", "").replaceAll("]", "").toLowerCase();
      const source = sourceByReference.get(reference);
      if (source) {
        return (
          <button
            className={styles.inlineCitationPill}
            type="button"
            key={index}
            onClick={() => onOpenSighting(source.sighting_id)}
            title={`${source.species_common_name} (${source.observation_reference})`}
          >
            <span className={styles.citationIcon}><Leaf /></span>
            <span className={styles.citationText}>
              {source.species_common_name} · {source.observation_reference.toUpperCase()}
            </span>
          </button>
        );
      }
      return <span key={index} className={styles.inlineReferenceUnlinked}>{token.startsWith("[") ? token : `[${token}]`}</span>;
    }

    // Negrita **texto**
    if (token.startsWith("**") && token.endsWith("**") && token.length >= 4) {
      const inner = token.slice(2, -2);
      return (
        <strong key={index} className={styles.boldText}>
          {formatInlineContent(inner, sourceByReference, onOpenSighting)}
        </strong>
      );
    }

    // Cursiva *texto* (un asterisco)
    if (token.startsWith("*") && token.endsWith("*") && token.length >= 2 && !token.startsWith("**")) {
      const inner = token.slice(1, -1);
      return (
        <em key={index} className={styles.italicText}>
          {formatInlineContent(inner, sourceByReference, onOpenSighting)}
        </em>
      );
    }

    // Cursiva _texto_
    if (token.startsWith("_") && token.endsWith("_") && token.length >= 2) {
      const inner = token.slice(1, -1);
      return (
        <em key={index} className={styles.italicText}>
          {formatInlineContent(inner, sourceByReference, onOpenSighting)}
        </em>
      );
    }

    // Código en línea `codigo`
    if (token.startsWith("`") && token.endsWith("`") && token.length >= 2) {
      return <code key={index} className={styles.inlineCode}>{token.slice(1, -1)}</code>;
    }

    return <Fragment key={index}>{token}</Fragment>;
  });
}

function FormattedAnswer({
  text,
  sources,
  onOpenSighting,
}: {
  text: string;
  sources: CopilotAnswer["sources"];
  onOpenSighting: (sightingId: string) => void;
}) {
  const sourceByReference = useMemo(
    () => new Map(sources.map((source) => [source.observation_reference.toLowerCase(), source])),
    [sources]
  );

  const lines = text.trim().split("\n");
  const blocks: ReactNode[] = [];
  let currentList: string[] = [];

  function flushList() {
    if (currentList.length > 0) {
      const listItems = [...currentList];
      currentList = [];
      blocks.push(
        <ul key={`list-${blocks.length}`} className={styles.answerList}>
          {listItems.map((item, idx) => (
            <li key={idx}>
              {formatInlineContent(item, sourceByReference, onOpenSighting)}
            </li>
          ))}
        </ul>
      );
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i].trim();
    if (!rawLine) {
      flushList();
      continue;
    }

    // Encabezado H2: ## Título
    if (/^##\s+/.test(rawLine)) {
      flushList();
      const content = rawLine.replace(/^##\s+/, "");
      blocks.push(
        <h3 key={`h2-${blocks.length}`} className={styles.answerHeading2}>
          {formatInlineContent(content, sourceByReference, onOpenSighting)}
        </h3>
      );
      continue;
    }

    // Encabezado H3 / H4: ### Título o #### Título
    if (/^#{3,4}\s+/.test(rawLine)) {
      flushList();
      const content = rawLine.replace(/^#{3,4}\s+/, "");
      blocks.push(
        <h4 key={`h3-${blocks.length}`} className={styles.answerHeading3}>
          {formatInlineContent(content, sourceByReference, onOpenSighting)}
        </h4>
      );
      continue;
    }

    // Elemento de lista: - item, * item, • item, 1. item
    if (/^([-•*]|\d+\.)\s+/.test(rawLine)) {
      const content = rawLine.replace(/^([-•*]|\d+\.)\s+/, "");
      currentList.push(content);
      continue;
    }

    // Párrafo normal
    flushList();
    blocks.push(
      <p key={`p-${blocks.length}`} className={styles.answerParagraph}>
        {formatInlineContent(rawLine, sourceByReference, onOpenSighting)}
      </p>
    );
  }

  flushList();

  return <div className={styles.formattedAnswer}>{blocks}</div>;
}