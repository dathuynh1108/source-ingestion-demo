"use client";

import {
  FormEvent,
  KeyboardEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import ReactMarkdown from "react-markdown";
import remarkBreaks from "remark-breaks";
import remarkGfm from "remark-gfm";
import { io, Socket } from "socket.io-client";
import { ulid } from "ulid";

import styles from "./page.module.css";

const CHATSERVER_URL =
  process.env.NEXT_PUBLIC_CHATSERVER_URL ?? "http://localhost:8001";
const CHAT_NAMESPACE = process.env.NEXT_PUBLIC_CHAT_NAMESPACE ?? "warehouse";
const SOCKET_PATH = normalizeSocketPath(
  process.env.NEXT_PUBLIC_CHATSERVER_SOCKET_PATH ?? "/socket.io",
);
const CLIENT_SESSION_STORAGE_KEY = "warehouse-chat-client-session";
const STARTER_PROMPTS = [
  "Which warehouse is most at risk of stockout today?",
  "What is the current inventory value by warehouse?",
  "Top SKUs above max stock",
  "Inventory movement for WH01 in the last 7 days",
  "Open purchase orders that still need replenishment",
] as const;

type ConnectionStatus = "connecting" | "connected" | "disconnected";
type ChatRole = "user" | "assistant" | "system" | "error";

type ChatLink = {
  title?: string | null;
  link?: string | null;
  format?: string | null;
};

type ChatItem = {
  id: string;
  role: ChatRole;
  text: string;
  createdAt: string;
  streaming?: boolean;
  links?: ChatLink[];
};

type ConversationHistoryItem = {
  conversationId: string;
  snippet: string;
  startedAt: string;
};

type ConversationListResponse = {
  items: Array<{
    conversations: string;
    started_at: string;
    first_message: string;
    snippet: string;
  }>;
};

type ConversationDetailResponse = {
  conversation_id: string;
  updated_at?: string | null;
  history: Array<{
    msg_id?: string | null;
    sender: string;
    message: string;
    created_at?: string | null;
    links?: ChatLink[] | null;
  }>;
};

type DashboardRow = Record<string, string | number | null>;

type DashboardResponse = {
  agent_mode?: string;
  summary?: DashboardRow;
  warehouse_summary?: DashboardRow[];
  low_stock_alerts?: DashboardRow[];
  overstock_alerts?: DashboardRow[];
  replenishment?: DashboardRow[];
};

type ServerMessagePayload = {
  event?: string;
  data?: {
    conversation_id?: string;
    msg_id?: string;
    chunk?: string;
    sender?: string;
    message?: string;
    links?: ChatLink[] | null;
    last_message_id?: string | null;
    updated_at?: string | null;
  };
  error?: string;
  message?: string;
};

type SessionPayload = {
  conversation_id?: string | null;
  resume_available?: boolean;
};

type RecentSubmission = {
  text: string;
  conversationId: string | null;
  timestamp: number;
};

function normalizeSocketPath(value: string): string {
  if (!value.trim()) {
    return "/socket.io";
  }
  return value.startsWith("/") ? value : `/${value}`;
}

function createId(): string {
  return ulid();
}

function getClientSessionId(): string {
  if (typeof window === "undefined") {
    return createId();
  }
  const existing = window.localStorage.getItem(CLIENT_SESSION_STORAGE_KEY);
  if (existing) {
    return existing;
  }
  const next = createId();
  window.localStorage.setItem(CLIENT_SESSION_STORAGE_KEY, next);
  return next;
}

function newChat(
  role: ChatRole,
  text: string,
  options?: Partial<Omit<ChatItem, "role" | "text">>,
): ChatItem {
  return {
    id: options?.id ?? createId(),
    role,
    text,
    createdAt: options?.createdAt ?? new Date().toISOString(),
    streaming: options?.streaming ?? false,
    links: options?.links,
  };
}

function roleFromSender(sender: string): ChatRole {
  const normalized = sender.toLowerCase();
  if (normalized === "user") {
    return "user";
  }
  if (normalized === "assistant" || normalized === "bot") {
    return "assistant";
  }
  if (normalized.includes("error")) {
    return "error";
  }
  return "system";
}

function resolveLinkHref(link?: string | null): string | undefined {
  if (!link) {
    return undefined;
  }
  if (link.startsWith("/")) {
    return `${CHATSERVER_URL}${link}`;
  }
  return link;
}

function formatTime(iso?: string | null): string {
  if (!iso) {
    return "--";
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return "--";
  }
  return date.toLocaleString("en-US");
}

function formatMetric(value: unknown): string {
  if (typeof value === "number") {
    return new Intl.NumberFormat("en-US", {
      maximumFractionDigits: value % 1 === 0 ? 0 : 2,
    }).format(value);
  }
  if (typeof value === "string" && value.trim()) {
    return value;
  }
  return "--";
}

function trimSnippet(value: string): string {
  const compact = value.replace(/\s+/g, " ").trim();
  if (compact.length <= 88) {
    return compact || "New chat";
  }
  return `${compact.slice(0, 87)}...`;
}

function MessageBubble({ item }: { item: ChatItem }) {
  const bubbleClassName = [
    styles.bubble,
    item.role === "user" ? styles.userBubble : "",
    item.role === "assistant" ? styles.assistantBubble : "",
    item.role === "system" ? styles.systemBubble : "",
    item.role === "error" ? styles.errorBubble : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div
      className={`${styles.messageRow} ${
        item.role === "user" ? styles.messageRowUser : styles.messageRowAssistant
      }`}
    >
      <article className={bubbleClassName}>
        <div className={styles.messageMeta}>
          <span>{item.role === "user" ? "You" : "Warehouse Assistant"}</span>
          <span>{formatTime(item.createdAt)}</span>
        </div>
        <div className={styles.markdown}>
          {item.text ? (
            <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]}>
              {item.text}
            </ReactMarkdown>
          ) : null}
          {item.streaming ? (
            <div className={styles.streamingIndicator}>
              {item.text ? (
                <span className={styles.streamingCursor} aria-hidden="true" />
              ) : (
                <span
                  className={styles.streamingDots}
                  aria-label="Assistant is typing"
                >
                  <span className={styles.streamingDot} />
                  <span className={styles.streamingDot} />
                  <span className={styles.streamingDot} />
                </span>
              )}
            </div>
          ) : null}
        </div>
        {item.links?.length ? (
          <div className={styles.linkList}>
            {item.links.map((link, index) => {
              const href = resolveLinkHref(link.link);
              if (!href) {
                return null;
              }
              return (
                <a
                  key={`${item.id}-link-${index}`}
                  className={styles.linkChip}
                  href={href}
                  target="_blank"
                  rel="noreferrer"
                >
                  {link.title || "Link"}
                </a>
              );
            })}
          </div>
        ) : null}
      </article>
    </div>
  );
}

