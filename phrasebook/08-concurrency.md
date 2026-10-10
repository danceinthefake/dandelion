# 8. Concurrency

Everything in Elixir runs in processes. These are not OS processes. They are small, isolated, and cheap: a few KB each, and millions for each machine. Each HTTP request is one process, and the background job is one process. They share nothing. They talk when they send messages.

The example does not need fan-out yet. Try these examples in `iex -S mix` (from `example/`).

Goroutine and `WaitGroup`: run several things at once and wait for all of them.

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
|> Task.async_stream(&App.Shop.Services.OrderService.get/1, max_concurrency: 10)
|> Enum.map(fn {:ok, result} -> result end)
```

`context.WithTimeout`: give up after a while.

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

**Why:** A goroutine must cooperate to be cancelled (it checks `ctx.Done()`). You can stop a process from outside. It cleans up, because it owns nothing that another process uses. This makes timeouts and cancellation plain in Elixir.
