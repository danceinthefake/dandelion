# 12. When it crashes

**In Go**, a panic in a goroutine takes down the whole program unless you `recover` it. A background goroutine that dies only stops:

```go
go func() {
    defer func() {
        if r := recover(); r != nil { log.Printf("job crashed: %v", r) }  // and now?
    }()
    for range ticker.C { expireUnpaid() }
}()
```

**In Elixir**, a crash ends one process, and its supervisor starts a fresh one ([`lib/platform/application.ex`](../example/lib/platform/application.ex#L13)):

```elixir
opts = [strategy: :one_for_one, name: Platform.Supervisor]
Supervisor.start_link(children, opts)
```

`:one_for_one`: if a child dies, restart that child only.

Background jobs add a second safety net. A job that crashes is not lost. Oban records the error and runs the job again later, with backoff, up to its `max_attempts` ([`lib/app/shop/workers/expire_unpaid_orders.ex`](../example/lib/app/shop/workers/expire_unpaid_orders.ex)).
If a whole node dies in the middle of a job, another node picks the job up.

This is what it means day to day:

- A bug in one HTTP request crashes the process of that request. The client gets a 500, and every other request continues.
- If the database goes away for a minute, the job of that minute fails and is retried. The next cron tick runs as usual after the database is back. You write no code for this.
- Do not put `recover` blocks around business logic. Write the happy path, with `{:error, _}` for the errors that you expect ([page 4](04-errors-as-values.md)). Let the unexpected errors crash.

| Go | Elixir |
|---|---|
| `panic` | `raise` or a failed match, and the process exits |
| `recover` | a supervisor restarting the process (not in your code) |
| a dead background goroutine | the process is restarted; a failed job is retried |
| crash = whole program | crash = one process |

**Why:** This is the reason to learn Elixir. Failures stay small. Recovery is part of the structure and you do not write it by hand. A service keeps running through the errors that page a person at 3 a.m.
