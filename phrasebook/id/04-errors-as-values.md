[English](../04-errors-as-values.md) · **Bahasa Indonesia**

# 4. Error sebagai nilai

**Di Go**:

```go
func (s *OrderService) List(p Params) (Page, error) {
    status, err := parseStatus(p.Status)
    if err != nil { return Page{}, err }
    page, err := parsePositive(p.Page, 1)
    if err != nil { return Page{}, err }
    perPage, err := parsePositive(p.PerPage, 20)
    if err != nil { return Page{}, err }
    return s.repo.List(status, page, perPage), nil
}
```

**Di Elixir** — function mengembalikan `{:ok, value}` atau
`{:error, reason}`, dan `with` menjalankan jalur normal (happy path),
berhenti di hal pertama yang tidak cocok
([`lib/shop/services/order_service.ex`](../../example/lib/shop/services/order_service.ex#L42)):

```elixir
def list(params) do
  with {:ok, status} <- status_param(params["status"]),
       {:ok, page} <- positive_int(params["page"], 1, :infinity, "page"),
       {:ok, per_page} <- positive_int(params["per_page"], 20, @max_per_page, "per_page") do
    orders = OrderRepo.list(%{status: status, page: page, per_page: per_page})
    {:ok, %{orders: orders, page: page, per_page: per_page}}
  end
end
```

Kalau `status_param/1` mengembalikan `{:error, {:invalid, "…"}}`, `with`
langsung mengembalikan error itu apa adanya — tidak perlu `if err != nil`
di setiap langkah.

| Go | Elixir |
|---|---|
| `(value, error)` | `{:ok, value}` / `{:error, reason}` |
| `if err != nil { return err }` | `with` |
| sentinel error (`ErrNotFound`) | atom: `{:error, :not_found}` |
| typed error (`*ConflictError`) | tuple: `{:error, {:conflict, "…"}}` |
| `errors.Is(err, ErrNotFound)` | pattern matching: `{:error, :not_found} ->` |

Error yang bisa dikembalikan service dicantumkan dalam satu type
([`order_service.ex`](../../example/lib/shop/services/order_service.ex#L12)) dan diubah
menjadi status HTTP di satu tempat ([`fallback_handler.ex`](../../example/lib/shop_web/handlers/fallback_handler.ex#L13)).

**Kenapa:** idenya sama dengan Go — error adalah nilai biasa, bukan
exception — tapi dengan lebih sedikit pengulangan. Exception memang ada di
Elixir, tapi untuk bug, bukan untuk "order tidak ditemukan".
