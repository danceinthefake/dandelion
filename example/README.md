# acme — dandelion's example service

A JSON API service in two parts: `lib/platform/`, what every app runs on,
and `lib/app/<domain>/`, the business, laid out the way a Go service is
(handlers → services → repos → models). It is what `mix dandelion.new`
generates; see [../DESIGN.md](../DESIGN.md).

```
lib/
  platform/                 same in every dandelion project
    application.ex          what starts, in order (≈ main.go)
    database/repo.ex        ≈ the *sql.DB pool
    web/                    ≈ the web server: endpoint, router (every route), health, errors
    release.ex              migrations in production
  app/
    shop/                   one domain; add more the same way
      handlers/             HTTP: params → service → JSON
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

## Release image

≈ a Go multi-stage Dockerfile: `mix release` builds a self-contained
release (the Erlang runtime included), copied into a slim Debian image.

```sh
docker build -t acme .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… -p 4000:4000 acme
```

In production, plain-HTTP requests are redirected to HTTPS, trusting the
load balancer's `x-forwarded-proto` header; `GET /health` (for probes) is
left alone. If other services call yours over plain HTTP inside the network
(`http://acme:4000` in Kubernetes), remove `force_ssl` from
[`config/prod.exs`](config/prod.exs).

`SECRET_KEY_BASE`: `mix phx.gen.secret`. Unpaid orders are cancelled after
`UNPAID_ORDER_MAX_AGE_SECONDS` (default 3600), checked every minute
(`lib/platform/cron.ex`).
