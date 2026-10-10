# The Go → Elixir phrasebook

This phrasebook is for Go developers who write their first Elixir service. Each page shows how you do something in Go and how you do it in Elixir. It also shows where it happens in [`../example`](../example). This is the `acme` service that `mix dandelion.new` generates, with its `shop` domain. Each page ends with one line on why Elixir does it that way.

The pages follow the path of a request, from `mix` to a crash:

1. [Project layout and `mix`](01-layout-and-mix.md) compares `go mod`, `go run`, and `go test`
2. [Starting up](02-starting-up.md) compares `main.go` and the supervision tree
3. [Routing and handlers](03-routing-and-handlers.md) compares chi and router plus handlers
4. [Errors as values](04-errors-as-values.md) compares `(value, err)` and `{:ok, _}` / `{:error, _}` and `with`
5. [Structs and validation](05-structs-and-validation.md) compares structs and schemas and changesets
6. [Services and transactions](06-services-and-transactions.md) compares `sql.Tx` and `Repo.transact`
7. [Repositories and queries](07-repositories-and-queries.md) compares `database/sql` or sqlc and Ecto
8. [Concurrency](08-concurrency.md) compares goroutines and `context` and processes and `Task`
9. [State that outlives a request](09-state.md) compares a mutex and a process that owns the state
10. [Tests](10-tests.md) compares `testing` and ExUnit
11. [Config and releases](11-config-and-releases.md) compares environment variables plus a Dockerfile and `runtime.exs` plus `mix release`
12. [When it crashes](12-when-it-crashes.md) compares `panic` and `recover` and supervisors

The rest of the cloud is what you otherwise run next to the service:

13. [Where is my Redis?](13-where-is-my-redis.md) covers pub/sub, cache, and presence, in the app
14. [Queues and topics](14-queues-and-topics.md) covers Cloud Tasks or asynq, Google Pub/Sub or Kafka, SQS FIFO, and "I still need a real broker"
15. [Cron, and "only one does it"](15-cron-and-leaders.md) covers Cloud Scheduler and Redis locks
16. [Frontend and live updates](16-frontend-and-live.md) covers a Vue app on the same release, WebSockets, and who is online
17. [One node or many](17-one-node-or-many.md) covers a service mesh, node failure, and network splits
18. [Metrics and traces](18-metrics-and-traces.md) compares `promhttp` and `otel-go` and telemetry events, and shows a trace that crosses nodes
19. [Logins, tokens, and who can see what](19-auth.md) compares middleware and plugs, JWT and signed tokens, and shows ownership in the service

Pages 1 to 7 are enough to change the example. Pages 8, 9, and 12 show where Elixir differs most from Go. They also show why Elixir is worth learning.
