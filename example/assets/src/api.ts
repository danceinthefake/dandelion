// Thin client for the JSON API (`Platform.Web.Router`). Every call resolves
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

import { clearSession, getToken, setSession, type User } from "./auth";

export type ApiError = { message: string; fields?: Record<string, unknown> };
export type Result<T> = { ok: true; data: T } | { ok: false; error: ApiError };

async function call<T>(method: string, path: string, body?: unknown): Promise<Result<T>> {
  try {
    const token = getToken();
    const headers: Record<string, string> = {};
    if (body) headers["content-type"] = "application/json";
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetch(`/api${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json().catch(() => ({}));
    if (res.ok) return { ok: true, data: json as T };
    // the token is bad or expired (but a failed login attempt is just an error)
    if (res.status === 401 && token && path !== "/session") clearSession();
    return { ok: false, error: { message: json.error ?? `HTTP ${res.status}`, fields: json.errors } };
  } catch {
    return { ok: false, error: { message: "can't reach the server" } };
  }
}

export const api = {
  login: async (email: string, password: string): Promise<Result<User>> => {
    const res = await call<{ token: string; user: User }>("POST", "/session", { email, password });
    if (!res.ok) return res;
    setSession(res.data.token, res.data.user);
    return { ok: true, data: res.data.user };
  },
  me: () => call<User>("GET", "/me"),
  order: (id: number) => call<Order>("GET", `/orders/${id}`),
  createOrder: (order: { customer_email: string; items: NewOrderItem[] }) =>
    call<Order>("POST", "/orders", order),
  cancelOrder: (id: number) => call<Order>("POST", `/orders/${id}/cancel`),
};

export const money = (cents: number) => (cents / 100).toFixed(2);
