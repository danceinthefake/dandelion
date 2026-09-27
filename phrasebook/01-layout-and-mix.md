# 1. Project layout and `mix`

**In Go**

```
go.mod                         module + dependencies
cmd/server/main.go
internal/http/  internal/service/  internal/repo/  internal/model/
go run ./cmd/server   go test ./...   gofmt   golangci-lint
```

**In Elixir** — `mix` is `go` (build, run, test, deps) in one tool:

| Go | Elixir |
|---|---|
| `go.mod` | [`mix.exs`](../example/mix.exs) — `deps/0` lists dependencies |
| `go mod download` | `mix deps.get` |
| `go run ./cmd/server` | `mix phx.server` |
| `go test ./...` | `mix test` |
| `gofmt` | `mix format` |
| `golangci-lint` | `mix credo --strict` |
| `go vet` | `mix compile --warnings-as-errors` |
| `cmd/server/main.go` | [`lib/platform/application.ex`](../example/lib/platform/application.ex) |
| router, middleware | [`lib/platform/web/`](../example/lib/platform/web) — every route in `router.ex` |
| `internal/<domain>/http/` | [`lib/app/shop/handlers/`](../example/lib/app/shop/handlers) |
| `internal/<domain>/service/` | [`lib/app/shop/services/`](../example/lib/app/shop/services) |
| `internal/<domain>/repo/` | [`lib/app/shop/repos/`](../example/lib/app/shop/repos) |
| `internal/<domain>/model/` | [`lib/app/shop/models/`](../example/lib/app/shop/models) |
| `migrations/` | [`priv/repo/migrations/`](../example/priv/repo/migrations) |

Dependencies, from [`mix.exs`](../example/mix.exs#L40):

```elixir
defp deps do
  [
    {:phoenix, "~> 1.8.15"},
    {:ecto_sql, "~> 3.13"},
    {:postgrex, "~> 0.22"},
    # …
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

**Why:** the folder names are the same on purpose. `lib/platform/` is what
every app runs on — the same in every dandelion project; `lib/app/<domain>/`
is your business, one folder per domain (`shop` here). Module names follow
the folders, like Go packages: `lib/app/shop/services/order_service.ex` is
`App.Shop.Services.OrderService`. Services don't know about HTTP, so the
same code runs from a handler, a worker, a script or a test.
