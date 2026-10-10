# 15. Cron, and "only one does it"

In Go, a ticker goroutine runs on every instance. Three instances therefore cancel the unpaid orders three times a minute. The usual fixes are a Cloud Scheduler that calls an endpoint, or a Redis lock.

```go
go func() {
    for range time.Tick(time.Minute) {
        if rdb.SetNX(ctx, "lock:expire", id, 50*time.Second).Val() {   // who's first?
            expireUnpaid()
        }
    }
}()
```

```elixir
# lib/platform/cron.ex: the whole schedule
def schedule do
  [
    {"* * * * *", App.Shop.Workers.ExpireUnpaidOrders}
  ]
end
```

The schedule uses standard cron syntax, in UTC, in one place ([`lib/platform/cron.ex`](../example/lib/platform/cron.ex)). Oban runs the schedule on one node only. This node is the leader, and Postgres chooses it. Each entry therefore runs one time for each tick for the whole cluster, with any number of nodes. If the leader dies, another node takes over. The entry inserts a job like any other job. The service retries it if it fails, and it survives a restart ([`expire_unpaid_orders.ex`](../example/lib/app/shop/workers/expire_unpaid_orders.ex)).

| Go | Elixir |
|---|---|
| `time.Ticker` on every instance | a cron entry: one time for each cluster |
| Cloud Scheduler → HTTP endpoint | the same entry, no endpoint to protect |
| Redis `SETNX` lock for "only one" | the leader of Oban, or a unique job |

## "Only one of these at a time"

For work that must not overlap or repeat, do not build a lock. Make the job unique:

```elixir
use Oban.Worker, unique: [period: :infinity, keys: [:event_id]]
```

The service does not queue a second job with the same `event_id`. This is how the payment webhook ignores the retries of the provider ([`process_payment_event.ex`](../example/lib/app/shop/workers/process_payment_event.ex)).
For a change to a row that must not race, the lock is the lock of the database: `SELECT … FOR UPDATE` inside `Repo.transact` ([`order_service.ex`](../example/lib/app/shop/services/order_service.ex),
`cancel/1`).

**Why:** A lock in Redis can expire while its holder still works, or it can outlive the holder. The leader and the unique rows live in Postgres next to your data. The same transactions therefore decide them. If a node cannot reach Postgres, it cannot act either. This stops both halves of a network split from running the job.
