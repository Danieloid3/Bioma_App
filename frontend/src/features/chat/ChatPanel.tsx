import { FormEvent, Fragment, KeyboardEvent, type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
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

import type { ChatChannel, CopilotUsageResponse, Researcher } from "../../domain/contracts";
import { ApiClient } from "../../shared/api/client";
import { AnimalAvatar } from "../../shared/components/AnimalAvatar";
import styles from "./ChatPanel.module.css";

type Citation = {
  type: string;
  reference: string;
  id?: string;
  label?: string;
};

type SidebarFilter = "chats" | "groups";

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
  delivered_count: number;
  status?: "pending" | "sent" | "failed";
  citations: Citation[];
};


type DirectoryResponse = {
  items: Researcher[];
};

type ChannelMember = Researcher;

type ChatRealtimeEvent = {
  type: "channel.created" | "channel.updated" | "message.created" | "message.updated" | "message.deleted" | "message.read";
  channel_id: string;
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
              {source.label || source.reference.toUpperCase()}
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
  const [channels, setChannels] = useState<ChatChannel[]>([]);
  const [contacts, setContacts] = useState<Researcher[]>([]);
  const [activeChannelId, setActiveChannelId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [sidebarFilter, setSidebarFilter] = useState<SidebarFilter>("chats");
  const [isSending, setIsSending] = useState(false);
  const [isCopilotThinking, setIsCopilotThinking] = useState(false);
  const [showUsageModal, setShowUsageModal] = useState(false);
  const [showMembersModal, setShowMembersModal] = useState(false);
  const [showAddMembersModal, setShowAddMembersModal] = useState(false);
  const [channelMembers, setChannelMembers] = useState<ChannelMember[]>([]);
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
  const [selectedAdditionalMemberIds, setSelectedAdditionalMemberIds] = useState<string[]>([]);
  const [additionalMemberSearch, setAdditionalMemberSearch] = useState("");


  const transcriptEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const transcriptRef = useRef<HTMLDivElement>(null);
  const shouldStickToBottomRef = useRef(true);
  const showCopilotSuggestion = draft.trim() === "@";

  const refreshChannels = useCallback(async () => {
    const channelsData = await api.get<ChatChannel[]>("/v1/chat/channels");
    setChannels(channelsData);
    setActiveChannelId((current) => current ?? channelsData[0]?.channel_id ?? null);
  }, [api]);

  const refreshActiveMessages = useCallback(async (channelId: string) => {
    const items = await api.get<Message[]>(`/v1/chat/channels/${channelId}/messages`);
    setMessages([...items].reverse().map((message) => ({ ...message, status: "sent" })));
    setChannels((previous) => previous.map((channel) =>
      channel.channel_id === channelId ? { ...channel, unread_count: 0 } : channel
    ));
  }, [api]);

  // Consulta de consumo del copiloto para el modal de la tuerquita
  const usageQuery = useQuery({
    queryKey: ["chat-copilot-usage"],
    queryFn: () => api.get<CopilotUsageResponse>("/v1/copilot/usage"),
    enabled: showUsageModal,
  });

  async function openMembers() {
    if (!activeChannelId) return;
    try {
      setChannelMembers(await api.get<ChannelMember[]>(`/v1/chat/channels/${activeChannelId}/members`));
      setShowMembersModal(true);
    } catch {
      setError(t("errors.network"));
    }
  }

  async function addMembers() {
    if (!activeChannelId || selectedAdditionalMemberIds.length === 0) return;
    try {
      await api.post(`/v1/chat/channels/${activeChannelId}/members`, { member_ids: selectedAdditionalMemberIds });
      setSelectedAdditionalMemberIds([]);
      setAdditionalMemberSearch("");
      setShowAddMembersModal(false);
      await openMembers();
    } catch { setError(t("errors.network")); }
  }

  async function leaveActiveGroup() {
    if (!activeChannelId || activeChannel?.channel_type !== "group") return;
    if (!window.confirm(t("chat.leaveGroupConfirm"))) return;
    try {
      await api.post(`/v1/chat/channels/${activeChannelId}/leave`);
      setShowMembersModal(false);
      setActiveChannelId(null);
      setMessages([]);
      await refreshChannels();
    } catch { setError(t("errors.network")); }
  }

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
          api.get<ChatChannel[]>("/v1/chat/channels"),
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

  // La lectura por REST conserva el cursor, marca leído y aplica RLS.
  useEffect(() => {
    if (!activeChannelId) {
      setMessages([]);
      return;
    }
    const channelId = activeChannelId;

    let isMounted = true;
    async function fetchMessages() {
      try {
        if (!isMounted) return;
        await refreshActiveMessages(channelId);
      } catch {
        // La siguiente invalidación o reconexión reintentará la sincronización.
      }
    }

    void fetchMessages();

    return () => {
      isMounted = false;
    };
  }, [activeChannelId, refreshActiveMessages]);

  // SSE no lleva mensajes: solo invalida y los datos se vuelven a leer por REST + RLS.
  useEffect(() => {
    const controller = new AbortController();
    let retryTimer: number | undefined;
    let stopped = false;

    const reconnect = () => {
      if (!stopped) retryTimer = window.setTimeout(connect, 1500);
    };
    const connect = async () => {
      try {
        await api.stream("/v1/chat/events", (event) => {
          if (event.event !== "chat") return;
          const change = JSON.parse(event.data) as ChatRealtimeEvent;
          if (change.type === "channel.created" || change.type === "channel.updated") {
            void refreshChannels();
            return;
          }
          if (change.channel_id === activeChannelId) {
            void refreshActiveMessages(change.channel_id);
          } else {
            void refreshChannels();
          }
        }, controller.signal);
        reconnect();
      } catch {
        if (!controller.signal.aborted) reconnect();
      }
    };
    void connect();
    return () => {
      stopped = true;
      controller.abort();
      if (retryTimer) window.clearTimeout(retryTimer);
    };
  }, [activeChannelId, api, refreshActiveMessages, refreshChannels]);

  // No interrumpir a quien está leyendo mensajes anteriores.
  useEffect(() => {
    if (shouldStickToBottomRef.current) {
      transcriptEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, isCopilotThinking]);

  function handleTranscriptScroll() {
    const transcript = transcriptRef.current;
    if (!transcript) return;
    shouldStickToBottomRef.current = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 80;
  }

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
    const recentByName = new Map(
      channels
        .filter((channel) => channel.channel_type === "direct")
        .map((channel) => [channel.display_name.toLocaleLowerCase(), channel.last_message_at ? Date.parse(channel.last_message_at) : 0]),
    );
    const ordered = [...contacts].sort((a, b) =>
      (recentByName.get(b.full_name.toLocaleLowerCase()) ?? 0) -
      (recentByName.get(a.full_name.toLocaleLowerCase()) ?? 0),
    );
    if (!searchQuery.trim()) return ordered;
    const q = searchQuery.toLowerCase();
    return ordered.filter(
      (c) =>
        c.full_name.toLowerCase().includes(q) ||
        c.role_title.toLowerCase().includes(q)
    );
  }, [contacts, channels, searchQuery]);

  const filteredChannels = useMemo(() => {
    const ordered = [...channels].sort((a, b) =>
      (a.last_message_at ? Date.parse(a.last_message_at) : Date.parse(a.updated_at)) -
      (b.last_message_at ? Date.parse(b.last_message_at) : Date.parse(b.updated_at)),
    ).reverse();
    if (!searchQuery.trim()) return ordered;
    const q = searchQuery.toLowerCase();
    return ordered.filter((c) =>
      c.display_name.toLowerCase().includes(q)
    );
  }, [channels, searchQuery]);

  const directChannelsByContactName = useMemo(() => new Map(
    channels
      .filter((channel) => channel.channel_type === "direct")
      .map((channel) => [channel.display_name.toLocaleLowerCase(), channel]),
  ), [channels]);

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

  const availableAdditionalMembers = useMemo(() => {
    const query = additionalMemberSearch.trim().toLocaleLowerCase();
    return contacts.filter((contact) => {
      const alreadyInGroup = channelMembers.some((member) => member.researcher_id === contact.researcher_id);
      return !alreadyInGroup && (!query || contact.full_name.toLocaleLowerCase().includes(query) || contact.role_title.toLocaleLowerCase().includes(query));
    });
  }, [additionalMemberSearch, channelMembers, contacts]);

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
      const channel = await api.post<ChatChannel>("/v1/chat/channels", {
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
      const channel = await api.post<ChatChannel>("/v1/chat/channels", {
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
      delivered_count: 1,
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
        await api.post(
          `/v1/chat/channels/${activeChannelId}/copilot`,
          { question: question || text }
        );
        // La respuesta persistida llega por SSE; el historial evita duplicados.
        await refreshActiveMessages(activeChannelId);
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
      requestAnimationFrame(() => textareaRef.current?.focus());
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
      if (showCopilotSuggestion) {
        setDraft("@copilot ");
        return;
      }
      void handleSendMessage();
    }
  }

  function completeCopilotMention() {
    setDraft("@copilot ");
    requestAnimationFrame(() => textareaRef.current?.focus());
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
          <div className={styles.sidebarFilters} role="tablist" aria-label={t("chat.sidebarFilters")}>
            <button
              type="button"
              role="tab"
              aria-selected={sidebarFilter === "chats"}
              className={`${styles.sidebarFilter} ${sidebarFilter === "chats" ? styles.sidebarFilterActive : ""}`}
              onClick={() => setSidebarFilter("chats")}
            >
              <MessageCircle aria-hidden="true" />
              {t("chat.chats")}
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={sidebarFilter === "groups"}
              className={`${styles.sidebarFilter} ${sidebarFilter === "groups" ? styles.sidebarFilterActive : ""}`}
              onClick={() => setSidebarFilter("groups")}
            >
              <Users aria-hidden="true" />
              {t("chat.groups")}
            </button>
          </div>
        </div>

        <div className={styles.contactsList}>
          {sidebarFilter === "chats" && <>
          <div className={styles.sectionLabel}>{t("chat.chats")}</div>
          {filteredContacts.map((contact) => {
            const isContactActive =
              activeChannel?.channel_type === "direct" &&
              activeChannel.display_name.toLowerCase() ===
                contact.full_name.toLowerCase();
            const directChannel = directChannelsByContactName.get(contact.full_name.toLocaleLowerCase());
            const preview = directChannel?.last_message_preview ||
              (directChannel ? t("chat.noMessagesYet") : contact.role_title);

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
                  <span className={styles.contactRole}>{preview}</span>
                </div>
                {directChannel && directChannel.unread_count > 0 && (
                  <span className={styles.messageBadge}>{directChannel.unread_count}</span>
                )}
              </button>
            );
          })}
          </>}

          {sidebarFilter === "groups" && <>
          <div className={styles.sectionHeaderRow}>
            <div className={styles.sectionLabel}>{t("chat.groups")}</div>
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
                  {channel.last_message_preview || t("chat.noMessagesYet")}
                </span>
              </div>
              {channel.unread_count > 0 && (
                <span className={styles.messageBadge}>
                  {channel.unread_count}
                </span>
              )}
            </button>
          ))}
          {filteredChannels.filter((channel) => channel.channel_type === "group").length === 0 && (
            <p className={styles.emptySidebarState}>{t("chat.emptyChannels")}</p>
          )}
          </>}

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

          <div className={styles.headerActions}>
            {activeChannel?.channel_type === "group" && (
              <button type="button" className={styles.settingsButton} onClick={() => void openMembers()} title={t("chat.viewMembers")}>
                <Users aria-hidden="true" />
              </button>
            )}
            <button type="button" className={styles.settingsButton} onClick={() => setShowUsageModal(true)} title={t("chat.usageTitle")}>
              <Settings aria-hidden="true" />
            </button>
          </div>
        </header>

        {/* Hilo de mensajes */}
        <div ref={transcriptRef} className={styles.transcript} onScroll={handleTranscriptScroll}>
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
                        title={t("chat.messageOptions")}
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
                            <span>{t("chat.editMessage")}</span>
                          </button>
                          <button
                            type="button"
                            className={`${styles.actionMenuItem} ${styles.danger}`}
                            onClick={() => void submitDeleteMessage(message.message_id)}
                          >
                            <Trash2 aria-hidden="true" />
                            <span>{t("chat.deleteMessage")}</span>
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
                      <span>{t("chat.deletedMessage")}</span>
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
                            <strong>{c.label || c.reference}</strong>
                          </button>
                        ))}
                      </div>
                    )}

                  <div className={styles.bubbleMeta}>
                    {/* Indicador de editado con lápiz (estilo WhatsApp) */}
                    {message.is_edited && !message.is_deleted && (
                      <span className={styles.editedTag} title={t("chat.editedMessage")}>
                        <Pencil aria-hidden="true" />
                        <span>{t("chat.editedMessage")}</span>
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
                        {message.status === "sent" && message.delivered_count > 1 && (
                          <CheckCheck className={message.read_count >= message.delivered_count ? styles.readReceipt : undefined} aria-hidden="true" />
                        )}
                        {message.status === "sent" && message.delivered_count <= 1 && (
                          <Check aria-hidden="true" />
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
                  <span>{t("chat.copilotName")}</span>
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
              disabled={!activeChannelId}
              rows={1}
            />
            {showCopilotSuggestion && activeChannelId && (
              <button
                type="button"
                className={styles.mentionSuggestion}
                onMouseDown={(event) => event.preventDefault()}
                onClick={completeCopilotMention}
              >
                <Sparkles aria-hidden="true" />
                <span><strong>@copilot</strong><small>{t("chat.copilotHint")}</small></span>
              </button>
            )}
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
                  {t("chat.level", { level: researcher.accreditation_level })}
                </span>
                <span className={styles.statLabel}>{t("chat.accessLevel")}</span>
              </div>
            </div>


            <div className={styles.modalNotice}>
              <ShieldCheck aria-hidden="true" />
              <span>{t("chat.securityNotice")}</span>
            </div>
          </div>
        </div>
      )}

      {showMembersModal && (
        <div className={styles.modalOverlay} onClick={() => setShowMembersModal(false)}>
          <div className={styles.membersModal} onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label={t("chat.groupMembersTitle")}>
            <div className={styles.modalHeader}>
              <div><h3>{t("chat.groupMembersTitle")}</h3><p>{t("chat.activeResearchers", { count: channelMembers.length })}</p></div>
              <div className={styles.memberModalActions}>
                <button type="button" className={styles.inlineSave} onClick={() => setShowAddMembersModal(true)}><UserPlus aria-hidden="true" />{t("chat.addMembers")}</button>
                <button type="button" className={styles.inlineCancel} onClick={() => void leaveActiveGroup()}>{t("chat.leaveGroup")}</button>
              <button type="button" className={styles.closeButton} onClick={() => setShowMembersModal(false)}><X aria-hidden="true" /></button>
              </div>
            </div>
            <div className={styles.groupMembersList}>
              {channelMembers.map((member) => (
                <div className={styles.groupMemberRow} key={member.researcher_id}>
                  <div className={styles.memberAvatar}>
                    <AnimalAvatar avatarKey={member.animal_avatar_key} seed={member.researcher_id} />
                  </div>
                  <div className={styles.memberDetails}>
                    <strong>{member.full_name}</strong>
                    <span>{member.role_title}</span>
                  </div>
                  <small>{t("chat.level", { level: member.accreditation_level })}</small>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {showAddMembersModal && activeChannelId && (
        <div className={styles.modalOverlay} onClick={() => setShowAddMembersModal(false)}>
          <div className={styles.addMembersModal} onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label={t("chat.addMembers")}>
            <div className={styles.modalHeader}>
              <div className={styles.modalTitleRow}>
                <div className={styles.modalIconWrap}><UserPlus aria-hidden="true" /></div>
                <div><h3 className={styles.modalTitleText}>{t("chat.addMembers")}</h3><p className={styles.modalSubtitleText}>{t("chat.membersCount", { count: selectedAdditionalMemberIds.length })}</p></div>
              </div>
              <button type="button" className={styles.closeButton} onClick={() => setShowAddMembersModal(false)} aria-label={t("common.close")}><X aria-hidden="true" /></button>
            </div>
            <div className={styles.memberSearchBox}>
              <Search aria-hidden="true" />
              <input type="search" className={styles.memberSearchInput} placeholder={t("chat.searchColleague")} value={additionalMemberSearch} onChange={(event) => setAdditionalMemberSearch(event.target.value)} autoFocus />
            </div>
            <div className={`${styles.memberSelectorList} ${styles.addMembersList}`}>
              {availableAdditionalMembers.map((contact) => {
                const selected = selectedAdditionalMemberIds.includes(contact.researcher_id);
                return <button type="button" key={contact.researcher_id} className={`${styles.memberSelectItem} ${selected ? styles.selected : ""}`} onClick={() => setSelectedAdditionalMemberIds((ids) => selected ? ids.filter((id) => id !== contact.researcher_id) : [...ids, contact.researcher_id])} aria-pressed={selected}>
                  <AnimalAvatar avatarKey={contact.animal_avatar_key} seed={contact.researcher_id} /><span className={styles.memberSelectInfo}><span className={styles.memberSelectName}>{contact.full_name}</span><span className={styles.memberSelectRole}>{contact.role_title}</span></span><span className={styles.memberLevelBadge}>{t("chat.level", { level: contact.accreditation_level })}</span>{selected && <span className={styles.memberSelectedCheck}><Check aria-hidden="true" /></span>}
                </button>;
              })}
              {availableAdditionalMembers.length === 0 && <p className={styles.emptyMemberSearch}>{t("chat.noMembersFound")}</p>}
            </div>
            <div className={styles.modalActions}><button type="button" className={styles.cancelBtn} onClick={() => setShowAddMembersModal(false)}>{t("common.cancel")}</button><button type="button" className={styles.submitBtn} disabled={!selectedAdditionalMemberIds.length} onClick={() => void addMembers()}><UserPlus aria-hidden="true" />{t("chat.addMembers")}</button></div>
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
                  placeholder={t("chat.searchColleague")}
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
                            aria-label={t("chat.selectResearcher", { name: contact.full_name })}
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
                            {t("chat.level", { level: contact.accreditation_level })}
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
