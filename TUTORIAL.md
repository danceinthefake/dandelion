# From zero to a three-node cluster

About ten minutes of your time, plus the first Docker build (a few minutes).
You need Erlang and Elixir ([mise](https://mise.jdx.dev) installs them), Docker,
and `curl`. Written for `dandelion_new` 0.2.0 or later.

## 1. Make a project

```sh
mix archive.install hex dandelion_new
mix dandelion.new shop_demo
cd shop_demo
```

You get a service laid out like a Go service (`lib/platform/`, `lib/app/<domain>/`),
a Vue console, and a compose file that runs **three copies of it** behind nginx.

## 2. Start the cluster

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
deploy/seed.sh      # two products, two users
```

The first build takes a few minutes (the next ones seconds). When
`curl localhost:8080/health` says `{"status":"ok"}`, three nodes are running and
have found each other through Postgres: nothing else to install.

## 3. Sign in and make orders on two nodes

Open http://localhost:8080 in **two browsers**, sign in as `admin@example.com`
with password `local-password-1` (public, local only). The page says which node
you are connected to; nginx gives each browser a node. Make an order in one:
it appears in the other at once, and "online now" counts both.

![two browsers on two different nodes](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/02-live-feed/live-feed.gif)

No Redis, no socket server: the nodes are connected to each other. (Claim 02 of
the [evidence](evidence/).)

The same from the command line. Log in as the customer, make an order, and see
that the API needs the token:

```sh
TOKEN=$(curl -s -X POST localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"customer@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":2}]}'
curl -o /dev/null -w '%{http_code}\n' localhost:8080/api/orders      # 401: no token
```

The price comes from the products table, never from the request. A customer sees
only their own orders; the token works on any of the three nodes (it is signed,
not stored).

## 4. Follow one order across nodes

Open http://localhost:16686 (Jaeger). Service: your app's name (`shop_demo`),
operation `POST /api/orders`, **Find Traces**, open one. You see the request, its
database queries, and the two background jobs the order queued — and the jobs may
have run on a **different node** than the request. Click a span, open *Process*:
`service.instance.id` is the node.

## 5. Kill a node

```sh
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 3
docker compose -f deploy/compose.cluster.yaml kill -s KILL node2
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 2, within seconds
curl localhost:8080/health                                              # still ok
docker compose -f deploy/compose.cluster.yaml start node2              # back to 3 in ~15 s
```

Jobs a dead node was running are run again by the others, and a payment event for
one order is never applied before the one that came first.

## 6. Check the claims yourself

```sh
deploy/cluster-proof.sh        # ~10 min: broadcast, jobs, ordering, cache, logins, traces, outage
deploy/partition-proof.sh      # ~4 min: a network split into node1 | node2+node3, then the heal
```

Each line it prints is a claim; [`evidence/`](evidence/) has the same runs
recorded, the negative controls (the same proof must *fail* when a feature is
broken on purpose), and [what is not proven](evidence/LIMITS.md).

## 7. Add your own resource

```sh
docker compose up -d           # Postgres on localhost:55432
mix setup && mix test          # about a minute the first time
mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer paid:boolean
mix ecto.migrate && mix test
mix phx.server                 # http://localhost:4000
```

It writes the model, repo, service, handler, migration, tests and routes in the
project's own layout, behind the login. Add the rules (who may see what, a
cancel, an event) by hand the way `lib/app/shop/` does.

## 8. Clean up

```sh
docker compose -f deploy/compose.cluster.yaml down -v
```

## Where to go next

[`phrasebook/`](phrasebook/) maps each Go habit to the Elixir way (19 short
pages), and [`DESIGN.md`](DESIGN.md) says why it's built this way.
