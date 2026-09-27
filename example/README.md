# shop — dandelion's example service

A small JSON API laid out the way a Go service is: router → handlers →
services → repos → models. It is what `mix dandelion.new` generates; see
[../DESIGN.md](../DESIGN.md).

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
docker build -t shop .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… shop /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… -p 4000:4000 shop
```

In production, plain-HTTP requests are redirected to HTTPS, trusting the
load balancer's `x-forwarded-proto` header; `GET /health` (for probes) is
left alone. If other services call yours over plain HTTP inside the network
(`http://shop:4000` in Kubernetes), remove `force_ssl` from
[`config/prod.exs`](config/prod.exs).

`SECRET_KEY_BASE`: `mix phx.gen.secret`. Unpaid orders: `UNPAID_ORDER_MAX_AGE_SECONDS`
(default 3600), `UNPAID_ORDER_CHECK_EVERY_SECONDS` (default 60).
