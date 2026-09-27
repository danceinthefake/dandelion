[English](../06-services-and-transactions.md) · **Bahasa Indonesia**

# 6. Service dan transaksi

**Di Go**:

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

**Di Elixir** ([`lib/shop/services/order_service.ex`](../../example/lib/shop/services/order_service.ex#L59)):

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

`Repo.transact` melakukan commit kalau function-nya mengembalikan
`{:ok, _}` dan rollback kalau mengembalikan `{:error, _}` — atau kalau
terjadi exception. Tidak ada `tx` yang perlu dioper ke sana-sini: setiap
query di dalam function itu berjalan di dalam transaksi, karena berjalan di
process yang sama.

| Go | Elixir |
|---|---|
| `db.BeginTx` / `defer tx.Rollback()` / `tx.Commit()` | `Repo.transact(fn -> … end)` |
| mengoper `tx` ke setiap panggilan repo | tidak perlu: process-nya yang memegang transaksi |
| `switch o.Status {…}` | function dengan beberapa clause (`cancellable/1`) |

**Kenapa:** aturan bisnisnya ("order yang sudah dikirim tidak bisa
dibatalkan") terbaca sebagai tiga clause function kecil yang bisa kamu test
sendiri-sendiri; transaksi menjadi bentuk kodenya, bukan pembukuan tambahan.
