[English](../08-concurrency.md) · **Bahasa Indonesia**

# 8. Konkurensi

Semua hal di Elixir berjalan di dalam **process** — bukan process OS: kecil,
terisolasi, murah (beberapa KB per process; jutaan per mesin). Setiap request
HTTP adalah satu process; background job juga satu process. Mereka tidak
berbagi apa pun: mereka berkomunikasi dengan saling mengirim pesan.

Contohnya belum butuh fan-out, jadi coba potongan kode ini di `iex -S mix`
(dari folder `example/`).

**Goroutine + `WaitGroup`** — jalankan beberapa hal sekaligus, tunggu semuanya:

```go
var wg sync.WaitGroup
results := make([]Order, len(ids))
for i, id := range ids {
    wg.Add(1)
    go func() { defer wg.Done(); results[i], _ = svc.Get(ctx, id) }()
}
wg.Wait()
```

```elixir
ids
|> Task.async_stream(&Shop.Services.OrderService.get/1, max_concurrency: 10)
|> Enum.map(fn {:ok, result} -> result end)
```

**`context.WithTimeout`** — menyerah setelah waktu tertentu:

```go
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel()
report, err := buildReport(ctx)
```

```elixir
task = Task.async(fn -> build_report() end)

case Task.yield(task, 2_000) || Task.shutdown(task) do
  {:ok, report} -> {:ok, report}
  nil -> {:error, :timeout}          # the task was stopped
end
```

| Go | Elixir |
|---|---|
| `go f()` | `Task.start(f)` / `Task.async(f)` |
| `sync.WaitGroup` | `Task.async_stream` / `Task.await_many` |
| `context.WithTimeout` | `Task.yield(task, ms) \|\| Task.shutdown(task)` |
| `ctx.Done()` dicek oleh function yang dipanggil | tidak perlu: `Task.shutdown` menghentikan process dari luar |
| channel | pesan: `send(pid, msg)` / `receive` |
| `select` pada channel | `receive` dengan beberapa pattern (+ `after ms`) |

**Kenapa:** goroutine harus bekerja sama supaya bisa dibatalkan (mengecek
`ctx.Done()`); process cukup dihentikan saja, dan dia bersih dengan sendirinya
karena tidak memiliki apa pun yang dipakai pihak lain. Itulah yang membuat
timeout dan pembatalan terasa biasa saja di Elixir.
