# Running a cluster

Every node runs the same release and does everything; start more nodes and
they join one cluster. Nodes find each other through Postgres
(`lib/platform/cluster.ex`), so there's nothing else to run.

## Three nodes on one machine

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
./deploy/cluster-proof.sh
```

Postgres, a migration run, three nodes and nginx as the load balancer on
http://localhost:8080. The proof script checks that:

- every node sees the other two;
- a broadcast (`Platform.Broadcast`) on one node reaches another;
- requests through the load balancer are answered, also with a node killed;
- a new order's confirmation job runs once, on one node;
- a job left behind by a killed node is run again by another node;
- each `order.created` subscriber runs once per order;
- payment events for one order run in arrival order even when three nodes race for them, and a dead node's unfinished payment job holds back only its own order, until rescued;
- a killed node drops out, and rejoins when started again;
- 15 seconds without Postgres crashes no node and splits nothing
  (`/health` says 503 meanwhile).

The secrets in `compose.cluster.yaml` are fixed and public: local only.

## What each node needs

| Variable | |
|---|---|
| `DATABASE_URL` | the database, as for a single node |
| `SECRET_KEY_BASE` | the same on every node |
| `PAYMENT_WEBHOOK_TOKEN` | the same on every node: the secret the payment provider sends in `x-callback-token` |
| `RELEASE_COOKIE` | **the same on every node, from a secret store**. It lets a node join — and run code on — every other node. `mix phx.gen.secret 32` makes one. The node refuses to start without it. |
| `NODE_IP` | this node's private IP. Needed on VMs (where `hostname -i` can say 127.0.1.1); containers find their own. The node is named `acme@<NODE_IP>`. |
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
