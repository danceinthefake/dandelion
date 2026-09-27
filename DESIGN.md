# dandelion — design notes

> A starting point for Go developers writing their first Elixir service: a
> project laid out the way a Go service is — router, handlers, services,
> repositories — with a guide that maps every Go habit to its Elixir
> equivalent.

Name: *dandelion* — **simplicity with resilience and joy.** The plainest
flower there is; it grows through cracks in concrete and comes back every
time you pull it; its seeds scatter on the wind — one flower becoming many,
the way a service starts single and grows into a cluster.

Tagline: **Simplicity with resilience and joy** — Go's philosophy
(simplicity: clear over clever, errors as values, communicate by messages)
carried into Elixir's (resilience: let it crash, supervisors; joy: data
flowing through transformations, developer happiness). Clustering
is part of the same project (§10).

Status: **design decided (2026-09-27)** — decisions in §9.

## 1. Problem

A Go developer who wants to try Elixir meets Phoenix first, and Phoenix asks
them to learn many things at once: generators, contexts, the Plug pipeline,
LiveView, sockets, and OTP underneath. None of it looks like the Go service
they already know how to write:

```
cmd/server/main.go
internal/http/router.go       chi routes
internal/http/orders.go       handlers: decode → call service → encode
internal/service/orders.go    business rules, no HTTP
internal/repo/orders.go       SQL, no business rules
internal/model/order.go       structs
```

So they either give up, or learn Phoenix's conventions before they've seen
why Elixir is worth it.

dandelion gives them a service with **the same shape they already know**, where
the only new thing is the language. The DITF goal (`../PLANNING.md`): make
Elixir approachable for the community, especially in Indonesia.

## 2. What dandelion is

Two parts:

1. **A project template** — a small, complete JSON API service, laid out in
   Go-style layers, with one worked example resource, tests, and one-command
   setup.
2. **A guide (the "phrasebook")** — for each Go habit, the Elixir way, pointing
   at the exact file in the template where it happens.

Not a framework and not a library: nothing to depend on at runtime. The
generated project is plain Phoenix + Ecto; dandelion only decides the layout and
explains it.

## 3. The template

### 3.1 Layout

```
lib/
  my_app/
    application.ex            ≈ main.go: what starts (supervision tree)
    repo.ex                   ≈ *sql.DB pool (Ecto.Repo)
    models/order.ex           ≈ model/order.go: struct + validation (Ecto schema/changeset)
    repos/order_repo.ex       ≈ repo/orders.go: queries only
    services/order_service.ex ≈ service/orders.go: rules, transactions, no HTTP
  my_app_web/
    router.ex                 ≈ chi routes
    handlers/order_handler.ex ≈ handlers: params → service → JSON
    handlers/fallback.ex      ≈ one place turning errors into HTTP statuses
    plugs/request_id.ex …     ≈ middleware
priv/repo/migrations/         ≈ migrations (golang-migrate / goose)
test/                         ≈ *_test.go, table-driven where it fits
config/runtime.exs            ≈ envconfig: settings from environment variables
```

Names follow Go vocabulary on purpose (`handlers/`, `services/`, `repos/`,
`models/`) instead of Phoenix's (`controllers/`, contexts). Under the hood
they are ordinary Phoenix controllers and Ecto modules — the guide says so
at each step.

### 3.2 Conventions the template shows

| Go | dandelion |
|---|---|
| `(value, err)` returns | `{:ok, value}` / `{:error, reason}` + `with` for the happy path |
| `if err != nil { return … }` chains | `with` … `else` |
| struct + methods | struct + module functions; data and functions apart |
| interface for a repo (mocking) | a behaviour (`@callback`) only where a test needs a fake; otherwise call the module |
| `context.Context` cancel/timeout | a process with a timeout (`Task.async` + `Task.yield`/`shutdown`) |
| goroutine + `WaitGroup` | `Task.async_stream` |
| `sync.Mutex` / shared state | a `GenServer` owning the state (only where needed) |
| `database/sql` tx | `Repo.transaction` / `Ecto.Multi` |
| table-driven tests | `for` over cases inside one `test`, or one `test` per case with a loop at module level |
| `go vet` / `gofmt` / `golangci-lint` | compiler warnings as errors / `mix format` / `credo` |
| `panic` / `recover` | "let it crash" + supervisor restart — explained, used sparingly |
| env config (envconfig / viper) | `config/runtime.exs` reading `System.get_env` |
| Dockerfile multi-stage | `mix release` in a multi-stage Dockerfile |

### 3.3 The worked example: `orders`

