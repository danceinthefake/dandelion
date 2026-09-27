[English](../07-repositories-and-queries.md) · **Bahasa Indonesia**

# 7. Repository dan query

**Di Go** (`database/sql`, atau sqlc yang menghasilkan hal yang sama):

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

**Di Elixir** — query Ecto dibangun dari function, lalu dikompilasi menjadi
SQL berparameter ([`lib/shop/repos/order_repo.ex`](../../example/lib/shop/repos/order_repo.ex#L21)):

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
| string SQL + argumen `$1` | query dibangun dari function; `^value` menandai parameter |
| `rows.Scan(&o.ID, …)` | baris kembali sebagai struct `%Order{}` |
| query kedua untuk item | `Repo.preload(:items)` |
| file up/down `golang-migrate` | [`priv/repo/migrations/`](../../example/priv/repo/migrations) + `mix ecto.migrate` / `ecto.rollback` |
| SQL mentah kalau perlu | `Repo.query("SELECT …", [args])` tetap bisa |

**Kenapa:** filter opsional (`if status …`) bisa dirangkai tanpa menyusun
string, dan nilai selalu dikirim sebagai parameter — tidak ada SQL injection
karena tidak sengaja. Repository tetap "hanya query": service memutuskan
*apa*, repository tahu *bagaimana*.
