**English** · [Bahasa Indonesia](id/01-layout-and-mix.md)

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
| `internal/http/` | [`lib/shop_web/`](../example/lib/shop_web) — router, handlers |
| `internal/service/` | [`lib/shop/services/`](../example/lib/shop/services) |
| `internal/repo/` | [`lib/shop/repos/`](../example/lib/shop/repos) |
| `internal/model/` | [`lib/shop/models/`](../example/lib/shop/models) |
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

**Why:** the folder names are the same on purpose. Everything under
`lib/shop/` is the application; `lib/shop_web/` is only the HTTP layer on
top, so the core can be used without it (from a job, a script, a test).
