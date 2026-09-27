# 4. Errors as values

**In Go**:

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

**In Elixir** — functions return `{:ok, value}` or `{:error, reason}`, and
`with` runs the happy path, stopping at the first thing that doesn't match
([`lib/shop/services/order_service.ex`](../example/lib/shop/services/order_service.ex#L44)):

```elixir
def list(params) do
  with {:ok, status} <- status_param(params["status"]),
       {:ok, page} <- positive_int(params["page"], 1, @max_page, "page"),
       {:ok, per_page} <- positive_int(params["per_page"], 20, @max_per_page, "per_page") do
    orders = OrderRepo.list(%{status: status, page: page, per_page: per_page})
    {:ok, %{orders: orders, page: page, per_page: per_page}}
  end
end
```

If `status_param/1` returns `{:error, {:invalid, "…"}}`, `with` returns
that error as it is — no `if err != nil` per step.

| Go | Elixir |
|---|---|
| `(value, error)` | `{:ok, value}` / `{:error, reason}` |
| `if err != nil { return err }` | `with` |
| sentinel errors (`ErrNotFound`) | atoms: `{:error, :not_found}` |
| typed errors (`*ConflictError`) | tuples: `{:error, {:conflict, "…"}}` |
| `errors.Is(err, ErrNotFound)` | pattern matching: `{:error, :not_found} ->` |

The errors the service can return are listed in one type
([`order_service.ex`](../example/lib/shop/services/order_service.ex#L12)) and turned
into HTTP statuses in one place ([`fallback_handler.ex`](../example/lib/shop_web/handlers/fallback_handler.ex#L13)).

**Why:** same idea as Go — errors are ordinary values, not exceptions — with
less repetition. Exceptions exist in Elixir, but they're for bugs, not for
"order not found".
