import { FormEvent, Fragment, KeyboardEvent, type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  Activity,
  AlertCircle,
  Ban,
  Check,
  CheckCheck,
  Clock,
  Clock3,
  Leaf,
  MessageCircle,
  MessageSquare,
  MoreVertical,
  Pencil,
  Search,
  Send,
  Settings,
  ShieldCheck,
  Sparkles,
  Trash2,
  UserPlus,
  Users,
  X,
  Zap,
} from "lucide-react";

import { useQuery } from "@tanstack/react-query";

import type { CopilotUsageResponse, Researcher } from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";
import { AnimalAvatar } from "../../shared/components/AnimalAvatar";
import styles from "./ChatPanel.module.css";

type Citation = {
  type: string;
  reference: string;
  id?: string;
};

type Channel = {
  channel_id: string;
  channel_type: "direct" | "group";
  name: string | null;
  display_name: string;
  message_count: number;
  unread_count: number;
  last_message_at: string | null;
  created_at: string;
  updated_at: string;
};

type Message = {
  message_id: string;
  channel_id: string;
  author_id: string | null;
  author_name: string;
  sender_role: "user" | "copilot";
  message_text: string;
  is_edited: boolean;
  is_deleted: boolean;
  created_at: string;
  read_count: number;
  status?: "pending" | "sent" | "failed";
  citations: Citation[];
};


type CopilotReply = {
  answer: string;
  model_name: string;
  sources: Citation[];
};

type DirectoryResponse = {
  items: Researcher[];
};

