[English](../02-starting-up.md) · **Bahasa Indonesia**

# 2. Saat aplikasi start

**Di Go** — `main` merangkai semuanya lalu menunggu:

```go
func main() {
    db := mustOpenDB(os.Getenv("DATABASE_URL"))
    go expireUnpaidOrders(ctx, db)          // background work
    log.Fatal(http.ListenAndServe(":4000", router(db)))
}
```

**Di Elixir** — aplikasi mendaftar apa saja yang harus berjalan, berurutan,
lalu menyerahkan daftar itu ke sebuah **supervisor**
([`lib/shop/application.ex`](../../example/lib/shop/application.ex#L9)):

```elixir
def start(_type, _args) do
  children =
    [
      ShopWeb.Telemetry,
      Shop.Repo,                        # the database pool (≈ *sql.DB)
      {Phoenix.PubSub, name: Shop.PubSub}
    ] ++ jobs() ++ [ShopWeb.Endpoint]   # jobs (≈ goroutines), then HTTP

  opts = [strategy: :one_for_one, name: Shop.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Setiap child adalah process yang dijalankan sesuai urutan itu; endpoint HTTP
paling akhir, jadi request baru masuk setelah pool database dan job sudah
siap.

**Kenapa:** di Go, `main` menjalankan semuanya lalu berharap semuanya tetap
jalan. Supervisor *mengawasi* mereka: kalau salah satu mati (job, koneksi
database), supervisor menjalankannya lagi — lihat
[12. Saat terjadi crash](12-when-it-crashes.md).
