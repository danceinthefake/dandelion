# 17. One node or many

A dandelion service is the same release if you run one copy or ten. Nodes join by themselves through Postgres ([`Dandelion.Cluster`](../lib/dandelion/cluster.ex)). Then the pieces from pages 13 to 15 work across them. Nothing in your domain code changes.

## "My service mesh"

```go
resp, err := http.Get("http://inventory-svc:8080/stock/" + sku)   // + retries, mTLS, a mesh
```

Between two services, you still use HTTP. Between the nodes of one service, you do not need a mesh. The nodes are connected, and a node can call a function on another node directly.

```elixir
:erpc.call(other_node, App.Shop.Services.OrderService, :get, [42])   # runs there, answers here
Node.list()                                                          # who is connected
```

You rarely do this by hand. The cache, pub/sub, presence, and queues already use the connections. This example shows that it is not magic. Treat the connection with care: anyone who has the cookie can run any code on every node. Keep the nodes on a private network (see below).

## What each node does

Every node runs everything: web, workers, queues, and cron (on the leader node). There are no roles. To scale, start another copy.

| Piece | Across nodes | If a node dies |
|---|---|---|
| Web, WebSocket | any node answers, and a load balancer spreads the requests | clients reconnect to another node |
| Jobs, ordered queue, cron | work spreads over nodes | another node runs its job again |
| `Platform.Broadcast`, presence | reaches every node | the others drop its presence, and in-flight broadcasts are lost |
| Cache | one copy for each node, cleared together | that copy is gone (it is a cache) |
| Metrics (`/metrics`) | each node reports itself, and Prometheus scrapes them all | its counters start again from zero |

## A network split

Two halves of the cluster cannot see each other:

| Piece | What happens | Why |
|---|---|---|
| Jobs, cron | a half without Postgres does nothing | they live in Postgres |
| Data | unchanged | transactions and row locks |
| Cache | the halves drift for up to 60 s and then empty on rejoin | short TTL |
| Broadcast | messages between halves are lost | fire and forget, so use a topic for what must arrive |
| Presence | each half sees its own users, and they merge after the heal | CRDT |

The rule behind it (DESIGN §10.3) is this: Postgres decides, and memory only makes things faster. Anything that must survive or happen exactly one time goes through the database.

## Try it

```sh
cd example
docker compose -f deploy/compose.cluster.yaml up -d --build
./deploy/cluster-proof.sh     # the claims above, checked: cache, queue order, a killed node…
```

Running it on real VMs: [`deploy/vms.md`](../example/deploy/vms.md).

**Why:** A Go service that scales out needs Redis, a broker, a scheduler, and a mesh. They stand in for what its instances cannot do together. The BEAM has nodes that can do this together. The extras therefore shrink to a few libraries and one database.