export default function Home() {
  const [messages, setMessages] = useState<ChatItem[]>([]);
  const [composer, setComposer] = useState("");
  const [connectionStatus, setConnectionStatus] =
    useState<ConnectionStatus>("connecting");
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [conversations, setConversations] = useState<ConversationHistoryItem[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const [dashboard, setDashboard] = useState<DashboardResponse | null>(null);
  const [dashboardError, setDashboardError] = useState<string | null>(null);
  const [isSending, setIsSending] = useState(false);
  const socketRef = useRef<Socket | null>(null);
  const messagesRef = useRef<HTMLDivElement | null>(null);
  const pendingAssistantIdRef = useRef<string | null>(null);
  const recentSubmissionRef = useRef<RecentSubmission | null>(null);

  const clearPendingAssistant = useCallback(() => {
    pendingAssistantIdRef.current = null;
  }, []);

  const ensurePendingAssistant = useCallback(() => {
    if (pendingAssistantIdRef.current) {
      return pendingAssistantIdRef.current;
    }

    const pendingId = `pending-${createId()}`;
    pendingAssistantIdRef.current = pendingId;
    setMessages((current) => [
      ...current,
      newChat("assistant", "", {
        id: pendingId,
        streaming: true,
      }),
    ]);
    return pendingId;
  }, []);

  const sendMessage = useCallback(
    (rawText: string) => {
      const text = rawText.trim();
      if (!text || !socketRef.current || connectionStatus !== "connected") {
        return false;
      }

      const now = Date.now();
      const recentSubmission = recentSubmissionRef.current;
      if (
        recentSubmission &&
        recentSubmission.text === text &&
        recentSubmission.conversationId === conversationId &&
        now - recentSubmission.timestamp < 500
      ) {
        return false;
      }

      recentSubmissionRef.current = {
        text,
        conversationId,
        timestamp: now,
      };
      setMessages((current) => [...current, newChat("user", text)]);
      setComposer("");
      setIsSending(true);
      ensurePendingAssistant();
      socketRef.current.emit("client_message", {
        conversation_id: conversationId,
        message: text,
      });
      return true;
    },
    [connectionStatus, conversationId, ensurePendingAssistant],
  );

  const fetchDashboard = useCallback(async () => {
    try {
      setDashboardError(null);
      const response = await fetch(`${CHATSERVER_URL}/api/v1/warehouse/dashboard`);
      if (!response.ok) {
        throw new Error(`Dashboard request failed (${response.status}).`);
      }
      const payload = (await response.json()) as DashboardResponse;
      setDashboard(payload);
    } catch (error) {
      setDashboardError(
        error instanceof Error ? error.message : "Unable to load dashboard.",
      );
    }
  }, []);

  const fetchConversations = useCallback(async () => {
    try {
      setHistoryLoading(true);
      setHistoryError(null);
      const response = await fetch(
        `${CHATSERVER_URL}/api/v1/chat/${CHAT_NAMESPACE}/history`,
      );
      if (!response.ok) {
        throw new Error(`History request failed (${response.status}).`);
      }
      const payload = (await response.json()) as ConversationListResponse;
      setConversations(
        payload.items.map((item) => ({
          conversationId: item.conversations,
          startedAt: item.started_at,
          snippet: trimSnippet(item.snippet || item.first_message || ""),
        })),
      );
    } catch (error) {
      setHistoryError(
        error instanceof Error ? error.message : "Unable to load chat history.",
      );
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  const loadConversation = useCallback(async (targetConversationId: string) => {
    try {
      setHistoryLoading(true);
      setHistoryError(null);
      const response = await fetch(
        `${CHATSERVER_URL}/api/v1/chat/${CHAT_NAMESPACE}/history/${targetConversationId}`,
      );
      if (!response.ok) {
        throw new Error(`Conversation request failed (${response.status}).`);
      }
      const payload = (await response.json()) as ConversationDetailResponse;
      setConversationId(payload.conversation_id);
      clearPendingAssistant();
      setMessages(
        payload.history.map((item) =>
          newChat(roleFromSender(item.sender), item.message, {
            id: item.msg_id ?? createId(),
            createdAt: item.created_at ?? new Date().toISOString(),
            streaming: false,
            links: item.links ?? undefined,
          }),
        ),
      );
    } catch (error) {
      setHistoryError(
        error instanceof Error ? error.message : "Unable to load conversation.",
      );
    } finally {
      setHistoryLoading(false);
    }
  }, [clearPendingAssistant]);

  const handleServerMessage = useCallback(
    (payload: ServerMessagePayload) => {
      if (payload.error) {
        const pendingId = pendingAssistantIdRef.current;
        setIsSending(false);
        clearPendingAssistant();
        setMessages((current) => {
          const next = pendingId
            ? current.filter((item) => item.id !== pendingId)
            : [...current];
          next.push(newChat("error", payload.message || "A server error occurred."));
          return next;
        });
        return;
      }

      if (payload.event === "chunk" && payload.data?.msg_id) {
        const chunkData = payload.data;
        setMessages((current) => {
          const next = [...current];
          const streamingId = chunkData.msg_id!;
          const index = next.findIndex((item) => item.id === streamingId);
          const pendingId = pendingAssistantIdRef.current;
          const pendingIndex = pendingId
            ? next.findIndex((item) => item.id === pendingId)
            : -1;
          if (index === -1) {
            if (pendingIndex !== -1) {
              next[pendingIndex] = {
                ...next[pendingIndex],
                id: streamingId,
                text: `${next[pendingIndex].text}${chunkData.chunk ?? ""}`,
                streaming: true,
              };
            } else {
              next.push(
                newChat("assistant", chunkData.chunk ?? "", {
                  id: streamingId,
                  streaming: true,
                }),
              );
            }
            pendingAssistantIdRef.current = streamingId;
            return next;
          }
          next[index] = {
            ...next[index],
            text: `${next[index].text}${chunkData.chunk ?? ""}`,
            streaming: true,
          };
          return next;
        });
        return;
      }

      if (payload.event === "message" && payload.data?.msg_id) {
        const messageData = payload.data;
        setMessages((current) => {
          const next = [...current];
          const resolvedId = messageData.msg_id!;
          const index = next.findIndex((item) => item.id === resolvedId);
          const pendingId = pendingAssistantIdRef.current;
          const pendingIndex = pendingId
            ? next.findIndex((item) => item.id === pendingId)
            : -1;
          const complete = newChat(
            roleFromSender(messageData.sender ?? "assistant"),
            messageData.message ?? "",
            {
              id: resolvedId,
              createdAt: new Date().toISOString(),
              streaming: false,
              links: messageData.links ?? undefined,
            },
          );
          if (index === -1) {
            if (pendingIndex !== -1) {
              next[pendingIndex] = complete;
            } else {
              next.push(complete);
            }
          } else {
            next[index] = complete;
          }
          return next;
        });
        setIsSending(false);
        clearPendingAssistant();
        return;
      }

      if (payload.event === "response" && payload.data?.conversation_id) {
        setConversationId(payload.data.conversation_id);
        setIsSending(false);
        clearPendingAssistant();
        void fetchConversations();
        void fetchDashboard();
        return;
      }

      if (payload.event === "interrupted") {
        const pendingId = pendingAssistantIdRef.current;
        setIsSending(false);
        clearPendingAssistant();
        setMessages((current) => {
          const next = pendingId
            ? current.filter((item) => item.id !== pendingId)
            : [...current];
          next.push(newChat("system", "Stopped the current response stream."));
          return next;
        });
      }
    },
    [clearPendingAssistant, fetchConversations, fetchDashboard],
  );

  useEffect(() => {
    const socket = io(CHATSERVER_URL, {
      path: SOCKET_PATH,
      transports: ["websocket"],
      auth: {
        namespace: CHAT_NAMESPACE,
        client_session_id: getClientSessionId(),
      },
    });

    socketRef.current = socket;
    setConnectionStatus("connecting");

    socket.on("connect", () => {
      setConnectionStatus("connected");
      void fetchDashboard();
      void fetchConversations();
    });

    socket.on("disconnect", () => {
      setConnectionStatus("disconnected");
    });

    socket.on("connect_error", (error) => {
      setConnectionStatus("disconnected");
      setHistoryError(error.message);
    });

    socket.on("session", (payload: SessionPayload) => {
      if (payload.resume_available && payload.conversation_id) {
        setConversationId(payload.conversation_id);
        void loadConversation(payload.conversation_id);
      }
    });

    socket.on("server_message", handleServerMessage);

    return () => {
      socket.disconnect();
      socketRef.current = null;
    };
  }, [fetchConversations, fetchDashboard, handleServerMessage, loadConversation]);

  useEffect(() => {
    if (!messagesRef.current) {
      return;
    }
    messagesRef.current.scrollTop = messagesRef.current.scrollHeight;
  }, [messages]);

  const connectionLabel = useMemo(() => {
    if (connectionStatus === "connected") {
      return "Ready";
    }
    if (connectionStatus === "connecting") {
      return "Connecting";
    }
    return "Offline";
  }, [connectionStatus]);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    sendMessage(composer);
  };

  const handleComposerKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key !== "Enter" || event.shiftKey) {
      return;
    }
    if (event.nativeEvent.isComposing) {
      return;
    }
    event.preventDefault();
    sendMessage(composer);
  };

  const handleStarterPrompt = (prompt: string) => {
    setComposer(prompt);
  };

  const handleStop = () => {
    socketRef.current?.emit("client_message", { type: "stop" });
  };

  const handleNewConversation = () => {
    clearPendingAssistant();
    setConversationId(null);
    setMessages([]);
    setComposer("");
  };

  const overview = dashboard?.summary ?? {};

  return (
    <div className={styles.page}>
      <div className={styles.shell}>
        <aside className={styles.sidebar}>
          <div className={styles.brandBlock}>
            <span className={styles.eyebrow}>Inventory Demo</span>
            <h1>Warehouse Chat</h1>
            <p>
              Ask quick questions about inventory, stock movement, low-stock risk,
              and replenishment on top of the current ClickHouse dataset.
            </p>
          </div>

          <section className={styles.sidebarSection}>
            <div className={styles.sectionHeader}>
              <h2>History</h2>
              <button
                type="button"
                className={styles.secondaryButton}
                onClick={handleNewConversation}
              >
                New chat
              </button>
            </div>

            <div className={styles.historyList}>
              {historyLoading ? (
                <p className={styles.mutedText}>Loading history...</p>
              ) : conversations.length === 0 ? (
                <p className={styles.mutedText}>No conversations yet.</p>
              ) : (
                conversations.map((item) => (
                  <button
                    key={item.conversationId}
                    type="button"
                    className={`${styles.historyItem} ${
                      item.conversationId === conversationId ? styles.historyItemActive : ""
                    }`}
                    onClick={() => void loadConversation(item.conversationId)}
                  >
                    <strong>{item.snippet}</strong>
                    <span>{formatTime(item.startedAt)}</span>
                  </button>
                ))
              )}
            </div>
            {historyError ? <p className={styles.errorText}>{historyError}</p> : null}
          </section>

          <section className={styles.sidebarSection}>
            <div className={styles.sectionHeader}>
              <h2>Starter prompts</h2>
            </div>
            <div className={styles.promptList}>
              {STARTER_PROMPTS.map((prompt) => (
                <button
                  key={prompt}
                  type="button"
                  className={styles.promptButton}
                  onClick={() => handleStarterPrompt(prompt)}
                >
                  {prompt}
                </button>
              ))}
            </div>
          </section>
        </aside>

        <main className={styles.workspace}>
          <header className={styles.workspaceHeader}>
            <div>
              <span className={styles.eyebrow}>Warehouse Assistant</span>
              <h2>Ask about current warehouse data</h2>
            </div>
            <div
              className={`${styles.statusPill} ${
                connectionStatus === "connected"
                  ? styles.statusConnected
                  : connectionStatus === "connecting"
                    ? styles.statusConnecting
                    : styles.statusDisconnected
              }`}
            >
              {connectionLabel}
            </div>
          </header>

          <div ref={messagesRef} className={styles.messageList}>
            {messages.length === 0 ? (
              <div className={styles.emptyState}>
                <h3>Start with a short question.</h3>
                <p>
                  This app is only for Q&A over the current warehouse dataset.
                  There is no document upload or file attachment flow.
                </p>
                <div className={styles.emptyPromptRow}>
                  {STARTER_PROMPTS.slice(0, 3).map((prompt) => (
                    <button
                      key={prompt}
                      type="button"
                      className={styles.promptButton}
                      onClick={() => handleStarterPrompt(prompt)}
                    >
                      {prompt}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              messages.map((item) => <MessageBubble key={item.id} item={item} />)
            )}
          </div>

          <form className={styles.composer} onSubmit={handleSubmit}>
            <label className={styles.composerLabel} htmlFor="chat-composer">
              Question
            </label>
            <textarea
              id="chat-composer"
              className={styles.textarea}
              value={composer}
              onChange={(event) => setComposer(event.target.value)}
              onKeyDown={handleComposerKeyDown}
              placeholder="Example: Which warehouse is most at risk of stockout today?"
              rows={4}
            />
            <div className={styles.composerFooter}>
              <p className={styles.mutedText}>
                Press Enter to send. Use Shift + Enter for a new line. The
                agent prioritizes inventory, replenishment, and movement.
              </p>
              <div className={styles.actionRow}>
                <button
                  type="button"
                  className={styles.secondaryButton}
                  onClick={handleStop}
                  disabled={!isSending}
                >
                  Stop
                </button>
                <button
                  type="submit"
                  className={styles.primaryButton}
                  disabled={connectionStatus !== "connected" || !composer.trim()}
                >
                  Send
                </button>
              </div>
            </div>
          </form>
        </main>

        <aside className={styles.rail}>
          <section className={styles.railSection}>
            <div className={styles.sectionHeader}>
              <h2>Latest snapshot</h2>
              <span className={styles.caption}>
                {formatMetric(overview.snapshot_date)}
              </span>
            </div>
            <div className={styles.metricGrid}>
              <div className={styles.metricCard}>
                <span className={styles.metricLabel}>Available</span>
                <strong>{formatMetric(overview.total_available_qty)}</strong>
              </div>
              <div className={styles.metricCard}>
                <span className={styles.metricLabel}>On hand</span>
                <strong>{formatMetric(overview.total_on_hand_qty)}</strong>
              </div>
              <div className={styles.metricCard}>
                <span className={styles.metricLabel}>Inventory value</span>
                <strong>{formatMetric(overview.total_inventory_value)}</strong>
              </div>
              <div className={styles.metricCard}>
                <span className={styles.metricLabel}>Low-stock SKUs</span>
                <strong>{formatMetric(overview.low_stock_sku_count)}</strong>
              </div>
            </div>
            {dashboardError ? <p className={styles.errorText}>{dashboardError}</p> : null}
          </section>

          <section className={styles.railSection}>
            <div className={styles.sectionHeader}>
              <h2>Top warehouses</h2>
              <span className={styles.caption}>{dashboard?.agent_mode ?? "--"}</span>
            </div>
            <div className={styles.tableBlock}>
              {(dashboard?.warehouse_summary ?? []).map((row, index) => (
                <div key={`warehouse-${index}`} className={styles.tableRow}>
                  <div>
                    <strong>{formatMetric(row.warehouse_name)}</strong>
                    <span>{formatMetric(row.city)}</span>
                  </div>
                  <div className={styles.tableMetric}>
                    <strong>{formatMetric(row.inventory_value)}</strong>
                    <span>Available {formatMetric(row.available_qty)}</span>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className={styles.railSection}>
            <div className={styles.sectionHeader}>
              <h2>Low stock to review</h2>
            </div>
            <div className={styles.tableBlock}>
              {(dashboard?.low_stock_alerts ?? []).map((row, index) => (
                <div key={`low-stock-${index}`} className={styles.tableRow}>
                  <div>
                    <strong>{formatMetric(row.sku_id)}</strong>
                    <span>{formatMetric(row.warehouse_name)}</span>
                  </div>
                  <div className={styles.tableMetric}>
                    <strong>{formatMetric(row.available_qty)}</strong>
                    <span>Reorder point {formatMetric(row.reorder_point)}</span>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className={styles.railSection}>
            <div className={styles.sectionHeader}>
              <h2>Open POs</h2>
            </div>
            <div className={styles.tableBlock}>
              {(dashboard?.replenishment ?? []).map((row, index) => (
                <div key={`po-${index}`} className={styles.tableRow}>
                  <div>
                    <strong>{formatMetric(row.sku_id)}</strong>
                    <span>{formatMetric(row.sku_name)}</span>
                  </div>
                  <div className={styles.tableMetric}>
                    <strong>{formatMetric(row.qty_open)}</strong>
                    <span>{formatMetric(row.open_value)}</span>
                  </div>
                </div>
              ))}
            </div>
          </section>
        </aside>
      </div>
    </div>
  );
}
