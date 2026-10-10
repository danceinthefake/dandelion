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

**In Elixir**, the routes are in [`lib/app/shop/routes.ex`](../example/lib/app/shop/routes.ex):

```elixir
# domain: shop
scope "/api" do
  pipe_through :api

  post "/orders", App.Shop.Handlers.OrderHandler, :create
  get "/orders", App.Shop.Handlers.OrderHandler, :index
  get "/orders/:id", App.Shop.Handlers.OrderHandler, :show
  post "/orders/:id/cancel", App.Shop.Handlers.OrderHandler, :cancel
end
```

Each domain lists its own routes, with full module names. [`lib/app/router.ex`](../example/lib/app/router.ex) mounts them. This is like `r.Mount("/orders", shop.Routes())` of chi in `main.go`. A new domain never edits the file of another domain.

The handler is in [`lib/app/shop/handlers/order_handler.ex`](../example/lib/app/shop/handlers/order_handler.ex#L23):

```elixir
action_fallback Platform.Web.FallbackHandler

def show(conn, %{"id" => id}) do
  with {:ok, id} <- id(id),
       {:ok, order} <- OrderService.get(id) do
    json(conn, OrderJSON.order(order))
  end
end
```

| Go | Elixir |
|---|---|
| `w http.ResponseWriter, r *http.Request` | one `conn`, which is the request and the response that you build |
| `chi.URLParam(r, "id")` | `%{"id" => id}` pattern-matched from the params |
| `writeJSON(w, 200, v)` | `json(conn, v)` |
| `writeError(w, err)` in every handler | `action_fallback`: any `{:error, _}` goes to [`FallbackHandler`](../example/lib/platform/web/fallback_handler.ex) |
| response struct with `json:"…"` tags | [`OrderJSON`](../example/lib/app/shop/handlers/order_json.ex) builds the map |
| middleware | *plugs* (`pipe_through :api`) |

**Why:** Handlers are Phoenix controllers under the hood. dandelion calls them handlers and puts them in `handlers/`, because that is what they are to you. `action_fallback` removes the `if err != nil { writeError… }` from every action. The code maps errors to status codes in exactly one place.
