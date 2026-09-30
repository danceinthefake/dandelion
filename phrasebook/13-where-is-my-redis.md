# 13. Where is my Redis?

In a Go service, Redis usually does three jobs: **pub/sub** between
instances, a **cache**, and "who is online". In dandelion each is a library
inside the app. No Redis to run, pay for or reconnect to.

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
The message reaches the subscribers on **every node**, because the nodes are
connected ([17](17-one-node-or-many.md)).

Like Redis pub/sub it is **fire and forget**: whoever listens right now gets
it; if nobody does, it's gone. For an event that must not be lost, use
[14](14-queues-and-topics.md).

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

What is different from Redis:

- **Each node has its own copy**, in its own memory: a read costs no network
  trip. Redis is one shared copy, a network trip away.
- So **deleting has to reach every node**: `Cache.delete/1` does it (over
  `Platform.Broadcast`). Call it **after** the database change is committed;
  before, another node could read the old row and cache it again.
- A node that joins (or rejoins after a network split) empties its cache, and
  every entry expires after 60 s, so a missed delete heals itself.
- The loader runs **in your own process**, on your own database connection —
  inside a transaction it sees that transaction's writes. So two requests
  missing the same key at once both load it, like a plain Redis get-then-set.

## Who is online

`Platform.Realtime.Presence` tracks each connected browser and merges the
lists of all nodes. An entry disappears when the connection does; when a node
dies, the others drop its entries. No `EXPIRE` and no heartbeat to write.

**Why:** Redis exists because Go instances can't talk to each other. BEAM
nodes can — so the cache, the pub/sub and the presence list live where the
code runs, and the network is used only to tell the other nodes what
changed.
