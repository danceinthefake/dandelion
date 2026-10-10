# 2. Starting up

**In Go**, `main` wires things up and blocks:

```go
func main() {
    db := mustOpenDB(os.Getenv("DATABASE_URL"))
    go expireUnpaidOrders(ctx, db)          // background work
    log.Fatal(http.ListenAndServe(":4000", router(db)))
}
```

**In Elixir**, the application lists what must run, in order. It gives the list to a supervisor ([`lib/platform/application.ex`](../example/lib/platform/application.ex#L13)). A supervisor is a process that starts other processes and watches them.

```elixir
def start(_type, _args) do
  children =
    [
      Platform.Web.Telemetry,
      Platform.Database.Repo,                  # the database pool (≈ *sql.DB)
      {Dandelion.Cluster, otp_app: :acme, repo: Platform.Database.Repo},   # nodes finding each other
      {Phoenix.PubSub, name: Platform.Broadcast},
      {Dandelion.Cache, pubsub: Platform.Broadcast},   # ≈ Redis as a cache, in memory
      {Oban, Platform.Queue.config()},         # background jobs and cron (≈ goroutines)
      Endpoint                                 # HTTP, last
    ]

  opts = [strategy: :one_for_one, name: Platform.Supervisor]
  Supervisor.start_link(children, opts)
end
```

The supervisor starts each child process in that order. The HTTP endpoint comes last. Requests therefore arrive only after the database pool and the jobs are up.

**Why:** In Go, `main` starts things and hopes that they keep running. A supervisor watches them. If one of them dies (the job queue or a database connection), the supervisor starts it again. See [12. When it crashes](12-when-it-crashes.md).
