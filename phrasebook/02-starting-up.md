# 2. Starting up

**In Go** — `main` wires things up and blocks:

```go
func main() {
    db := mustOpenDB(os.Getenv("DATABASE_URL"))
    go expireUnpaidOrders(ctx, db)          // background work
    log.Fatal(http.ListenAndServe(":4000", router(db)))
}
```

**In Elixir** — the application lists what must run, in order, and hands
the list to a **supervisor** ([`lib/platform/application.ex`](../example/lib/platform/application.ex#L13)):

```elixir
def start(_type, _args) do
  children =
    [
      Platform.Web.Telemetry,
      Platform.Database.Repo,                  # the database pool (≈ *sql.DB)
      {Dandelion.Cluster, otp_app: :acme, repo: Platform.Database.Repo},   # nodes finding each other
      {Phoenix.PubSub, name: Platform.Broadcast},
      Platform.Cache,                          # ≈ Redis as a cache, in memory
      {Oban, Platform.Queue.config()},         # background jobs and cron (≈ goroutines)
      Endpoint                                 # HTTP, last
    ]

  opts = [strategy: :one_for_one, name: Platform.Supervisor]
  Supervisor.start_link(children, opts)
end
```

Each child is a process started in that order; the HTTP endpoint comes last,
so requests only arrive once the database pool and jobs are up.

**Why:** in Go, `main` starts things and hopes they keep running. A
supervisor *watches* them: if one dies (the job queue, a database connection), it
starts it again — see [12. When it crashes](12-when-it-crashes.md).
