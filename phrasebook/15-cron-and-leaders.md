# 15. Cron, and "only one does it"

In Go, a ticker goroutine runs on **every instance** — so three instances
cancel the unpaid orders three times a minute. The usual fixes: Cloud
Scheduler calling an endpoint, or a Redis lock.

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
# lib/platform/cron.ex — the whole schedule
def schedule do
  [
    {"* * * * *", App.Shop.Workers.ExpireUnpaidOrders}
  ]
end
```

Standard cron syntax, in UTC, in one place
([`lib/platform/cron.ex`](../example/lib/platform/cron.ex)). Oban runs the
schedule on **one node only** — its leader, chosen through Postgres — so each
entry runs once per tick for the whole cluster, however many nodes are up. If
the leader dies, another node takes over. The entry inserts a job like any
other, so it is retried if it fails and survives a restart
([`expire_unpaid_orders.ex`](../example/lib/app/shop/workers/expire_unpaid_orders.ex)).

| Go | Elixir |
|---|---|
| `time.Ticker` on every instance | a cron entry: once per cluster |
| Cloud Scheduler → HTTP endpoint | the same entry, no endpoint to protect |
| Redis `SETNX` lock for "only one" | Oban's leader; or a **unique job** |

## "Only one of these at a time"

For work that shouldn't overlap or repeat, don't build a lock — make the job
unique:

```elixir
use Oban.Worker, unique: [period: :infinity, keys: [:event_id]]
```

A second job with the same `event_id` is not queued. That is how the payment
webhook ignores the provider's retries
([`process_payment_event.ex`](../example/lib/app/shop/workers/process_payment_event.ex)).
And for a change to a row that must not race, the lock is the database's:
`SELECT … FOR UPDATE` inside `Repo.transact`
([`order_service.ex`](../example/lib/app/shop/services/order_service.ex),
`cancel/1`).

**Why:** a lock in Redis can expire while its holder is still working, or
outlive it. The leader and the unique rows live in Postgres next to your
data, so they are decided by the same transactions. (And if a node can't reach
Postgres, it can't act either — that is what stops both halves of a network
split from running the job.)
