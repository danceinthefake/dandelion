# Running a cluster

Every node runs the same release and does everything. If you start more nodes, they join one cluster. Nodes find each other through Postgres (`Dandelion.Cluster`, from the dandelion library). You run nothing else.

## Three nodes on one machine

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
./deploy/cluster-proof.sh
```

The compose file starts Postgres, a migration run, three nodes, and nginx as the load balancer on http://localhost:8080. The proof script makes sure that these statements are true:

- Every node sees the other two.
<!-- @frontend-start -->
- `/` serves the Vue app through the load balancer.
<!-- @frontend-end -->
- A broadcast (`Platform.Broadcast`) on one node reaches another node.
- The load balancer answers requests, also when a node is killed.
<!-- @example-start -->
- The confirmation job of a new order runs one time, on one node.
- Another node runs again a job that a killed node left.
- Each `order.created` subscriber runs one time for each order.
- Payment events for one order run in arrival order, also when three nodes race for them. An unfinished payment job of a dead node holds back only its own order, until the rescue.
- A price that you change through one node is read fresh from the cache on every node. A node that joins again starts with an empty cache.
<!-- @example-end -->
<!-- @example-start -->
- `./deploy/failure-proof.sh` cuts the leader off from Postgres. The leader steps down, another node leads, and jobs run one time. Its cache serves only until the entries expire. The script also kills, stops cleanly, and freezes Postgres while orders are made. Every acknowledged order survives, and every order has its events one time. A hung database gets a fast 503 and not a hung request.
- `./deploy/reliability-proof.sh` runs a client that guesses passwords. The client gets 429 with a `retry-after`, while `/health` and the rest of the API still work. A node that stops under load says "draining" on `/health`, finishes its requests, and exits with code 0. No order is refused or lost. The service cuts off a request body that never arrives and a silent client. This takes about 3 minutes.
- `./deploy/backup.sh DIR` and `./deploy/restore.sh DIR` save and restore the cluster. The backup is the database in one `pg_dump` snapshot (the cluster continues to serve) and the uploaded files that the script takes after it. The restore replaces the database, puts the files back, and starts the nodes. `./deploy/backup-proof.sh` backs up a busy cluster, destroys it (the containers, Postgres, and the uploads volume), and rebuilds it from the backup alone. Every order that comes back has its events and is an order that the cluster made. Passwords, search, flags, the audit log, and files are back. The events in flight finish.
- `./deploy/s3-proof.sh` keeps the same files in an S3-compatible bucket and not on the uploads volume. It sets `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, and `S3_SECRET_ACCESS_KEY`. It runs first with SeaweedFS and then with Garage. Downloads from every node match the upload. A delete removes the object. A stopped bucket gives 503 with `Retry-After` and leaves no row. A replaced node still serves the file.
- `./deploy/accounts-proof.sh` tests the accounts. Registration sends a confirmation link. A forgotten password gives the same answer for any address. A link works one time. A short password is refused without use of the link. An expired link is refused. The old sessions end. Five wrong passwords lock an address on every node, also an address that nobody has. A reset unlocks it. A dead mail server delays the email and nothing else. No link is kept in a readable form.
- `./deploy/upgrade-proof.sh` builds a second version of the app (a new column and code that uses it). Its migration runs while the first version serves. The nodes are replaced one at a time under load. No request fails. Version 1 and version 2 serve together. Any node reads back every order.
- `./deploy/dashboard-proof.sh` makes sure that Prometheus reads all three nodes and that Grafana (http://localhost:13000) has the dashboard. The script makes traffic, a rate limit, paused orders, a dead mail server, and a draining node happen. Every query of the dashboard runs, and the panels for those events have data.
- `./deploy/search-proof.sh` tests search with 20 000 products: prefix and multi-word search, accents, a typo, and nasty input. Ten renames are searchable at once from all three nodes. The query uses the GIN index. The script times 200 searches.
- `./deploy/email-proof.sh` makes sure that the mail server gets the confirmation of each order exactly one time. If the mail server is stopped, the service still accepts orders at once, the circuit opens, and the messages wait. When the server returns, all messages arrive, one time each. If the job runs again, it sends nothing.
- `./deploy/audit-proof.sh` makes sure that the changes made through the load balancer are all in one log. The log has the actor, the old and new values, and the request id of the response. Refused changes leave nothing. The log has no secret. The database refuses UPDATE, DELETE, and TRUNCATE from every node.
- `./deploy/uploads-proof.sh` uploads a file through the load balancer. All three nodes (one shared volume) serve the download byte for byte. The file belongs to the customer. Its bytes decide what it is. Ten uploads at once work. A delete removes the bytes. Nodes that are killed in the middle of an upload leave no half file and no row.
- `./deploy/flags-proof.sh` lets an admin pause new orders with a flag through one node. All three nodes then refuse the next orders with a 503. A node that is split off from the cluster serves the old value for one minute at most (the cache time). Then it reads Postgres.
- `./deploy/webhook-proof.sh` lets an admin register a URL. The service delivers each new order to it one time, signed. The script recomputes the signature outside the app. If the receiver is stopped, the circuit opens and the deliveries wait. When the receiver returns, every event arrives.
- `./deploy/rolling-proof.sh` runs a rolling deploy. node1, node2, and node3 stop and start in turn under load, with slow clients in the middle of a request. A stopping node cuts off no request. No order is lost or made twice. One cron leader remains after the deploy.
- `./deploy/idempotency-proof.sh` sends the same order request twenty times at once. The service makes one order. A later request returns the order. This is true also after the nodes were killed in the middle of the request.
- `./deploy/partition-proof.sh` splits the network (`node1 | node2 + node3`). Both halves still reach Postgres. A live broadcast does not cross the split. A cut-off cache goes stale and is emptied after the heal. Jobs and ordered payments still run exactly one time. One cron leader remains. Presence merges after the heal.
<!-- @example-end -->
- A request is a trace in Jaeger under the trace id that the caller sent.
<!-- @example-start -->
- The jobs of an order, which run on another node, are spans of the same trace.
<!-- @example-end -->
- A killed node drops out and joins again when you start it again.
- A time of 15 seconds without Postgres crashes no node and splits nothing. `/health` says 503 in that time.

The secrets in `compose.cluster.yaml` are fixed and public. Use them for local work only.

For real machines, read [vms.md](vms.md).

## What each node needs

| Variable | |
|---|---|
| `DATABASE_URL` | the database, as for a single node |
| `SECRET_KEY_BASE` | the same on every node |
| `PAYMENT_WEBHOOK_TOKEN` | the same on every node: the secret that the payment provider sends in `x-callback-token` |
| `RELEASE_COOKIE` | The same on every node, from a secret store. It lets a node join every other node and run code on it. `mix phx.gen.secret 32` makes one. The node refuses to start without it. |
| `NODE_IP` | the private IP of this node. You need it on VMs, where `hostname -i` can say 127.0.1.1. Containers find their own IP. The node is named `acme@<NODE_IP>`. |
| `NODE_HOST` | Use it instead of `NODE_IP`. It is a name that resolves to the cluster address of this node. Use it for a host or container on several networks. On these hosts, `hostname -i` lists the addresses in no fixed order, and the node can get the name of the wrong address. (The compose file uses it.) |
| `CLUSTER_DATABASE_URL` | Optional. A direct connection to Postgres for discovery. Use it when `DATABASE_URL` goes through PgBouncer in transaction mode, because `LISTEN` does not work through it. |

## Network

Nodes talk to each other on one port, 9100. There is no epmd (see `rel/vm.args.eex`).

- Open 9100 between the app nodes only. Nothing else can reach it. Anyone who can connect with the cookie can run any code on the node.
- Open the HTTP port (4000) to the load balancer only.
- Keep the nodes on a private network with no public IPs.

If a node crashes or stops, the other nodes notice at once, because its connection drops. If the network goes silent, they notice within the `net_ticktime` of Erlang (60 s).

## Metrics

Each node serves `GET /metrics` (Prometheus text) about itself. Point Prometheus at every node and not at the load balancer. Add the series up:

```yaml
scrape_configs:
  - job_name: acme
    metrics_path: /metrics
    static_configs:
      - targets: ["10.0.0.5:4000", "10.0.0.6:4000", "10.0.0.7:4000"]
    # with METRICS_TOKEN set on the nodes:
    # authorization: { credentials: "the-token" }
```

`platform_cluster_nodes_count` is the cluster size as each node sees it. All nodes report the same number while the cluster is whole. A node that is cut off reports a lower number. This is a good alert.

## Tracing

The compose file starts [Jaeger](https://www.jaegertracing.io) and points the nodes at it (`OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318`). Its UI is http://localhost:16686. On your own VMs, point `OTEL_EXPORTER_OTLP_ENDPOINT` at your collector or backend. A request that arrives with a `traceparent` header keeps its trace id. The trace of a caller therefore goes through the load balancer, a node, and the jobs that it queues, on any node that runs them.

## Logins

Every node signs and verifies tokens with the same `SECRET_KEY_BASE`. A login on one node is therefore valid on all nodes, and a node that restarts keeps everyone logged in. If you rotate `SECRET_KEY_BASE`, everyone is logged out. `seed.sh` makes the two demo users (`admin@example.com` and `customer@example.com`, with the password `local-password-1`) in the local cluster. Never create users like that in production.
