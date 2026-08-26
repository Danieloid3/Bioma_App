const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8000";

export class ApiClient {
  constructor(private readonly tokenProvider: () => string | null) {}

  async get<T>(path: string, query: URLSearchParams = new URLSearchParams()): Promise<T> {
    const token = this.tokenProvider();
    const response = await fetch(`${apiBaseUrl}${path}?${query.toString()}`, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    });
    if (!response.ok) throw new Error(`API request failed: ${response.status}`);
    return response.json() as Promise<T>;
  }
}

