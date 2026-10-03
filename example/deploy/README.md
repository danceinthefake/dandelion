# Running a cluster

Every node runs the same release and does everything; start more nodes and
they join one cluster. Nodes find each other through Postgres
(`Dandelion.Cluster`, from the dandelion library), so there's nothing else to run.

## Three nodes on one machine

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
./deploy/cluster-proof.sh
```

Postgres, a migration run, three nodes and nginx as the load balancer on
http://localhost:8080. The proof script checks that:

- every node sees the other two;
<!-- @frontend-start -->
- `/` serves the Vue app through the load balancer;
<!-- @frontend-end -->
- a broadcast (`Platform.Broadcast`) on one node reaches another;
- requests through the load balancer are answered, also with a node killed;
<!-- @example-start -->
- a new order's confirmation job runs once, on one node;
- a job left behind by a killed node is run again by another node;
- each `order.created` subscriber runs once per order;
- payment events for one order run in arrival order even when three nodes race for them, and a dead node's unfinished payment job holds back only its own order, until rescued;
- a price changed through one node is read fresh from the cache on every node, and a node that joins again starts with an empty cache;
<!-- @example-end -->
<!-- @example-start -->
- `./deploy/failure-proof.sh`: the leader cut off from Postgres (it steps down, another
  node leads, jobs run once, its cache serves only until the entries expire) and
  Postgres killed, stopped cleanly and frozen while orders are being made: every
  acknowledged order survives and every order has its events, once; a hung database
  gets a quick 503, not a hung request;
- `./deploy/partition-proof.sh`: a network split (`node1 | node2 + node3`, both
  halves still reach Postgres): a live broadcast doesn't cross it, a cut-off
  cache goes stale and is emptied on the heal, jobs and ordered payments still
  run exactly once, one cron leader, presence merges after the heal;
<!-- @example-end -->
- a request is a trace in Jaeger under the trace id it was sent;
<!-- @example-start -->
- an order's jobs, run on another node, are spans of the same trace;
<!-- @example-end -->
- a killed node drops out, and rejoins when started again;
- 15 seconds without Postgres crashes no node and splits nothing
  (`/health` says 503 meanwhile).

The secrets in `compose.cluster.yaml` are fixed and public: local only.

On real machines: [vms.md](vms.md).

## What each node needs

| Variable | |
|---|---|
| `DATABASE_URL` | the database, as for a single node |
| `SECRET_KEY_BASE` | the same on every node |
| `PAYMENT_WEBHOOK_TOKEN` | the same on every node: the secret the payment provider sends in `x-callback-token` |
| `RELEASE_COOKIE` | **the same on every node, from a secret store**. It lets a node join — and run code on — every other node. `mix phx.gen.secret 32` makes one. The node refuses to start without it. |
| `NODE_IP` | this node's private IP. Needed on VMs (where `hostname -i` can say 127.0.1.1); containers find their own. The node is named `acme@<NODE_IP>`. |
| `NODE_HOST` | instead of `NODE_IP`: a name that resolves to this node's cluster address. For a host or container on **several networks**, where `hostname -i` lists the addresses in no fixed order and the node could be named after the wrong one. (The compose file uses it.) |
| `CLUSTER_DATABASE_URL` | optional: a direct connection to Postgres for discovery, when `DATABASE_URL` goes through PgBouncer in transaction mode (`LISTEN` doesn't work through it) |

## Network

Nodes talk to each other on **one port, 9100** (no epmd; `rel/vm.args.eex`).

- Open **9100 between the app nodes only** — nothing else may reach it:
  whoever can connect with the cookie can run any code on the node.
- Open the HTTP port (4000) to the load balancer only.
- Keep the nodes on a private network, no public IPs.

A node that dies is noticed at once when its connection drops (a crash, a
stop); if the network just goes silent, within Erlang's `net_ticktime`
(60 s).

## Metrics

Each node serves `GET /metrics` (Prometheus text) about itself; point Prometheus
at **every** node, not at the load balancer, and add the series up:

```yaml
scrape_configs:
  - job_name: acme
    metrics_path: /metrics
    static_configs:
      - targets: ["10.0.0.5:4000", "10.0.0.6:4000", "10.0.0.7:4000"]
    # with METRICS_TOKEN set on the nodes:
    # authorization: { credentials: "the-token" }
```

`platform_cluster_nodes_count` is the cluster size as each node sees it: all
nodes report the same number while the cluster is whole, and a node that is cut
off reports less — a good alert.

## Tracing

The compose file starts [Jaeger](https://www.jaegertracing.io) and points the
nodes at it (`OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318`); its UI is
http://localhost:16686. On your own VMs, point `OTEL_EXPORTER_OTLP_ENDPOINT` at
your collector or backend. A request that arrives with a `traceparent` header
keeps its trace id, so a caller's trace goes through the load balancer, a node,
and the jobs it queues, wherever they run.

## Logins

Every node signs and checks tokens with the same `SECRET_KEY_BASE`, so a login on
one node is good on all of them, and a node that restarts keeps everyone logged
in. Rotating `SECRET_KEY_BASE` logs everyone out. `seed.sh` makes the two demo
users (`admin@example.com`, `customer@example.com`, password `local-password-1`)
in the local cluster: never create users like that in production.

