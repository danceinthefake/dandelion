# 13. Where is my Redis?

In a Go service, Redis usually does three jobs: pub/sub between instances, a cache, and "who is online". In dandelion, each job is a library inside the app. You do not run, pay for, or reconnect to a Redis.

| You used Redis for | Here |
|---|---|
| `PUBLISH` / `SUBSCRIBE` | `Platform.Broadcast` ([Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub)) |
| `GET` / `SET` with a TTL | `Dandelion.Cache` ([Cachex](https://hexdocs.pm/cachex)) |
| a set of online users, with expiry | `Platform.Realtime.Presence` |

## Pub/sub

```go
rdb.Publish(ctx, "orders", payload)                 // on any instance
sub := rdb.Subscribe(ctx, "orders")                 // on every instance
for msg := range sub.Channel() { push(msg) }
```

```elixir
Phoenix.PubSub.broadcast(Platform.Broadcast, "orders", {:order_created, order})  # any node

Phoenix.PubSub.subscribe(Platform.Broadcast, "orders")        # in the process that wants them
receive do
  {:order_created, order} -> push(order)
end
```

`OrderService.create/1` does the broadcast
([`order_service.ex`](../example/lib/app/shop/services/order_service.ex)),
and the channel that listens is
[`order_feed_channel.ex`](../example/lib/app/shop/channels/order_feed_channel.ex).
The message reaches the subscribers on every node, because the nodes are connected ([17](17-one-node-or-many.md)).

Like Redis pub/sub, it is fire and forget. Whoever listens at that moment gets the message. If nobody listens, the message is gone. For an event that you must not lose, use [14](14-queues-and-topics.md).

## Cache

```go
val, err := rdb.Get(ctx, key).Result()
if err == redis.Nil {
    val = loadFromDB()
    rdb.Set(ctx, key, val, time.Minute)
}
```

```elixir
Cache.fetch({:product, sku}, fn -> ProductRepo.get(sku) end)   # load on a miss, keep 60 s
Cache.delete({:product, sku})                                   # on every node
```

([`product_service.ex`](../example/lib/app/shop/services/product_service.ex),
[`Dandelion.Cache`](../lib/dandelion/cache.ex).)

These points differ from Redis:

- Each node has its own copy, in its own memory. A read costs no network trip. Redis is one shared copy, and it is a network trip away.
- A delete must therefore reach every node. `Cache.delete/1` does this over `Platform.Broadcast`. Call it after the database change is committed. If you call it before, another node can read the old row and cache it again.
- A node that joins empties its cache. A node that joins again after a network split also empties its cache. Every entry expires after 60 s, so a missed delete heals itself.
- The loader runs in your own process, on your own database connection. Inside a transaction, it sees the writes of that transaction. Two requests that miss the same key at once both load it. This is like a plain get-then-set in Redis.

## Who is online

`Platform.Realtime.Presence` tracks each connected browser and merges the lists of all nodes. An entry disappears when its connection disappears. When a node dies, the other nodes drop its entries. You write no `EXPIRE` and no heartbeat.

**Why:** Redis exists because Go instances cannot talk to each other. BEAM nodes can. The cache, the pub/sub, and the presence list therefore live where the code runs. The network tells the other nodes only what changed.