function formatInlineContent(
  text: string,
  sourceByReference: Map<string, Citation>,
  onOpenSighting?: (sightingId: string) => void
): ReactNode[] {
  const tokens = text.split(/(@copilot\b|\[?obs-[A-Za-z0-9-]+\]?|\*\*[^*]+\*\*|\*[^*\n]+\*|_[^_\n]+_|`[^`]+`)/gi);

  return tokens.map((token, index) => {
    if (!token) return null;

    // @copilot mention
    if (token.toLowerCase() === "@copilot") {
      return (
        <span key={index} className={styles.copilotMentionBadge}>
          <Sparkles aria-hidden="true" />
          @copilot
        </span>
      );
    }

    // Cita autorizada [obs-XXXX]
    if (/^\[?obs-[A-Za-z0-9-]+\]?$/i.test(token)) {
      const reference = token.replaceAll("[", "").replaceAll("]", "").toLowerCase();
      const source = sourceByReference.get(reference);
      if (source && source.id && onOpenSighting) {
        return (
          <button
            className={styles.inlineCitationPill}
            type="button"
            key={index}
            onClick={() => onOpenSighting(source.id!)}
            title={`Abrir registro ${source.reference}`}
          >
            <span className={styles.citationIcon}><Leaf /></span>
            <span className={styles.citationText}>
              {source.reference.toUpperCase()}
            </span>
          </button>
        );
      }
      return (
        <span key={index} className={styles.inlineReferenceUnlinked}>
          {token.startsWith("[") ? token : `[${token}]`}
        </span>
      );
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

    // Cursiva *texto*
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

    // Código `code`
    if (token.startsWith("`") && token.endsWith("`") && token.length >= 2) {
      return (
        <code key={index} className={styles.inlineCode}>
          {token.slice(1, -1)}
        </code>
      );
    }

    return <Fragment key={index}>{token}</Fragment>;
  });
}

function formatChatMessage(text: string): ReactNode[] {
  return text.split(/(@copilot\b)/gi).map((token, index) =>
    token.toLowerCase() === "@copilot" ? (
      <span key={index} className={styles.inlineCopilotMention}>
        <Sparkles aria-hidden="true" />
        @copilot
      </span>
    ) : (
      <Fragment key={index}>{token}</Fragment>
    ),
  );
}

function FormattedAnswer({
  text,
  citations,
  onOpenSighting,
}: {
  text: string;
  citations: Citation[];
  onOpenSighting?: (sightingId: string) => void;
}) {
  const sourceByReference = useMemo(
    () => new Map(citations.map((s) => [s.reference.toLowerCase(), s])),
    [citations]
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

    // Encabezado H3: ### Título o #### Título
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

    // Listas: - item, * item, • item, 1. item
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

export function ChatPanel({
  api,
  researcher,
  onOpenSighting,
}: {
  api: ApiClient;
  researcher: Researcher;
  onOpenSighting?: (sightingId: string) => void;
}) {
  const { t } = useTranslation();
  const [channels, setChannels] = useState<Channel[]>([]);
  const [contacts, setContacts] = useState<Researcher[]>([]);
  const [activeChannelId, setActiveChannelId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [isCopilotThinking, setIsCopilotThinking] = useState(false);
  const [showUsageModal, setShowUsageModal] = useState(false);
  const [activeMenuMessageId, setActiveMenuMessageId] = useState<string | null>(null);
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editDraft, setEditDraft] = useState("");
  const [, setError] = useState<string | null>(null);

  // Estados para creación de grupos
  const [showCreateGroupModal, setShowCreateGroupModal] = useState(false);
  const [groupName, setGroupName] = useState("");
  const [selectedGroupMemberIds, setSelectedGroupMemberIds] = useState<string[]>([]);
  const [groupMemberSearch, setGroupMemberSearch] = useState("");
  const [isCreatingGroup, setIsCreatingGroup] = useState(false);


  const transcriptEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Consulta de consumo del copiloto para el modal de la tuerquita
  const usageQuery = useQuery({
    queryKey: ["chat-copilot-usage"],
    queryFn: () => api.get<CopilotUsageResponse>("/v1/copilot/usage"),
    enabled: showUsageModal,
  });

  // Cerrar menú de opciones al hacer click afuera
  useEffect(() => {
    function handleClickOutside() {
      if (activeMenuMessageId) setActiveMenuMessageId(null);
    }
    window.addEventListener("click", handleClickOutside);
    return () => window.removeEventListener("click", handleClickOutside);
  }, [activeMenuMessageId]);


  // Cargar canales y directorio de investigadores
  useEffect(() => {
    let isMounted = true;
    async function loadInitialData() {
      try {
        const [channelsData, directoryData] = await Promise.all([
          api.get<Channel[]>("/v1/chat/channels"),
          api.get<DirectoryResponse>("/v1/researchers"),
        ]);
        if (!isMounted) return;
        setChannels(channelsData);
        const otherResearchers = directoryData.items.filter(
          (c) => c.researcher_id !== researcher.researcher_id
        );
        setContacts(otherResearchers);
        if (channelsData.length > 0 && !activeChannelId) {
          setActiveChannelId(channelsData[0].channel_id);
        }
      } catch {
        if (isMounted) setError(t("errors.network"));
      }
    }
    void loadInitialData();
    return () => {
      isMounted = false;
    };
  }, [api, researcher.researcher_id, t, activeChannelId]);

  // Cargar y sincronizar mensajes del canal activo con polling reactivo
  useEffect(() => {
    if (!activeChannelId) {
      setMessages([]);
      return;
    }

    let isMounted = true;
    async function fetchMessages() {
      try {
        const items = await api.get<Message[]>(
          `/v1/chat/channels/${activeChannelId}/messages`
        );
        if (!isMounted) return;
        setMessages(
          [...items].reverse().map((m) => ({ ...m, status: "sent" }))
        );
        setChannels((previous) => previous.map((channel) =>
          channel.channel_id === activeChannelId ? { ...channel, unread_count: 0 } : channel
        ));
      } catch {
        // Silencioso en polling
      }
    }

    void fetchMessages();
    const interval = setInterval(() => {
      void fetchMessages();
    }, 4000);

    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, [api, activeChannelId]);

  // Scroll automático al final al recibir nuevos mensajes
  useEffect(() => {
    transcriptEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isCopilotThinking]);

  // Encontrar el contacto correspondiente para un canal directo
  const activeChannel = useMemo(() => {
    return channels.find((c) => c.channel_id === activeChannelId);
  }, [channels, activeChannelId]);

  const activeContact = useMemo(() => {
    if (!activeChannel || activeChannel.channel_type !== "direct") return null;
    return contacts.find(
      (c) =>
        c.full_name.toLowerCase() ===
        activeChannel.display_name.toLowerCase()
    );
  }, [activeChannel, contacts]);

  // Filtrado de contactos y canales por búsqueda
  const filteredContacts = useMemo(() => {
    if (!searchQuery.trim()) return contacts;
    const q = searchQuery.toLowerCase();
    return contacts.filter(
      (c) =>
        c.full_name.toLowerCase().includes(q) ||
        c.role_title.toLowerCase().includes(q)
    );
  }, [contacts, searchQuery]);

  const filteredChannels = useMemo(() => {
    if (!searchQuery.trim()) return channels;
    const q = searchQuery.toLowerCase();
    return channels.filter((c) =>
      c.display_name.toLowerCase().includes(q)
    );
  }, [channels, searchQuery]);

  // Filtrado de investigadores dentro del modal de nuevo grupo
  const filteredGroupContacts = useMemo(() => {
    if (!groupMemberSearch.trim()) return contacts;
    const q = groupMemberSearch.toLowerCase();
    return contacts.filter(
      (c) =>
        c.full_name.toLowerCase().includes(q) ||
        c.role_title.toLowerCase().includes(q)
    );
  }, [contacts, groupMemberSearch]);

  function toggleGroupMember(memberId: string) {
    setSelectedGroupMemberIds((prev) =>
      prev.includes(memberId)
        ? prev.filter((id) => id !== memberId)
        : [...prev, memberId]
    );
  }

  async function handleCreateGroup(e: FormEvent) {
    e.preventDefault();
    const name = groupName.trim();
    if (!name || selectedGroupMemberIds.length === 0 || isCreatingGroup) return;

    setIsCreatingGroup(true);
    setError(null);
    try {
      const channel = await api.post<Channel>("/v1/chat/channels", {
        channel_type: "group",
        name: name,
        member_ids: selectedGroupMemberIds,
      });

      setChannels((prev) => [
        channel,
        ...prev.filter((c) => c.channel_id !== channel.channel_id),
      ]);
      setActiveChannelId(channel.channel_id);
      setShowCreateGroupModal(false);
      setGroupName("");
      setSelectedGroupMemberIds([]);
      setGroupMemberSearch("");
    } catch {
      setError(t("errors.network"));
    } finally {
      setIsCreatingGroup(false);
    }
  }

  // Iniciar o abrir conversación directa
  async function openDirectChat(contact: Researcher) {

    try {
      setError(null);
      const channel = await api.post<Channel>("/v1/chat/channels", {
        channel_type: "direct",
        member_ids: [contact.researcher_id],
      });
      setChannels((prev) => {
        const exists = prev.some((c) => c.channel_id === channel.channel_id);
        return exists ? prev : [channel, ...prev];
      });
      setActiveChannelId(channel.channel_id);
    } catch {
      setError(t("errors.network"));
    }
  }

  // Enviar mensaje e invocar @copilot si está presente
  async function handleSendMessage(e?: FormEvent) {

    if (e) e.preventDefault();
    const text = draft.trim();
    if (!activeChannelId || !text || isSending) return;

    const tempId = crypto.randomUUID();
    const isCopilotMention = /^@copilot\b/i.test(text);

    const pendingMsg: Message = {
      message_id: tempId,
      channel_id: activeChannelId,
      author_id: researcher.researcher_id,
      author_name: researcher.full_name,
      sender_role: "user",
      message_text: text,
      is_edited: false,
      is_deleted: false,
      created_at: new Date().toISOString(),
      read_count: 1,
      status: "pending",
      citations: [],
    };

    setMessages((prev) => [...prev, pendingMsg]);
    setDraft("");
    setIsSending(true);

    try {
      const sentMsg = await api.post<Message>(
        `/v1/chat/channels/${activeChannelId}/messages`,
        { message_text: text }
      );

      setMessages((prev) =>
        prev.map((m) =>
          m.message_id === tempId ? { ...sentMsg, status: "sent" } : m
        )
      );

      if (isCopilotMention) {
        setIsCopilotThinking(true);
        const question = text.replace(/^@copilot\b\s*/i, "");
        const copilotResponse = await api.post<CopilotReply>(
          `/v1/chat/channels/${activeChannelId}/copilot`,
          { question: question || text }
        );

        const copilotMsg: Message = {
          message_id: crypto.randomUUID(),
          channel_id: activeChannelId,
          author_id: null,
          author_name: "Copiloto Bioma",
          sender_role: "copilot",
          message_text: copilotResponse.answer,
          is_edited: false,
          is_deleted: false,
          created_at: new Date().toISOString(),
          read_count: 1,
          status: "sent",
          citations: copilotResponse.sources || [],
        };

        setMessages((prev) => [...prev, copilotMsg]);
      }
    } catch {
      setMessages((prev) =>
        prev.map((m) =>
          m.message_id === tempId ? { ...m, status: "failed" } : m
        )
      );
      setError(t("errors.network"));
    } finally {
      setIsSending(false);
      setIsCopilotThinking(false);
    }
  }

  // Editar mensaje propio
  async function submitEditMessage(messageId: string) {
    const text = editDraft.trim();
    if (!text) return;
    try {
      await api.patch(`/v1/chat/messages/${messageId}`, { message_text: text });
      setMessages((prev) =>
        prev.map((m) =>
          m.message_id === messageId
            ? { ...m, message_text: text, is_edited: true }
            : m
        )
      );
      setEditingMessageId(null);
      setEditDraft("");
    } catch {
      setError(t("errors.network"));
    }
  }

  // Eliminar mensaje propio (soft delete estilo WhatsApp)
  async function submitDeleteMessage(messageId: string) {
    try {
      await api.delete(`/v1/chat/messages/${messageId}`);
      setMessages((prev) =>
        prev.map((m) =>
          m.message_id === messageId
            ? { ...m, message_text: "Este mensaje fue eliminado", is_deleted: true }
            : m
        )
      );
      setActiveMenuMessageId(null);
    } catch {
      setError(t("errors.network"));
    }
  }


  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void handleSendMessage();
    }
  }

  return (
    <section className={styles.container}>
      {/* 1. Panel Lateral Izquierdo: Investigadores y Canales */}
      <aside className={styles.sidebar}>
        <div className={styles.sidebarHeader}>
          <div className={styles.sidebarTitle}>
            <MessageSquare aria-hidden="true" />
            <span>{t("chat.sidebarTitle")}</span>
          </div>
          <div className={styles.searchBox}>
            <Search aria-hidden="true" />
            <input
              type="text"
              className={styles.searchInput}
              placeholder={t("chat.searchPlaceholder")}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
        </div>

        <div className={styles.contactsList}>
          {/* Sección de Investigadores */}
          <div className={styles.sectionLabel}>{t("chat.researchers")}</div>
          {filteredContacts.map((contact) => {
            const isContactActive =
              activeChannel?.channel_type === "direct" &&
              activeChannel.display_name.toLowerCase() ===
                contact.full_name.toLowerCase();

            return (
              <button
                key={contact.researcher_id}
                type="button"
                className={`${styles.contactItem} ${
                  isContactActive ? styles.active : ""
                }`}
                onClick={() => void openDirectChat(contact)}
              >
                <AnimalAvatar
                  avatarKey={contact.animal_avatar_key}
                  seed={contact.researcher_id}
                />
                <div className={styles.contactInfo}>
                  <span className={styles.contactName}>{contact.full_name}</span>
                  <span className={styles.contactRole}>{contact.role_title}</span>
                </div>
              </button>
            );
          })}

          {/* Sección de Canales de Campo */}
          <div className={styles.sectionHeaderRow}>
            <div className={styles.sectionLabel}>{t("chat.channels")}</div>
            <button
              type="button"
              className={styles.createGroupBtn}
              onClick={() => setShowCreateGroupModal(true)}
              title={t("chat.createGroup")}
            >
              <UserPlus aria-hidden="true" />
              <span>{t("chat.createGroup")}</span>
            </button>
          </div>

          {filteredChannels.filter((c) => c.channel_type === "group").map((channel) => (
            <button
              key={channel.channel_id}
              type="button"
              className={`${styles.contactItem} ${
                channel.channel_id === activeChannelId ? styles.active : ""
              }`}
              onClick={() => setActiveChannelId(channel.channel_id)}
            >
              <div className={styles.groupChannelIcon}>
                <Users aria-hidden="true" />
              </div>
              <div className={styles.contactInfo}>
                <span className={styles.contactName}>
                  {channel.display_name}
                </span>
                <span className={styles.contactRole}>
                  {channel.message_count} {channel.message_count === 1 ? "mensaje" : "mensajes"}
                </span>
              </div>
              {channel.unread_count > 0 && (
                <span className={styles.messageBadge}>
                  {channel.unread_count}
                </span>
              )}
            </button>
          ))}

        </div>
      </aside>

      {/* 2. Área Central de Chat */}
      <main className={styles.chatArea}>
        {/* Cabecera del chat con información del contacto y tuerquita de consumo */}
        <header className={styles.header}>
          <div className={styles.headerLeft}>
            {activeContact ? (
              <AnimalAvatar
                avatarKey={activeContact.animal_avatar_key}
                seed={activeContact.researcher_id}
              />
            ) : activeChannel?.channel_type === "group" ? (
              <Users
                aria-hidden="true"
                style={{
                  width: "2rem",
                  height: "2rem",
                  color: "var(--sage)",
                  padding: ".4rem",
                  background: "var(--sage-soft)",
                  borderRadius: "50%",
                }}
              />
            ) : (
              <MessageCircle
                aria-hidden="true"
                style={{ width: "1.8rem", height: "1.8rem", color: "var(--sage)" }}
              />
            )}
            <div className={styles.headerDetails}>
              <h2 className={styles.headerTitle}>
                {activeChannel?.display_name || t("chat.selectPrompt")}
              </h2>
              <span className={styles.headerSubtitle}>
                <ShieldCheck aria-hidden="true" />
                {t("chat.protectedChannel")}
              </span>
            </div>
          </div>

          {/* Botón de la tuerquita (Consumo de Copiloto) */}
          <button
            type="button"
            className={styles.settingsButton}
            onClick={() => setShowUsageModal(true)}
            title={t("chat.usageTitle")}
          >
            <Settings aria-hidden="true" />
          </button>
        </header>

        {/* Hilo de mensajes */}
        <div className={styles.transcript}>
          {!activeChannelId && (
            <div className={styles.emptyChat}>
              <MessageCircle aria-hidden="true" />
              <h3>{t("chat.selectPrompt")}</h3>
              <p>{t("chat.selectPromptDesc")}</p>
            </div>
          )}

          {activeChannelId && messages.length === 0 && (
            <div className={styles.emptyChat}>
              <Sparkles aria-hidden="true" />
              <h3>{t("copilot.welcome")}</h3>
              <p>{t("chat.copilotHint")}</p>
            </div>
          )}

          {messages.map((message) => {
            const isOwn = message.author_id === researcher.researcher_id;
            const isCopilot = message.sender_role === "copilot";
            const isEditingThis = editingMessageId === message.message_id;
            const isMenuOpen = activeMenuMessageId === message.message_id;

            return (
              <div
                key={message.message_id}
                className={`${styles.messageRow} ${
                  isOwn ? styles.own : isCopilot ? styles.copilot : styles.other
                }`}
              >
                {!isOwn && !isCopilot && (
                  <AnimalAvatar
                    avatarKey="avatar_ocelot"
                    seed={message.author_id || "contact"}
                  />
                )}

                <div
                  className={`${styles.bubble} ${
                    message.is_deleted ? styles.deletedBubble : ""
                  }`}
                >
                  {/* Acciones en hover (3 puntitos) dentro de la burbuja arriba a la derecha */}
                  {isOwn && !message.is_deleted && !isEditingThis && (
                    <div className={styles.messageActions} onClick={(e) => e.stopPropagation()}>
                      <button
                        type="button"
                        className={styles.actionButton}
                        onClick={() =>
                          setActiveMenuMessageId(isMenuOpen ? null : message.message_id)
                        }
                        title="Opciones de mensaje"
                      >
                        <MoreVertical aria-hidden="true" />
                      </button>
                      {isMenuOpen && (
                        <div className={styles.actionMenu}>
                          <button
                            type="button"
                            className={styles.actionMenuItem}
                            onClick={() => {
                              setEditingMessageId(message.message_id);
                              setEditDraft(message.message_text);
                              setActiveMenuMessageId(null);
                            }}
                          >
                            <Pencil aria-hidden="true" />
                            <span>Editar</span>
                          </button>
                          <button
                            type="button"
                            className={`${styles.actionMenuItem} ${styles.danger}`}
                            onClick={() => void submitDeleteMessage(message.message_id)}
                          >
                            <Trash2 aria-hidden="true" />
                            <span>Eliminar</span>
                          </button>
                        </div>
                      )}
                    </div>
                  )}

                  <div className={styles.bubbleAuthor}>
                    {isCopilot ? (
                      <>
                        <Sparkles aria-hidden="true" />
                        <span>{message.author_name}</span>
                      </>
                    ) : (
                      <span>{isOwn ? "Tú" : message.author_name}</span>
                    )}
                  </div>


                  {/* 1. Modo mensaje eliminado (WhatsApp style) */}
                  {message.is_deleted ? (
                    <p className={styles.deletedText}>
                      <Ban aria-hidden="true" />
                      <span>Este mensaje fue eliminado</span>
                    </p>
                  ) : isEditingThis ? (
                    /* 2. Modo editor inline */
                    <div className={styles.inlineEditor}>
                      <textarea
                        className={styles.inlineTextarea}
                        value={editDraft}
                        onChange={(e) => setEditDraft(e.target.value)}
                        rows={2}
                      />
                      <div className={styles.inlineActions}>
                        <button
                          type="button"
                          className={styles.inlineCancel}
                          onClick={() => setEditingMessageId(null)}
                        >
                          Cancelar
                        </button>
                        <button
                          type="button"
                          className={styles.inlineSave}
                          onClick={() => void submitEditMessage(message.message_id)}
                        >
                          Guardar
                        </button>
                      </div>
                    </div>
                  ) : isCopilot ? (
                    /* 3. Formateo enriquecido del copiloto */
                    <FormattedAnswer
                      text={message.message_text}
                      citations={message.citations || []}
                      onOpenSighting={onOpenSighting}
                    />
                  ) : (
                    /* 4. Mensaje de texto normal */
                    <p className={styles.bubbleText}>{formatChatMessage(message.message_text)}</p>
                  )}

                  {/* Tarjetas de fuentes autorizadas al pie de la respuesta del copiloto */}
                  {isCopilot &&
                    !message.is_deleted &&
                    message.citations &&
                    message.citations.length > 0 && (
                      <div className={styles.citations}>
                        <div className={styles.citationsLabel}>
                          Fuentes autorizadas
                        </div>
                        {message.citations.map((c, i) => (
                          <button
                            key={`${c.reference}-${i}`}
                            type="button"
                            className={styles.citationBadge}
                            onClick={() => {
                              if (c.type === "sighting" && c.id && onOpenSighting) {
                                onOpenSighting(c.id);
                              }
                            }}
                            title={`Abrir registro ${c.reference}`}
                          >
                            <strong>{c.reference}</strong>
                          </button>
                        ))}
                      </div>
                    )}

                  <div className={styles.bubbleMeta}>
                    {/* Indicador de editado con lápiz (estilo WhatsApp) */}
                    {message.is_edited && !message.is_deleted && (
                      <span className={styles.editedTag} title="Mensaje editado">
                        <Pencil aria-hidden="true" />
                        <span>Editado</span>
                      </span>
                    )}

                    <time>
                      {new Date(message.created_at).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </time>
                    {isOwn && !message.is_deleted && (
                      <>
                        {message.status === "pending" && (
                          <Clock aria-hidden="true" />
                        )}
                        {message.status === "sent" && (
                          <CheckCheck aria-hidden="true" />
                        )}
                        {message.status === "failed" && (
                          <AlertCircle
                            aria-hidden="true"
                            style={{ color: "#c0392b" }}
                          />
                        )}
                      </>
                    )}
                  </div>
                </div>
              </div>
            );
          })}


          {/* Animación cuando el copiloto está pensando */}
          {isCopilotThinking && (
            <div className={`${styles.messageRow} ${styles.copilot}`}>
              <div className={styles.bubble}>
                <div className={styles.bubbleAuthor}>
                  <Sparkles aria-hidden="true" />
                  <span>Copiloto Bioma</span>
                </div>
                <div className={styles.typing}>
                  <i />
                  <i />
                  <i />
                </div>
              </div>
            </div>
          )}

          <div ref={transcriptEndRef} />
        </div>

        {/* Barra de Composición */}
        <form className={styles.composer} onSubmit={(e) => void handleSendMessage(e)}>
          <div className={styles.inputWrapper}>
            <textarea
              ref={textareaRef}
              className={styles.textarea}
              placeholder={t("chat.placeholder")}
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={!activeChannelId || isSending}
              rows={1}
            />
            <button
              type="submit"
              className={styles.sendButton}
              disabled={!activeChannelId || !draft.trim() || isSending}
              title={t("copilot.ask")}
            >
              <Send aria-hidden="true" />
            </button>
          </div>
          <div className={styles.composerHint}>
            <span>{t("chat.enterHint")}</span>
            <span className={styles.copilotTag}>
              <Sparkles aria-hidden="true" style={{ width: ".75rem", height: ".75rem" }} />
              {t("chat.copilotHint")}
            </span>
          </div>
        </form>
      </main>

      {/* 3. Modal de Consumo del Copiloto (Tuerquita) */}
      {showUsageModal && (
        <div
          className={styles.modalOverlay}
          onClick={() => setShowUsageModal(false)}
        >
          <div
            className={styles.usageModal}
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
          >
            <div className={styles.modalHeader}>
              <div>
                <h3>{t("chat.usageTitle")}</h3>
                <p style={{ margin: 0, fontSize: ".8rem", color: "var(--muted)" }}>
                  {t("chat.usageSubtitle")}
                </p>
              </div>
              <button
                type="button"
                className={styles.closeButton}
                onClick={() => setShowUsageModal(false)}
              >
                <X aria-hidden="true" />
              </button>
            </div>

            <div className={styles.statsGrid}>
              <div className={styles.statCard}>
                <Activity aria-hidden="true" />
                <span className={styles.statValue}>
                  {usageQuery.data?.item?.total_queries ?? 0}
                </span>
                <span className={styles.statLabel}>{t("chat.queries")}</span>
              </div>

              <div className={styles.statCard}>
                <Zap aria-hidden="true" />
                <span className={styles.statValue}>
                  {usageQuery.data?.item?.total_tokens?.toLocaleString() ?? 0}
                </span>
                <span className={styles.statLabel}>{t("chat.tokens")}</span>
              </div>

              <div className={styles.statCard}>
                <Clock3 aria-hidden="true" />
                <span className={styles.statValue} style={{ fontSize: "1rem" }}>
                  {usageQuery.data?.item?.last_query_at
                    ? new Date(usageQuery.data.item.last_query_at).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })
                    : "—"}
                </span>
                <span className={styles.statLabel}>{t("chat.lastQuery")}</span>
              </div>

              <div className={styles.statCard}>
                <ShieldCheck aria-hidden="true" />
                <span className={styles.statValue} style={{ fontSize: "1rem" }}>
                  Nivel {researcher.accreditation_level}
                </span>
                <span className={styles.statLabel}>Nivel de acceso</span>
              </div>
            </div>


            <div className={styles.modalNotice}>
              <ShieldCheck aria-hidden="true" />
              <span>{t("chat.securityNotice")}</span>
            </div>
          </div>
        </div>
      )}

      {/* 4. Modal de Creación de Grupo de Investigación */}
      {showCreateGroupModal && (
        <div
          className={styles.modalOverlay}
          onClick={() => setShowCreateGroupModal(false)}
        >
          <div
            className={styles.createGroupCard}
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
          >
            <div className={styles.modalHeader}>
              <div className={styles.modalTitleRow}>
                <div className={styles.modalIconWrap}>
                  <Users aria-hidden="true" />
                </div>
                <div>
                  <h3 className={styles.modalTitleText}>{t("chat.createGroupTitle")}</h3>
                  <p className={styles.modalSubtitleText}>{t("chat.createGroupSubtitle")}</p>
                </div>
              </div>
              <button
                type="button"
                className={styles.closeButton}
                onClick={() => setShowCreateGroupModal(false)}
                aria-label={t("common.close")}
              >
                <X aria-hidden="true" />
              </button>
            </div>

            <form onSubmit={handleCreateGroup} className={styles.createGroupForm}>
              <div className={styles.formGroup}>
                <label className={styles.formLabel}>
                  <span>{t("chat.groupName")}</span>
                  <span className={styles.requiredStar}>*</span>
                </label>
                <input
                  type="text"
                  className={styles.formInput}
                  placeholder={t("chat.groupNamePlaceholder")}
                  value={groupName}
                  onChange={(e) => setGroupName(e.target.value)}
                  maxLength={80}
                  required
                  autoFocus
                />
              </div>

              <div className={styles.formGroup}>
                <div className={styles.membersHeaderRow}>
                  <label className={styles.formLabel}>
                    <span>{t("chat.selectMembers")}</span>
                    <span className={styles.requiredStar}>*</span>
                  </label>
                  <span className={styles.membersCountBadge}>
                    {t("chat.membersCount", { count: selectedGroupMemberIds.length })}
                  </span>
                </div>

                <div className={styles.memberSearchBox}>
                  <Search aria-hidden="true" />
                  <input
                    type="text"
                    className={styles.memberSearchInput}
                    placeholder="Buscar colega por nombre o cargo…"
                    value={groupMemberSearch}
                    onChange={(e) => setGroupMemberSearch(e.target.value)}
                  />
                </div>


                <div className={styles.memberSelectorList}>
                  {filteredGroupContacts.map((contact) => {
                    const isSelected = selectedGroupMemberIds.includes(contact.researcher_id);
                    return (
                      <div
                        key={contact.researcher_id}
                        className={`${styles.memberSelectItem} ${isSelected ? styles.selected : ""}`}
                        onClick={() => toggleGroupMember(contact.researcher_id)}
                      >
                        <div className={styles.checkboxContainer}>
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {}}
                            className={styles.customCheckbox}
                            aria-label={`Seleccionar ${contact.full_name}`}
                          />
                        </div>
                        <AnimalAvatar
                          avatarKey={contact.animal_avatar_key}
                          seed={contact.researcher_id}
                        />
                        <div className={styles.memberSelectInfo}>
                          <span className={styles.memberSelectName}>{contact.full_name}</span>
                          <span className={styles.memberSelectRole}>{contact.role_title}</span>
                        </div>
                        <span className={styles.memberLevelBadge}>
                          Nivel {contact.accreditation_level}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>

              {selectedGroupMemberIds.length === 0 && (
                <p className={styles.hintNotice}>
                  <AlertCircle aria-hidden="true" />
                  <span>{t("chat.minMembersHint")}</span>
                </p>
              )}

              <div className={styles.modalActions}>
                <button
                  type="button"
                  className={styles.cancelBtn}
                  onClick={() => setShowCreateGroupModal(false)}
                >
                  {t("common.cancel")}
                </button>
                <button
                  type="submit"
                  className={styles.submitBtn}
                  disabled={!groupName.trim() || selectedGroupMemberIds.length === 0 || isCreatingGroup}
                >
                  {isCreatingGroup ? (
                    t("common.loading")
                  ) : (
                    <>
                      <Check aria-hidden="true" />
                      {t("chat.createGroupSubmit")}
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </section>
  );
}
