const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8001";

type ApiErrorBody = {
  error?: { code?: string; message?: string; correlation_id?: string; details?: unknown };
};

export type ServerSentEvent = {
  event: string;
  data: string;
};

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly correlationId?: string,
  ) {
    super(message);
  }
}

const correlationId = () => crypto.randomUUID();

export class ApiClient {
  constructor(private readonly tokenProvider: () => string | null) {}

  async get<T>(path: string, query?: URLSearchParams): Promise<T> {
    const suffix = query && query.size > 0 ? `?${query.toString()}` : "";
    return this.request<T>(`${path}${suffix}`, { method: "GET" });
  }

  async post<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) });
  }

  async patch<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: "PATCH", body: JSON.stringify(body) });
  }

  async delete<T>(path: string): Promise<T> {
    return this.request<T>(path, { method: "DELETE" });
  }

  /**
   * Opens an authenticated SSE stream using fetch because native EventSource
   * cannot attach Bioma's in-memory bearer token.
   */
  async stream(
    path: string,
    onEvent: (event: ServerSentEvent) => void,
    signal: AbortSignal,
  ): Promise<void> {
    const token = this.tokenProvider();
    const response = await fetch(`${apiBaseUrl}${path}`, {
      method: "GET",
      credentials: "include",
      signal,
      headers: {
        Accept: "text/event-stream",
        "X-Correlation-ID": correlationId(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    });
    if (!response.ok) {
      const payload = (await response.json().catch(() => ({}))) as ApiErrorBody;
      throw new ApiError(
        response.status,
        payload.error?.code ?? "stream_failed",
        payload.error?.message ?? `Stream failed (${response.status})`,
        payload.error?.correlation_id,
      );
    }
    if (!response.body) throw new ApiError(0, "stream_unavailable", "La conexión en tiempo real no está disponible.");

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      while (!signal.aborted) {
        const { value, done } = await reader.read();
        if (done) return;
        buffer += decoder.decode(value, { stream: true }).replaceAll("\r\n", "\n");
        let separator = buffer.indexOf("\n\n");
        while (separator >= 0) {
          const block = buffer.slice(0, separator);
          buffer = buffer.slice(separator + 2);
          const event = block.match(/^event:\s*(.+)$/m)?.[1] ?? "message";
          const data = block
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trimStart())
            .join("\n");
          if (data) onEvent({ event, data });
          separator = buffer.indexOf("\n\n");
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  async request<T>(path: string, init: RequestInit): Promise<T> {
    const token = this.tokenProvider();
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...init,
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        "X-Correlation-ID": correlationId(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init.headers,
      },
    });
    if (response.status === 204) return undefined as T;
    if (!response.ok) {
      const payload = (await response.json().catch(() => ({}))) as ApiErrorBody;
      throw new ApiError(
        response.status,
        payload.error?.code ?? "request_failed",
        payload.error?.message ?? `Request failed (${response.status})`,
        payload.error?.correlation_id,
      );
    }
    return (await response.json()) as T;
  }
}
