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
the list to a **supervisor** ([`lib/shop/application.ex`](../example/lib/shop/application.ex#L9)):

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

Each child is a process started in that order; the HTTP endpoint comes last,
so requests only arrive once the database pool and jobs are up.

**Why:** in Go, `main` starts things and hopes they keep running. A
supervisor *watches* them: if one dies (the job, a database connection), it
starts it again — see [12. When it crashes](12-when-it-crashes.md).
