// Thin client for the JSON API (`App.Router`). Every call resolves
// to { ok: true, data } or { ok: false, error } — errors are values here too.

export type OrderItem = { sku: string; quantity: number; price_cents: number };
// what you send: the price is the server's (its products table)
export type NewOrderItem = { sku: string; quantity: number };
export type Order = {
  id: number;
  customer_email: string;
  status: string;
  total_cents: number;
  items: OrderItem[];
  created_at: string;
  updated_at: string;
};

export type Product = { sku: string; name: string; price_cents: number; description?: string };
export type SearchHit = { sku: string; name: string; price_cents: number; snippet: string | null; rank: number };
export type SearchResponse = { query: string; match: "text" | "fuzzy" | "none"; total: number; results: SearchHit[] };
export type AuditEntry = {
  id: number;
  at: string;
  actor: string;
  action: string;
  subject: string;
  details: Record<string, unknown>;
  request_id: string | null;
};
export type Flag = { key: string; value: unknown; updated_at: string };
export type Webhook = { id: number; url: string; events: string[]; active: boolean; secret?: string };
export type StoredFile = { id: number; filename: string; content_type: string; size: number; sha256: string; created_at: string };

import { clearSession, getToken, setSession, type User } from "./auth";

export type ApiError = {
  message: string;
  status?: number;
  fields?: Record<string, unknown>;
  retryAfter?: number;
};
export type Result<T> = { ok: true; data: T } | { ok: false; error: ApiError };

async function call<T>(method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<Result<T>> {
  try {
    const token = getToken();
    const headers: Record<string, string> = {};
    if (body) headers["content-type"] = "application/json";
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetch(`/api${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal,
    });
    const json = res.status === 204 ? {} : await res.json().catch(() => ({}));
    if (res.ok) return { ok: true, data: json as T };
    // the token is bad or expired (but a failed login attempt is just an error)
    if (res.status === 401 && token && path !== "/session") clearSession();
    const retryAfter = Number(res.headers.get("retry-after")) || undefined;
    // a 503 with no words of its own: the service is busy or paused, and asking again will usually work
    const fallback = res.status === 503 ? "The service is busy: try again in a moment." : `HTTP ${res.status}`;
    return {
      ok: false,
      error: { message: json.error ?? fallback, status: res.status, fields: json.errors, retryAfter },
    };
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") return { ok: false, error: { message: "cancelled" } };
    return { ok: false, error: { message: "can't reach the server" } };
  }
}

const qs = (params: Record<string, string | number | undefined>) => {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") q.set(k, String(v));
  const s = q.toString();
  return s ? `?${s}` : "";
};

export const api = {
  // -- who
  login: async (email: string, password: string): Promise<Result<User>> => {
    const res = await call<{ token: string; user: User }>("POST", "/session", { email, password });
    if (!res.ok) return res;
    setSession(res.data.token, res.data.user);
    return { ok: true, data: res.data.user };
  },
  me: () => call<User>("GET", "/me"),
  register: (email: string, password: string) => call<User>("POST", "/users", { email, password }),
  forgotPassword: (email: string) => call<{ status: string }>("POST", "/password/forgot", { email }),
  resetPassword: (token: string, password: string) =>
    call<{ status: string }>("POST", "/password/reset", { token, password }),
  confirmEmail: (token: string) => call<User>("POST", "/email/confirm", { token }),
  resendConfirmation: () => call<{ status: string }>("POST", "/email/resend"),

  // -- orders
  order: (id: number) => call<Order>("GET", `/orders/${id}`),
  createOrder: (order: { customer_email: string; items: NewOrderItem[] }) => call<Order>("POST", "/orders", order),
  cancelOrder: (id: number) => call<Order>("POST", `/orders/${id}/cancel`),

  // -- products
  searchProducts: (q: string, signal?: AbortSignal, limit = 10) =>
    call<SearchResponse>("GET", `/search/products${qs({ q, limit })}`, undefined, signal),
  product: (sku: string) => call<Product>("GET", `/products/${encodeURIComponent(sku)}`),
  createProduct: (p: { sku: string; name: string; description?: string; price_cents: number }) =>
    call<Product>("POST", "/products", p),
  updateProductDetails: (sku: string, d: { name?: string; description?: string }) =>
    call<Product>("PUT", `/products/${encodeURIComponent(sku)}/details`, d),
  setProductPrice: (sku: string, price_cents: number) =>
    call<Product>("PUT", `/products/${encodeURIComponent(sku)}`, { price_cents }),
  deleteProduct: (sku: string) => call<unknown>("DELETE", `/products/${encodeURIComponent(sku)}`),

  // -- settings and the audit log
  flags: () => call<{ flags: Flag[] }>("GET", "/flags"),
  setFlag: (key: string, value: unknown) => call<{ key: string; value: unknown }>("PUT", `/flags/${encodeURIComponent(key)}`, { value }),
  deleteFlag: (key: string) => call<unknown>("DELETE", `/flags/${encodeURIComponent(key)}`),
  audit: (params: { actor?: string; action?: string; subject?: string; before?: number; limit?: number }) =>
    call<{ entries: AuditEntry[]; next_before: number | null }>("GET", `/audit${qs(params)}`),

  // -- webhooks
  webhooks: () => call<{ endpoints: Webhook[] }>("GET", "/webhooks"),
  createWebhook: (url: string, events: string[]) => call<Webhook>("POST", "/webhooks", { url, events }),
  deleteWebhook: (id: number) => call<unknown>("DELETE", `/webhooks/${id}`),

  // -- files
  files: () => call<{ files: StoredFile[] }>("GET", "/files"),
  deleteFile: (id: number) => call<unknown>("DELETE", `/files/${id}`),
  /** Sends a file, reporting how much has gone (fetch can't). */
  uploadFile: (file: File, onProgress: (fraction: number) => void): Promise<Result<StoredFile>> =>
    new Promise((resolve) => {
      const xhr = new XMLHttpRequest();
      xhr.open("POST", "/api/files");
      const token = getToken();
      if (token) xhr.setRequestHeader("authorization", `Bearer ${token}`);
      xhr.upload.onprogress = (e) => e.lengthComputable && onProgress(e.loaded / e.total);
      xhr.onerror = () => resolve({ ok: false, error: { message: "can't reach the server" } });
      xhr.onload = () => {
        let json: any = {};
        try {
          json = JSON.parse(xhr.responseText);
        } catch {
          // not JSON
        }
        if (xhr.status >= 200 && xhr.status < 300) resolve({ ok: true, data: json as StoredFile });
        else resolve({ ok: false, error: { message: json.error ?? `HTTP ${xhr.status}`, status: xhr.status } });
      };
      const form = new FormData();
      form.append("file", file);
      xhr.send(form);
    }),
  /** The bytes of a file, with the login (a plain link could not send it). */
  downloadFile: async (f: StoredFile): Promise<Result<Blob>> => {
    try {
      const token = getToken();
      const res = await fetch(`/api/files/${f.id}`, { headers: token ? { authorization: `Bearer ${token}` } : {} });
      if (!res.ok) return { ok: false, error: { message: `HTTP ${res.status}`, status: res.status } };
      return { ok: true, data: await res.blob() };
    } catch {
      return { ok: false, error: { message: "can't reach the server" } };
    }
  },
};

export const money = (cents: number) => (cents / 100).toFixed(2);
