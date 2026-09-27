# 6. Services and transactions

**In Go**:

```go
func (s *OrderService) Cancel(ctx context.Context, id int64) (Order, error) {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil { return Order{}, err }
    defer tx.Rollback()

    o, err := s.repo.LockForUpdate(ctx, tx, id)   // SELECT … FOR UPDATE
    if err != nil { return Order{}, err }
    if o.Status == "shipped" { return Order{}, ErrConflict }
    if err := s.repo.UpdateStatus(ctx, tx, id, "cancelled"); err != nil { return Order{}, err }
    return o, tx.Commit()
}
```

**In Elixir** ([`lib/app/shop/services/order_service.ex`](../example/lib/app/shop/services/order_service.ex#L59)):

```elixir
def cancel(id) do
  Repo.transact(fn ->
    with {:ok, order} <- locked(id),
         :ok <- cancellable(order),
         {:ok, order} <- OrderRepo.update_status(order, "cancelled") do
      {:ok, Repo.preload(order, :items)}
    end
  end)
end

defp cancellable(%Order{status: status}) when status in ["pending", "paid"], do: :ok
defp cancellable(%Order{status: "shipped"}), do: {:error, {:conflict, "a shipped order can't be cancelled"}}
```

`Repo.transact` commits when the function returns `{:ok, _}` and rolls back
when it returns `{:error, _}` — or raises. There is no `tx` to pass around:
every query in the function runs inside the transaction, because it runs
in the same process.

| Go | Elixir |
|---|---|
| `db.BeginTx` / `defer tx.Rollback()` / `tx.Commit()` | `Repo.transact(fn -> … end)` |
| passing `tx` to every repo call | nothing: the process holds the transaction |
| `switch o.Status {…}` | multi-clause functions (`cancellable/1`) |

**Why:** the rule ("shipped can't be cancelled") reads as three small
function clauses you can test on their own; the transaction is the shape of
the code, not bookkeeping.
