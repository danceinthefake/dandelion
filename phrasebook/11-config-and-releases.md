**English** · [Bahasa Indonesia](id/11-config-and-releases.md)

# 11. Config and releases

**In Go** — config from the environment, one static binary in an image:

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

**In Elixir** — [`config/runtime.exs`](../example/config/runtime.exs#L26) runs at
boot and reads the environment:

```elixir
config :shop, Shop.Jobs.ExpireUnpaidOrders,
  max_age_seconds: String.to_integer(System.get_env("UNPAID_ORDER_MAX_AGE_SECONDS", "3600")),
  every_seconds: String.to_integer(System.get_env("UNPAID_ORDER_CHECK_EVERY_SECONDS", "60")),
  enabled: config_env() != :test
```

and `mix release` builds a self-contained directory — your code plus the
Erlang runtime — which the [`Dockerfile`](../example/Dockerfile) copies into a slim
image (130 MB for the example):

```sh
docker build -t shop .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… shop /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… -p 4000:4000 shop
```

| Go | Elixir |
|---|---|
| envconfig / viper | `config/runtime.exs` + `System.get_env` |
| compile-time settings (`-ldflags`) | `config/config.exs`, `dev.exs`, `test.exs`, `prod.exs` |
| static binary | `mix release` (runtime included; no Erlang needed on the host) |
| `migrate up` in the entrypoint | `bin/migrate` ([`rel/overlays/bin/migrate`](../example/rel/overlays/bin/migrate)) |
| attaching a debugger to prod | `bin/shop remote` — a live shell inside the running server |

**Why:** `runtime.exs` means one image for every environment. And a remote
shell into a running release (`Shop.Jobs.ExpireUnpaidOrders.run_now()` from
production, safely) is something Go can't offer.
