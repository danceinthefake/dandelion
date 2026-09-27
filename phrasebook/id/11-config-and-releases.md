[English](../11-config-and-releases.md) · **Bahasa Indonesia**

# 11. Konfigurasi dan release

**Di Go** — konfigurasi dari environment, satu binary statis di dalam image:

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

**Di Elixir** — [`config/runtime.exs`](../../example/config/runtime.exs#L26) dijalankan
saat boot dan membaca environment:

```elixir
config :shop, Shop.Jobs.ExpireUnpaidOrders,
  max_age_seconds: String.to_integer(System.get_env("UNPAID_ORDER_MAX_AGE_SECONDS", "3600")),
  every_seconds: String.to_integer(System.get_env("UNPAID_ORDER_CHECK_EVERY_SECONDS", "60")),
  enabled: config_env() != :test
```

dan `mix release` membangun sebuah folder mandiri — kode kamu plus runtime
Erlang — yang disalin oleh [`Dockerfile`](../../example/Dockerfile) ke image yang ramping
(130 MB untuk contoh ini):

```sh
docker build -t shop .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… shop /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=… -p 4000:4000 shop
```

Di production, request HTTP biasa dialihkan ke HTTPS, berdasarkan header
`x-forwarded-proto` dari load balancer; `GET /health` (untuk probe) tidak
ikut dialihkan. Kalau service lain memanggil service kamu lewat HTTP biasa di
dalam jaringan (`http://shop:4000` di Kubernetes), hapus `force_ssl` dari
[`config/prod.exs`](../../example/config/prod.exs).

| Go | Elixir |
|---|---|
| envconfig / viper | `config/runtime.exs` + `System.get_env` |
| pengaturan saat compile (`-ldflags`) | `config/config.exs`, `dev.exs`, `test.exs`, `prod.exs` |
| binary statis | `mix release` (runtime ikut dibawa; host tidak perlu Erlang) |
| `migrate up` di entrypoint | `bin/migrate` ([`rel/overlays/bin/migrate`](../../example/rel/overlays/bin/migrate)) |
| memasang debugger ke production | `bin/shop remote` — shell langsung di dalam server yang sedang berjalan |

**Kenapa:** `runtime.exs` berarti satu image untuk semua environment. Dan
shell ke dalam release yang sedang berjalan (menjalankan
`Shop.Jobs.ExpireUnpaidOrders.run_now()` dari production, dengan aman) adalah
sesuatu yang tidak bisa ditawarkan Go.
