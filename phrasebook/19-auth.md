# 19. Logins, tokens, and who can see what

**In Go**, authentication is middleware. This is a function that wraps your handlers, reads `Authorization`, and puts the user in the `context` of the request:

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

**In Elixir**, the same thing is a plug. The router lists it in a pipeline, and the user goes in `conn.assigns` (the `context`):

```elixir
pipeline :authenticated do
  plug App.Accounts.Handlers.Auth, :authenticate
end

scope "/api" do
  pipe_through [:api, :authenticated]
  get "/orders", App.Shop.Handlers.OrderHandler, :index
end
```

[`auth.ex`](../example/lib/app/accounts/handlers/auth.ex) is the middleware. [`router.ex`](../example/lib/app/router.ex) defines the pipelines, and the `routes.ex` of each domain says which routes need the pipeline. `:admin` is a second pipeline, and it adds a role check.

| Go | Elixir |
|---|---|
| `func Auth(next http.Handler) http.Handler` | a plug: `call(conn, opts)` |
| `r.With(Auth).Get(…)` or `r.Group` | `pipe_through [:api, :authenticated]` |
| `r.Context().Value(userKey)` | `conn.assigns.current_user` |
| `golang.org/x/crypto/pbkdf2`, bcrypt, argon2 | [`password.ex`](../example/lib/app/accounts/services/password.ex): PBKDF2 from `:crypto`, no dependency |
| a signed JWT | [`Phoenix.Token`](../example/lib/app/accounts/handlers/token.ex): it is signed, it expires, and nothing is stored |

## One login, many nodes

A JWT or a `Phoenix.Token` is signed and not stored. You therefore have no session table or Redis to share. Every node has the same `SECRET_KEY_BASE`. Every node therefore accepts a token that any node issued. The cluster proof logs in one time and gets answers from all three nodes. The price is that you cannot take a token back before it expires. The code says what to do if you need that.

## Who may see what is a rule

The plug answers "who are you". The answer to "what can you see" depends on the data, so it is a service rule like any other rule:

```elixir
OrderService.get(id, viewer)    # a customer asking for somebody else's order: :not_found
```

A customer gets `404` for the order of another customer. This is the same answer as for an order that does not exist, so the response does not say that the order is there. The mistake of an id in the URL that anyone can change tops most API-security lists. This is the reason that ownership lives in the service and in the query of the repo, and not in each handler.

**Why:** A plug is a function from conn to conn. The middleware is not a wrapper and not a framework. It is a function in a list. Tokens are signed, so a login costs the cluster nothing.
