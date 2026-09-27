[English](../03-routing-and-handlers.md) · **Bahasa Indonesia**

# 3. Routing dan handler

**Di Go** (chi):

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

**Di Elixir** — route ada di [`lib/shop_web/router.ex`](../../example/lib/shop_web/router.ex#L8):

```elixir
scope "/api", ShopWeb.Handlers do
  pipe_through :api

  post "/orders", OrderHandler, :create
  get "/orders", OrderHandler, :index
  get "/orders/:id", OrderHandler, :show
  post "/orders/:id/cancel", OrderHandler, :cancel
end
```

dan handler-nya di [`lib/shop_web/handlers/order_handler.ex`](../../example/lib/shop_web/handlers/order_handler.ex#L23):

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
| `w http.ResponseWriter, r *http.Request` | satu `conn` — request *dan* response yang sedang kamu bangun |
| `chi.URLParam(r, "id")` | `%{"id" => id}` diambil dari params lewat pattern matching |
| `writeJSON(w, 200, v)` | `json(conn, v)` |
| `writeError(w, err)` di setiap handler | `action_fallback`: semua `{:error, _}` dikirim ke [`FallbackHandler`](../../example/lib/shop_web/handlers/fallback_handler.ex) |
| response struct dengan tag `json:"…"` | [`OrderJSON`](../../example/lib/shop_web/handlers/order_json.ex) membangun map-nya |
| middleware | *plug* (`pipe_through :api`) |

**Kenapa:** di balik layar, handler adalah *controller* Phoenix; dandelion
menyebutnya handler dan menaruhnya di `handlers/` karena bagi kamu memang
itulah fungsinya. `action_fallback` menghilangkan
`if err != nil { writeError… }` dari setiap action — error dipetakan ke
status code di satu tempat saja.
