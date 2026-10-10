# acme — dandelion's example service

This is a JSON API service with two parts. `lib/platform/` has what every app runs on. `lib/app/<domain>/` has the business, in the layout of a Go service: handlers, services, repos, and models. `mix dandelion.new` generates this service. See [../DESIGN.md](../DESIGN.md).

The parts that are the same in every project come from the [`dandelion`](../lib) library. They are `Dandelion.Cluster`, `Dandelion.Cache`, `Dandelion.Queue`, `Dandelion.Queue.Ordered`, and `Dandelion.PubSub`. `platform/` wires them up. It also holds what belongs to this app: the endpoint, the cron schedule, and the subscriptions. The router is in `lib/app/`.

```
lib/
  platform/                 same in every dandelion project
    application.ex          what starts, in order (≈ main.go)
    database/repo.ex        ≈ the *sql.DB pool
    web/                    ≈ the web server: endpoint, health, errors
    queue.ex                ≈ Cloud Tasks: background jobs (Oban, set up by Dandelion.Queue)
    cron.ex                 ≈ Cloud Scheduler: recurring jobs, once per cluster
    pubsub.ex               ≈ Google Pub/Sub topics: who subscribes to what (mechanism: Dandelion.PubSub)
    realtime/               ≈ Pusher presence: who is online, across nodes
    release.ex              migrations in production
  app/
    router.ex               ≈ the router in main.go: mounts each domain's routes
    shop/                   one domain; add more the same way
      routes.ex             the domain's paths and who may call them
      handlers/             HTTP: params → service → JSON
      channels/             WebSocket: the live order feed
      workers/              background work
      models/  repos/  services/
```

To add another domain, run `mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer`. It writes the layers, a migration, tests, and the routes for one resource in `lib/app/billing/`. The shape is the same as `shop`. Then run `mix ecto.migrate`.

Module names follow the folders. For example, `lib/app/shop/services/order_service.ex` is `App.Shop.Services.OrderService`.

```sh
mise install              # Erlang + Elixir (mise.toml)
docker compose up -d      # Postgres 18 on localhost:55432
mise exec -- mix setup    # deps + database
mise exec -- mix test
mise exec -- mix credo --strict
mise exec -- mix phx.server   # http://localhost:4000
```

The Vue and blessing-ui frontend is in `assets/`. You need Node. Run `cd assets && npm install && npm run build` to put it in `priv/static/app`. Phoenix serves it at `/`. While you work on it, run `npm run dev`. This runs Vite on :5173 and forwards `/api` and `/socket` to Phoenix. The frontend shows the live order feed (an order made on any node appears at once) and who is online. It also has a new-order form and the detail of an order. `mix dandelion.new --no-frontend` leaves it out.

## Release image

This is like a Go multi-stage Dockerfile. `mix release` builds a self-contained release with the Erlang runtime. The Dockerfile copies the release into a slim Debian image.

```sh
docker build -t acme .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PAYMENT_WEBHOOK_TOKEN=… -e RELEASE_COOKIE=… -e PHX_HOST=… -p 4000:4000 acme
```

For more than one node, read [deploy/README.md](deploy/README.md). It describes a local 3-node cluster behind nginx and what each node needs.

In production, the service redirects plain-HTTP requests to HTTPS. It trusts the `x-forwarded-proto` header of the load balancer. It does not redirect `GET /health` (for probes). If other services call yours over plain HTTP inside the network (`http://acme:4000` in Kubernetes), remove `force_ssl` from [`config/prod.exs`](config/prod.exs).

Make `SECRET_KEY_BASE` with `mix phx.gen.secret`. `PAYMENT_WEBHOOK_TOKEN` is the secret that the payment provider sends in `x-callback-token`. The service cancels unpaid orders after `UNPAID_ORDER_MAX_AGE_SECONDS` (default 3600). It checks every minute (`lib/platform/cron.ex`).

## Try the API

