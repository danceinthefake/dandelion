# acme — dandelion's example service

A JSON API service in two parts: `lib/platform/`, what every app runs on,
and `lib/app/<domain>/`, the business, laid out the way a Go service is
(handlers → services → repos → models). It is what `mix dandelion.new`
generates; see [../DESIGN.md](../DESIGN.md).

The parts that are the same in every project — `Dandelion.Cluster`,
`Dandelion.Cache`, `Dandelion.Queue`, `Dandelion.Queue.Ordered`,
`Dandelion.PubSub` — come from the [`dandelion`](../lib) library; `platform/`
wires them up and holds what belongs to *this* app (router, endpoint, cron
schedule, subscriptions).

```
lib/
  platform/                 same in every dandelion project
    application.ex          what starts, in order (≈ main.go)
    database/repo.ex        ≈ the *sql.DB pool
    web/                    ≈ the web server: endpoint, router (every route), health, errors
    queue.ex                ≈ Cloud Tasks: background jobs (Oban, set up by Dandelion.Queue)
    cron.ex                 ≈ Cloud Scheduler: recurring jobs, once per cluster
    pubsub.ex               ≈ Google Pub/Sub topics: who subscribes to what (mechanism: Dandelion.PubSub)
    realtime/               ≈ Pusher presence: who is online, across nodes
    release.ex              migrations in production
  app/
    shop/                   one domain; add more the same way
      handlers/             HTTP: params → service → JSON
      channels/             WebSocket: the live order feed
      workers/              background work
      models/  repos/  services/
```

Module names follow the folders: `lib/app/shop/services/order_service.ex`
is `App.Shop.Services.OrderService`.

```sh
mise install              # Erlang + Elixir (mise.toml)
docker compose up -d      # Postgres 18 on localhost:55432
mise exec -- mix setup    # deps + database
mise exec -- mix test
mise exec -- mix credo --strict
mise exec -- mix phx.server   # http://localhost:4000
```

The Vue + blessing-ui frontend is in `assets/` (Node needed): `cd assets &&
npm install && npm run build` puts it in `priv/static/app`, and Phoenix serves
it at `/`. While working on it, `npm run dev` runs Vite on :5173 and forwards
`/api` and `/socket` to Phoenix. It shows the live order feed (an order made
on any node appears at once), who's online, a new-order form and an order's
detail. `mix dandelion.new --no-frontend` leaves it out.

## Release image

≈ a Go multi-stage Dockerfile: `mix release` builds a self-contained
release (the Erlang runtime included), copied into a slim Debian image.

```sh
docker build -t acme .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PAYMENT_WEBHOOK_TOKEN=… -e RELEASE_COOKIE=… -e PHX_HOST=… -p 4000:4000 acme
```

More than one node: [deploy/README.md](deploy/README.md) — a local 3-node
cluster behind nginx, and what each node needs.

In production, plain-HTTP requests are redirected to HTTPS, trusting the
load balancer's `x-forwarded-proto` header; `GET /health` (for probes) is
left alone. If other services call yours over plain HTTP inside the network
(`http://acme:4000` in Kubernetes), remove `force_ssl` from
[`config/prod.exs`](config/prod.exs).

`SECRET_KEY_BASE`: `mix phx.gen.secret`. `PAYMENT_WEBHOOK_TOKEN`: the secret the payment provider sends in `x-callback-token`. Unpaid orders are cancelled after
`UNPAID_ORDER_MAX_AGE_SECONDS` (default 3600), checked every minute
(`lib/platform/cron.ex`).

## Try the API

`mix setup` seeds two products (`TEA-01`, `CUP-02`). Orders are **priced from the
products table** — send only the SKU and the quantity; a `price_cents` in the
request is ignored, and an unknown SKU is a 400:

```sh
curl -X POST localhost:4000/api/orders -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":2}]}'
curl -X PUT localhost:4000/api/products/TEA-01 -H 'content-type: application/json' \
  -d '{"price_cents":1600}'          # the next order pays 1600; old orders keep their price
```

## Metrics

`GET /metrics` is Prometheus text: request and handler durations, database
query and pool-queue time, Oban jobs (duration by queue, worker and outcome;
exceptions), the cache's hits and misses, the number of nodes in the cluster as
this node sees it, and VM memory. What is reported is the list in
[`lib/platform/web/telemetry.ex`](lib/platform/web/telemetry.ex): add a line
to add a metric. Keep the endpoint on your private network; setting
`METRICS_TOKEN` also requires `Authorization: Bearer <token>`.

