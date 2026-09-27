**English** · [Bahasa Indonesia](id/03-routing-and-handlers.md)

# 3. Routing and handlers

**In Go** (chi):

```go
r.Route("/api/orders", func(r chi.Router) {
    r.Post("/", h.Create)
    r.Get("/", h.List)
    r.Get("/{id}", h.Show)
    r.Post("/{id}/cancel", h.Cancel)
})

func (h *OrderHandler) Show(w http.ResponseWriter, r *http.Request) {
    id, err := strconv.Atoi(chi.URLParam(r, "id"))
    if err != nil { writeError(w, errNotFound); return }
    order, err := h.svc.Get(r.Context(), id)
    if err != nil { writeError(w, err); return }
    writeJSON(w, 200, toOrderResponse(order))
}
```

**In Elixir** — routes in [`lib/shop_web/router.ex`](../example/lib/shop_web/router.ex#L12):

```elixir
scope "/api", ShopWeb.Handlers do
  pipe_through :api

  post "/orders", OrderHandler, :create
  get "/orders", OrderHandler, :index
  get "/orders/:id", OrderHandler, :show
  post "/orders/:id/cancel", OrderHandler, :cancel
end
```

and the handler in [`lib/shop_web/handlers/order_handler.ex`](../example/lib/shop_web/handlers/order_handler.ex#L23):

```elixir
action_fallback ShopWeb.Handlers.FallbackHandler

def show(conn, %{"id" => id}) do
  with {:ok, id} <- id(id),
       {:ok, order} <- OrderService.get(id) do
    json(conn, OrderJSON.order(order))
  end
end
```

| Go | Elixir |
|---|---|
| `w http.ResponseWriter, r *http.Request` | one `conn` — the request *and* the response you're building |
| `chi.URLParam(r, "id")` | `%{"id" => id}` pattern-matched from the params |
| `writeJSON(w, 200, v)` | `json(conn, v)` |
| `writeError(w, err)` in every handler | `action_fallback`: any `{:error, _}` goes to [`FallbackHandler`](../example/lib/shop_web/handlers/fallback_handler.ex) |
| response struct with `json:"…"` tags | [`OrderJSON`](../example/lib/shop_web/handlers/order_json.ex) builds the map |
| middleware | *plugs* (`pipe_through :api`) |

**Why:** handlers are Phoenix *controllers* under the hood; dandelion calls them
handlers and puts them in `handlers/` because that's what they are to you.
`action_fallback` removes the `if err != nil { writeError… }` from every
action — errors are mapped to status codes in exactly one place.