`mix setup` seeds two products (`TEA-01` and `CUP-02`) and two users, `admin@example.com` and `customer@example.com`. Both users have the password `local-password-1`. This password is public and is for local use only. Orders need a login. The service prices orders from the products table. Send the SKU and the quantity. The service ignores a `price_cents` in the request. An unknown SKU gets a 400.

```sh
# log in: a signed token comes back
TOKEN=$(curl -s -X POST localhost:4000/api/session -H 'content-type: application/json' \
  -d '{"email":"customer@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -X POST localhost:4000/api/orders -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":2}]}'

curl localhost:4000/api/orders -H "authorization: Bearer $TOKEN"   # your orders, not everyone's
```

New users register with `POST /api/users` (`{"email": …, "password": …}`, at least 10 characters). They are customers. The service never reads the role from a request.

## Logins and who may do what

[`lib/app/accounts/`](lib/app/accounts) is a small, real login. It is a place to start and not a library to depend on.

- Passwords: The service hashes passwords with PBKDF2-SHA256 from `:crypto` of Erlang, so it needs no dependency. It uses 600 000 iterations and a salt for each password. The hash stores the iteration count, so you can raise it later. A login with an unknown email costs the same time as a wrong password and gives the same answer.
- Tokens: The tokens are signed and expire after a day (`Phoenix.Token`). The service stores nothing, so any node accepts a token that another node issued. You cannot revoke a token before it expires. `App.Accounts.Handlers.Token` says what to do if you need that.
- The plug [`App.Accounts.Handlers.Auth`](lib/app/accounts/handlers/auth.ex) guards routes with the pipelines in [`router.ex`](lib/app/router.ex). `:authenticated` needs a valid token, or the answer is 401. `:admin` needs the admin role, or the answer is 403. The catalog and the payment webhook (which has its own token) stay public.
- Who can see what is a rule, so it is in the service. An order belongs to the user who made it. A customer gets their own orders. For the order of another customer, the answer is 404. This is the same answer as for an order that does not exist. An admin sees all orders. Only admins change prices, and only admins see the live feed.
- The web console signs in and then shows the live feed to admins. It keeps the token in `sessionStorage`. It sends the token as a header and as the `token` parameter of the WebSocket.

Password reset, address confirmation, and lockout after failed attempts also exist (see [../evidence/25-accounts/](../evidence/25-accounts/)). Two-factor login does not exist.

## Metrics

`GET /metrics` returns Prometheus text. It has these metrics:
- Request and handler durations.
- Database query time and pool-queue time.
- Oban jobs: duration by queue, worker, and outcome, and exceptions.
- The hits and misses of the cache.
- The number of nodes in the cluster as this node sees it.
- VM memory.

The list in [`lib/platform/web/telemetry.ex`](lib/platform/web/telemetry.ex) defines what the service reports. To add a metric, add a line. Keep the endpoint on your private network. If you set `METRICS_TOKEN`, the endpoint also needs `Authorization: Bearer <token>`.

## Tracing

Every request, database query, and background job is a span ([OpenTelemetry](https://opentelemetry.io)). A job continues the trace of the request that queued it, on any node that runs the job. Set `OTEL_EXPORTER_OTLP_ENDPOINT` (for example `http://jaeger:4318`). The nodes then send spans there over OTLP/HTTP, to Jaeger, Tempo, Honeycomb, or any collector. Without it, the service exports nothing and does not try to connect. `OTEL_SERVICE_NAME` names the service (default: the app). Each node tags its spans with `service.instance.id`, so a trace shows which node did what.

`docker compose -f deploy/compose.cluster.yaml up` starts Jaeger next to the nodes. Make an order, then open http://localhost:16686 and look at the trace. It shows the request on one node and the jobs of the order on another node.

The wiring is five lines in [`lib/platform/application.ex`](lib/platform/application.ex) and a block in [`config/runtime.exs`](config/runtime.exs). The service keeps every span. In production, sample the spans (`OTEL_TRACES_SAMPLER=parentbased_traceidratio` and `OTEL_TRACES_SAMPLER_ARG=0.1`).

