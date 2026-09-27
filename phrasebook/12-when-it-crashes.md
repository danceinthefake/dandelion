# 12. When it crashes

**In Go** — a panic in a goroutine takes down the whole program unless you
`recover` it, and a background goroutine that dies just… stops:

```go
go func() {
    defer func() {
        if r := recover(); r != nil { log.Printf("job crashed: %v", r) }  // and now?
    }()
    for range ticker.C { expireUnpaid() }
}()
```

**In Elixir** — a crash ends **one process**, and its **supervisor** starts a
fresh one ([`lib/shop/application.ex`](../example/lib/shop/application.ex#L9)):

```elixir
opts = [strategy: :one_for_one, name: Shop.Supervisor]
Supervisor.start_link(children, opts)
```

`:one_for_one`: if a child dies, restart that child only. The example tests
exactly this ([`test/shop/jobs/expire_unpaid_orders_test.exs`](../example/test/shop/jobs/expire_unpaid_orders_test.exs)):
it kills the job, waits for the supervisor to start a new one, and checks the
new one still cancels orders.

What that means day to day:

- A bug in one HTTP request crashes that request's process: the client gets a
  500, every other request carries on.
- The database goes away for a minute: the job crashes on its next tick, is
  restarted, and works again once the database is back — no code for that.
- No `recover` blocks around business logic: write the happy path (with
  `{:error, _}` for errors you *expect*, [page 4](04-errors-as-values.md)),
  and let the unexpected crash.

| Go | Elixir |
|---|---|
| `panic` | `raise` / a failed match — the process exits |
| `recover` | a supervisor restarting the process (not in your code) |
| a dead background goroutine | restarted automatically |
| crash = whole program | crash = one process |

**Why:** this is the reason to learn Elixir. Failures stay small, recovery is
structural instead of hand-written, and a service keeps running through the
kind of errors that page someone at 3 a.m.
