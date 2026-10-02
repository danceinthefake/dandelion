// The login: a token from POST /api/session, kept for the tab (sessionStorage).
// Every API call sends it as `Authorization: Bearer …`, and so does the
// WebSocket (`/socket?token=…`). A real site that serves its own pages would
// rather use an HttpOnly cookie; this console talks to a JSON API.
import { ref } from "vue";

export type User = { id: number; email: string; role: "customer" | "admin" };

const KEY = "acme.token";
export const user = ref<User | null>(null);

export const getToken = (): string | null => {
  try {
    return sessionStorage.getItem(KEY);
  } catch {
    return null;
  }
};

export function setSession(token: string, u: User) {
  try {
    sessionStorage.setItem(KEY, token);
  } catch {
    // no storage: the login lasts until the page is reloaded
  }
  user.value = u;
}

export function clearSession() {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    // nothing to remove
  }
  user.value = null;
}
