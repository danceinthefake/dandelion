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

**In Elixir**, functions return `{:ok, value}` or `{:error, reason}`. `with` runs the happy path and stops at the first value that does not match ([`lib/app/shop/services/order_service.ex`](../example/lib/app/shop/services/order_service.ex#L44)):

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

If `status_param/1` returns `{:error, {:invalid, "…"}}`, `with` returns that error as it is. You do not write an `if err != nil` for each step.

| Go | Elixir |
|---|---|
| `(value, error)` | `{:ok, value}` / `{:error, reason}` |
| `if err != nil { return err }` | `with` |
| sentinel errors (`ErrNotFound`) | atoms: `{:error, :not_found}` |
| typed errors (`*ConflictError`) | tuples: `{:error, {:conflict, "…"}}` |
| `errors.Is(err, ErrNotFound)` | pattern matching: `{:error, :not_found} ->` |

One type lists the errors that the service can return ([`order_service.ex`](../example/lib/app/shop/services/order_service.ex#L12)). One place turns them into HTTP statuses ([`fallback_handler.ex`](../example/lib/platform/web/fallback_handler.ex#L13)).

**Why:** The idea is the same as in Go. Errors are ordinary values and not exceptions. The code repeats less. Exceptions exist in Elixir, but they are for bugs and not for "order not found".
