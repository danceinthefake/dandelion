# 11. Config and releases

**In Go**, the configuration comes from the environment, and one static binary sits in an image:

```go
type Config struct {
    MaxAge time.Duration `envconfig:"UNPAID_ORDER_MAX_AGE_SECONDS" default:"3600s"`
}
```

```dockerfile
FROM golang:1.x AS build
RUN go build -o /server ./cmd/server
FROM gcr.io/distroless/base
COPY --from=build /server /server
```

**In Elixir**, [`config/runtime.exs`](../example/config/runtime.exs#L27) runs at boot and reads the environment:

```elixir
config :acme, App.Shop.Workers.ExpireUnpaidOrders,
  max_age_seconds: String.to_integer(System.get_env("UNPAID_ORDER_MAX_AGE_SECONDS", "3600"))
```

`mix release` builds a self-contained directory with your code and the Erlang runtime. The [`Dockerfile`](../example/Dockerfile) copies the directory into a slim image (130 MB for the example):

```sh
docker build -t acme .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… acme /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e RELEASE_COOKIE=… -e PHX_HOST=… -p 4000:4000 acme
```

In production, the service redirects plain-HTTP requests to HTTPS. It trusts the `x-forwarded-proto` header of the load balancer. It does not redirect `GET /health` (for probes). If other services call yours over plain HTTP inside the network (`http://acme:4000` in Kubernetes), remove `force_ssl` from [`config/prod.exs`](../example/config/prod.exs).

| Go | Elixir |
|---|---|
| envconfig / viper | `config/runtime.exs` + `System.get_env` |
| compile-time settings (`-ldflags`) | `config/config.exs`, `dev.exs`, `test.exs`, `prod.exs` |
| static binary | `mix release` (the runtime is included, so the host does not need Erlang) |
| `migrate up` in the entrypoint | `bin/migrate` ([`rel/overlays/bin/migrate`](../example/rel/overlays/bin/migrate)) |
| attaching a debugger to prod | `bin/acme remote`, a live shell inside the running server |

**Why:** `runtime.exs` means one image for every environment. A remote shell into a running release is also possible. For example, you can queue a job by hand with `Oban.insert(App.Shop.Workers.ExpireUnpaidOrders.new(%{}))`. Go cannot offer this.