One resource, end to end: `POST /orders`, `GET /orders/:id`,
`GET /orders?status=…`, `PATCH /orders/:id/cancel`. Enough to show:
validation errors → 422 with field messages, not found → 404, a business
rule (can't cancel a shipped order), a transaction touching two tables
(order + order_items), pagination, and a background job (e.g. a timeout
that cancels unpaid orders) — the place where Elixir's processes show their
value without making the rest of the code unfamiliar.

### 3.4 Stack

- Phoenix, used minimally (router + controllers + JSON; no HTML, LiveView,
  assets, mailer, dashboard, gettext) — same as fumehood.
- Ecto + **Postgres** (what Go services in Indonesian companies mostly use),
  `compose.yaml` for the local database.
- `mise.toml` pinning Erlang / Elixir.
- No frontend in the template (a Go developer's service is usually an API);
  a Vue + blessing-ui add-on comes later.

## 4. How people get it

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Generator** ← decided | `mix archive.install hex dandelion_new` then `mix dandelion.new my_app` | one command, project named correctly, like `phx.new` | a generator to maintain; must track Phoenix releases |
| B. Template repository | "Use this template" on GitHub, then rename | no code to maintain | renaming modules by hand (`MyApp` everywhere) is a bad first experience |

Decided: **A**. *Changed while building (milestone 3):* the plan was to run
`phx.new` and then edit its output. But `example/` already *is* `phx.new`
output plus the dandelion edits — and it's the tested version. So `dandelion.new`
**copies the example** (embedded in the archive as `installer/priv/templates`)
and changes only what must differ per project:

- names: `Shop` / `shop` → module / app, in paths and contents, in one regex
  pass (so a name like `Workshop` isn't renamed twice);
- secrets: fresh `secret_key_base` values and signing salts;
- formatting: every Elixir file is re-formatted with the project's own
  formatter rules (captured from the example), since a longer or shorter
  name moves line breaks;
- `--no-example`: the orders files are left out and three spots (routes, job
  start, job config) are edited — each edit fails loudly if its text is
  missing, so a change to the example can't produce a broken project.

Every generated project is the tested example, and there's no dependency on
the user's `phx_new` version. `mix dandelion.sync_templates` copies `example/`
into the package; a test fails while they differ. Upgrading Phoenix means
upgrading the example.

## 5. The phrasebook (guide)

Short pages, each: the Go code, the Elixir code, the file in the template,
and one sentence on why Elixir does it that way. Order follows the path of a
request:

1. Project layout and `mix` (vs `go mod`, `go run`, `go test`)
2. Starting up: `application.ex` and supervisors (vs `main.go`)
3. Routing and handlers (vs chi)
4. Errors as values: `{:ok, _}` / `{:error, _}` and `with`
5. Structs, pattern matching, and validation (changesets)
6. Services and transactions
7. Repositories and queries (Ecto vs `database/sql` / sqlc)
8. Concurrency: processes, `Task`, timeouts (vs goroutines, context)
9. Shared state: `GenServer` (vs mutex)
10. Tests (vs `testing`, table-driven)
11. Config and releases (vs env + Dockerfile)
12. When it crashes: supervisors (vs `panic`/`recover`)

Written in **English and Bahasa Indonesia** (DITF principle).

## 6. Relationship to fumehood

fumehood already follows the router → controller → service split and the
error-to-JSON fallback; dandelion takes those from it. fumehood has no
repository layer yet (it stores no data of its own until its audit log), so
dandelion defines that layer, and fumehood adopts it for the audit log later.

## 7. Not goals

A new framework or runtime library · replacing Phoenix's generators for
people who already know Phoenix · LiveView or HTML front ends · covering
every Go library's equivalent.

## 8. Milestones

1. ✅ **The example service by hand** (done 2026-09-27, `example/`) — the
   `orders` service in the dandelion layout, tests, compose + mise, running;
   background job; release Dockerfile (130 MB image, migrate + server
   verified). This is the thing the generator
   will produce, so it's built and reviewed first.
2. ✅ **Phrasebook v1** (done 2026-09-27, `phrasebook/`) — the 12 pages in
   English, each pointing into the example; links and line anchors checked,
   standalone snippets (Task fan-out, timeout, GenServer counter) run.
3. ✅ **Generator** (done 2026-09-27, `installer/`) — `mix dandelion.new`,
   producing the example (`--no-example` leaves it out). Integration test:
   a generated project, with and without the example, fetches deps,
   compiles with warnings as errors, passes `mix format --check-formatted`,
   its tests and `credo --strict`; the built archive installs and generates
   from outside the repo.
4. **Bahasa Indonesia** translation ✅ (done 2026-09-27: `phrasebook/id/`,
   `README.id.md`; code blocks checked identical to the English pages),
   release (hex `dandelion_new`) — pending, needs the maintainer's hex account.
5. **Cluster** (§10) — to be designed in detail when it starts.

## 9. Decisions

Decided 2026-09-27:

1. ✅ Layout and naming — Go vocabulary: `handlers/`, `services/`, `repos/`,
   `models/`.
2. ✅ Example resource — `orders` with items, the cancel rule and a
   background job.
3. ✅ Database — Postgres.
4. ✅ Delivery — generator, `mix dandelion.new`, copying the tested example (§4).
5. ✅ Linting — `credo` included.
6. ✅ Frontend — API only; a Vue + blessing-ui add-on later.

## 10. Growing into a cluster

Start single, then extend. A company service usually needs an app **plus**
Redis (cache, pub/sub), Kafka / RabbitMQ consumers, a worker and cron.
Several Elixir nodes forming a cluster cover all of that in one runtime —
dandelion shows how, on top of the same layout, with the same
Go-developer-first explanations. It reuses mature libraries instead of
rebuilding them:

| Need | Go stack usually | dandelion (proposal) |
|---|---|---|
| nodes finding each other | — | `dns_cluster` (DNS / Kubernetes headless service) |
| pub/sub across instances | Redis pub/sub, NATS | `Phoenix.PubSub` (already in the example) |
| cache shared across instances | Redis | `Cachex` or `Nebulex` (distributed) |
| queue consumers | sarama / segmentio kafka-go, amqp | `Broadway` (Kafka, RabbitMQ, GCP Pub/Sub, SQS) |
| background jobs + cron | a worker binary + cron / asynq | `Oban` (Postgres-backed, cron built in) |
| exactly one instance does X | leader election via Redis / etcd lock | one process per cluster (`:global` / Oban uniqueness) |

Shape (*proposal*, to decide when this milestone starts): an option on the
generator (`mix dandelion.new my_app --cluster`) or a later step that adds
clustering to an existing project, plus phrasebook pages (Redis pub/sub →
Phoenix.PubSub, consumer groups → Broadway, cron + leader lock → one
process per cluster, …), and a real deployment test: three nodes, one
killed, the work carries on elsewhere.
