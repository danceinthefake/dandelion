// Thin client for the JSON API (`Platform.Web.Router`). Every call resolves
// to { ok: true, data } or { ok: false, error } — errors are values here too.

export type OrderItem = { sku: string; quantity: number; price_cents: number };
export type Order = {
  id: number;
  customer_email: string;
  status: string;
  total_cents: number;
  items: OrderItem[];
  created_at: string;
  updated_at: string;
};

export type ApiError = { message: string; fields?: Record<string, unknown> };
export type Result<T> = { ok: true; data: T } | { ok: false; error: ApiError };

async function call<T>(method: string, path: string, body?: unknown): Promise<Result<T>> {
  try {
    const res = await fetch(`/api${path}`, {
      method,
      headers: body ? { "content-type": "application/json" } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json().catch(() => ({}));
    if (res.ok) return { ok: true, data: json as T };
    return { ok: false, error: { message: json.error ?? `HTTP ${res.status}`, fields: json.errors } };
  } catch {
    return { ok: false, error: { message: "can't reach the server" } };
  }
}

export const api = {
  order: (id: number) => call<Order>("GET", `/orders/${id}`),
  createOrder: (order: { customer_email: string; items: OrderItem[] }) =>
    call<Order>("POST", "/orders", order),
  cancelOrder: (id: number) => call<Order>("POST", `/orders/${id}/cancel`),
};

export const money = (cents: number) => (cents / 100).toFixed(2);
