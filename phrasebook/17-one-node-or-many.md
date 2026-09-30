# 17. One node or many

A dandelion service is the same release whether you run one copy or ten.
Nodes join by themselves (through Postgres,
[`lib/platform/cluster.ex`](../example/lib/platform/cluster.ex)) and then
the pieces from 13–15 work across them. Nothing in your domain code changes.

## "My service mesh"

```go
resp, err := http.Get("http://inventory-svc:8080/stock/" + sku)   // + retries, mTLS, a mesh
```

Between two *services* you still use HTTP. Between **nodes of one service**
you don't need a mesh: they're connected, and a node can call a function on
another node directly.

```elixir
:erpc.call(other_node, App.Shop.Services.OrderService, :get, [42])   # runs there, answers here
Node.list()                                                          # who is connected
```

You rarely do this by hand: the cache, pub/sub, presence and queues already
use the connections. It is here so you know it is not magic — and so you
treat the connection with respect: **anyone holding the cookie can run any
code on every node**. Keep the nodes on a private network (below).

## What each node does

Every node runs everything: web, workers, queues, cron (whichever node is
leader). There are no roles. To scale, start another copy.

| Piece | Across nodes | If a node dies |
|---|---|---|
| Web, WebSocket | any node answers; a load balancer spreads them | clients reconnect to another |
| Jobs, ordered queue, cron | work spreads over nodes | its job is run again by another |
| `Platform.Broadcast`, presence | reaches every node | the others drop its presence; in-flight broadcasts are lost |
| Cache | one copy per node, cleared together | that copy is gone (it is a cache) |

## A network split

Two halves of the cluster that can't see each other:

| Piece | What happens | Why |
|---|---|---|
| Jobs, cron | a half without Postgres does nothing | they live in Postgres |
| Data | unchanged | transactions and row locks |
| Cache | halves drift for up to 60 s, then empty on rejoin | short TTL |
| Broadcast | messages between halves are lost | fire and forget; use a topic for what must arrive |
| Presence | each half sees its own users; they merge when it heals | CRDT |

The rule behind it (DESIGN §10.3): **Postgres decides, memory only makes
things faster.** Anything that must survive or happen exactly once goes
through the database.

## Try it

```sh
cd example
docker compose -f deploy/compose.cluster.yaml up -d --build
./deploy/cluster-proof.sh     # the claims above, checked: cache, queue order, a killed node…
```

Running it on real VMs: [`deploy/vms.md`](../example/deploy/vms.md).

**Why:** a Go service that scales out needs Redis, a broker, a scheduler and
a mesh to stand in for what its instances can't do together. The BEAM has
nodes that can — so the extras shrink to a few libraries and one database.
