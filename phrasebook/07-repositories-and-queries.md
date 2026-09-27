# 7. Repositories and queries

**In Go** (`database/sql`, or sqlc generating the same):

```go
func (r *OrderRepo) List(ctx context.Context, status *string, page, perPage int) ([]Order, error) {
    rows, err := r.db.QueryContext(ctx, `
        SELECT … FROM orders
        WHERE ($1::text IS NULL OR status = $1)
        ORDER BY inserted_at DESC, id DESC
        LIMIT $2 OFFSET $3`, status, perPage, (page-1)*perPage)
    // … scan rows, then load items
}
```

**In Elixir** — Ecto queries are built from functions, and compiled to
parameterised SQL ([`lib/app/shop/repos/order_repo.ex`](../example/lib/app/shop/repos/order_repo.ex#L21)):

```elixir
def list(%{status: status, page: page, per_page: per_page}) do
  Order
  |> then(fn q -> if status, do: where(q, status: ^status), else: q end)
  |> order_by(desc: :inserted_at, desc: :id)
  |> limit(^per_page)
  |> offset(^((page - 1) * per_page))
  |> Repo.all()
  |> Repo.preload(:items)
end

def lock_for_update(id), do: Order |> where(id: ^id) |> lock("FOR UPDATE") |> Repo.one()
```

| Go | Elixir |
|---|---|
| SQL string + `$1` args | query built from functions; `^value` marks a parameter |
| `rows.Scan(&o.ID, …)` | rows come back as `%Order{}` structs |
| second query for items | `Repo.preload(:items)` |
| `golang-migrate` up/down files | [`priv/repo/migrations/`](../example/priv/repo/migrations) + `mix ecto.migrate` / `ecto.rollback` |
| raw SQL when needed | `Repo.query("SELECT …", [args])` still works |

**Why:** optional filters (`if status …`) compose without string building,
and values are always parameters — no SQL injection by accident. The repo
stays "queries only": the service decides *what*, the repo knows *how*.
