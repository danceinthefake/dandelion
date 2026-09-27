# The Go → Elixir phrasebook

For Go developers writing their first Elixir service. Each page shows how
you'd do something in Go, how it's done in Elixir, where it happens in
[`../example`](../example) (the `acme` service `mix dandelion.new` generates, with its `shop` domain),
and one line on *why* Elixir does it that way.

The pages follow the path of a request, from `mix` to a crash:

1. [Project layout and `mix`](01-layout-and-mix.md) — `go mod`, `go run`, `go test`
2. [Starting up](02-starting-up.md) — `main.go` vs the supervision tree
3. [Routing and handlers](03-routing-and-handlers.md) — chi vs router + handlers
4. [Errors as values](04-errors-as-values.md) — `(value, err)` vs `{:ok, _}` / `{:error, _}` and `with`
5. [Structs and validation](05-structs-and-validation.md) — structs vs schemas and changesets
6. [Services and transactions](06-services-and-transactions.md) — `sql.Tx` vs `Repo.transact`
7. [Repositories and queries](07-repositories-and-queries.md) — `database/sql` / sqlc vs Ecto
8. [Concurrency](08-concurrency.md) — goroutines and `context` vs processes and `Task`
9. [State that outlives a request](09-state.md) — mutex vs a process that owns the state
10. [Tests](10-tests.md) — `testing` vs ExUnit
11. [Config and releases](11-config-and-releases.md) — env config + Dockerfile vs `runtime.exs` + `mix release`
12. [When it crashes](12-when-it-crashes.md) — `panic` / `recover` vs supervisors

Reading order: 1–7 are enough to change the example; 8, 9 and 12 are where
Elixir differs most from Go, and why it's worth learning.
