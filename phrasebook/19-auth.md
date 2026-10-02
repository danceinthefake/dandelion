# 19. Logins, tokens and who may see what

**In Go** — authentication is middleware: a function that wraps your handlers,
checks `Authorization`, and puts the user in the request's `context`:

```go
func Auth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        user, err := verify(bearer(r))
        if err != nil { http.Error(w, "unauthorized", 401); return }
        next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey, user)))
    })
}
r.With(Auth).Get("/orders", listOrders)         // chi
```

**In Elixir** — the same thing is a **plug**, listed in the router as a
pipeline, and the user goes in `conn.assigns` (the `context`):

```elixir
pipeline :authenticated do
  plug App.Accounts.Handlers.Auth, :authenticate
end

scope "/api" do
  pipe_through [:api, :authenticated]
  get "/orders", App.Shop.Handlers.OrderHandler, :index
end
```

[`auth.ex`](../example/lib/app/accounts/handlers/auth.ex) is the middleware;
[`router.ex`](../example/lib/platform/web/router.ex) says which routes need it,
and `:admin` (a second pipeline) adds a role check.

| Go | Elixir |
|---|---|
| `func Auth(next http.Handler) http.Handler` | a plug: `call(conn, opts)` |
| `r.With(Auth).Get(…)` / `r.Group` | `pipe_through [:api, :authenticated]` |
| `r.Context().Value(userKey)` | `conn.assigns.current_user` |
| `golang.org/x/crypto/pbkdf2`, bcrypt, argon2 | [`password.ex`](../example/lib/app/accounts/services/password.ex): PBKDF2 from `:crypto`, no dependency |
| a signed JWT | [`Phoenix.Token`](../example/lib/app/accounts/handlers/token.ex): signed, expires, nothing stored |

## One login, many nodes

A JWT or a `Phoenix.Token` is **signed, not stored**, so there's no session table
or Redis to share. Every node has the same `SECRET_KEY_BASE`, so every node
accepts a token any node issued — the cluster proof logs in once and gets answers
from all three nodes. The price is that a token can't be taken back before it
expires; the code says what to do if you need that.

## Who may see what is a rule

The plug answers "who are you"; "what may you see" depends on the data, so it is
a **service** rule, like any other:

```elixir
OrderService.get(id, viewer)    # a customer asking for somebody else's order: :not_found
```

A customer gets `404` for another customer's order — the same as for one that
doesn't exist, so the response doesn't say it's there. This is the mistake that
tops most API-security lists (an id in the URL that anyone can change), and the
reason ownership lives in the service and the repo's query, not in each handler.

**Why:** a plug is a function from conn to conn, so the middleware is not a
wrapper and not a framework: it's a function in a list. And because tokens are
signed, logging in costs the cluster nothing.
