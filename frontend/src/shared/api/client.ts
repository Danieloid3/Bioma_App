const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8001";

type ApiErrorBody = {
  error?: { code?: string; message?: string; correlation_id?: string; details?: unknown };
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
