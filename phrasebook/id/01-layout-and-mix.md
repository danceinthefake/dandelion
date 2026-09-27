[English](../01-layout-and-mix.md) · **Bahasa Indonesia**

# 1. Struktur project dan `mix`

**Di Go**

```
go.mod                         module + dependencies
cmd/server/main.go
internal/http/  internal/service/  internal/repo/  internal/model/
go run ./cmd/server   go test ./...   gofmt   golangci-lint
```

**Di Elixir** — `mix` adalah `go` (build, run, test, dependency) dalam satu
tool:

| Go | Elixir |
|---|---|
| `go.mod` | [`mix.exs`](../../example/mix.exs) — `deps/0` berisi daftar dependency |
| `go mod download` | `mix deps.get` |
| `go run ./cmd/server` | `mix phx.server` |
| `go test ./...` | `mix test` |
| `gofmt` | `mix format` |
| `golangci-lint` | `mix credo --strict` |
| `go vet` | `mix compile --warnings-as-errors` |
| `internal/http/` | [`lib/shop_web/`](../../example/lib/shop_web) — router, handler |
| `internal/service/` | [`lib/shop/services/`](../../example/lib/shop/services) |
| `internal/repo/` | [`lib/shop/repos/`](../../example/lib/shop/repos) |
| `internal/model/` | [`lib/shop/models/`](../../example/lib/shop/models) |
| `migrations/` | [`priv/repo/migrations/`](../../example/priv/repo/migrations) |

Dependency, dari [`mix.exs`](../../example/mix.exs#L40):

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

**Kenapa:** nama foldernya sengaja dibuat sama. Semua yang ada di bawah
`lib/shop/` adalah aplikasinya; `lib/shop_web/` hanya lapisan HTTP di
atasnya, jadi intinya bisa dipakai tanpa HTTP (dari job, script, atau test).
