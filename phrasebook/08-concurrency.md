**English** · [Bahasa Indonesia](id/08-concurrency.md)

# 8. Concurrency

Everything in Elixir runs in **processes** — not OS processes: tiny,
isolated, cheap (a few KB each; millions per machine). Each HTTP request is
one; the background job is one. They share nothing: they talk by sending
messages.

The example doesn't need fan-out yet, so try these in `iex -S mix` (from
`example/`).

**Goroutine + `WaitGroup`** — run several things at once, wait for all:

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

**`context.WithTimeout`** — give up after a while:

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
| `ctx.Done()` checked by the callee | not needed: `Task.shutdown` stops the process from outside |
| channels | messages: `send(pid, msg)` / `receive` |
| `select` on channels | `receive` with several patterns (+ `after ms`) |

**Why:** a goroutine has to cooperate to be cancelled (check `ctx.Done()`);
a process can simply be stopped, and it cleans up because it owns nothing
anyone else uses. That's what makes timeouts and cancellation boring in
Elixir.
