# dandelion — design notes

> A whole cloud in one app. The usual cloud setup — web servers, workers,
> pub/sub, cache, task queue, cron, message brokers — as one Elixir
> release, laid out the way a Go service is (router, handlers, services,
> repositories). Run one copy on one VM; run 3 or 10 and they join into one
> system. Every seed carries the whole plant.

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

*Changed 2026-09-27* (was `lib/my_app/` + `lib/my_app_web/`, Phoenix's
habit). Two parts: **`lib/platform/`** — what every app runs on, the same
in every dandelion project — and **`lib/app/<domain>/`** — the business,
one folder per domain, laid out the way a Go service is.

```
lib/
  platform/                   what every app runs on
    application.ex            ≈ main.go: what starts, in order
    database/repo.ex          ≈ *sql.DB pool (Ecto.Repo) — Cloud SQL
    web/                      ≈ the web server
      endpoint.ex             ≈ http.Server + middleware
      router.ex               ≈ chi router: every route of every domain
      fallback_handler.ex     ≈ one place turning errors into HTTP statuses
      health_handler.ex  error_json.ex  telemetry.ex
    cluster.ex  cluster/      ≈ service discovery: nodes find each other through Postgres
    queue.ex                  ≈ Cloud Tasks: Oban (jobs in Postgres)
    cron.ex                   ≈ Cloud Scheduler: the crontab, once per cluster
    release.ex                migrations in production
    # coming with §10: pubsub.ex (≈ Google Pub/Sub), queue/ordered.ex (≈ SQS FIFO),
    # cache/, realtime/ — Platform.Broadcast (≈ Redis pub/sub) is
    # Phoenix.PubSub, started in application.ex
  app/
    shop/                     one domain; landing/, dashboard/, … the same way
      handlers/               ≈ internal/shop/http: params → service → JSON
      workers/                ≈ background goroutines / queue handlers
      services/               ≈ internal/shop/service: rules, transactions, no HTTP
      repos/                  ≈ internal/shop/repo: queries only
      models/                 ≈ internal/shop/model: structs + validation
deploy/                       ≈ the load balancer + N nodes: 3-node compose, nginx, proof
priv/repo/migrations/         ≈ migrations (golang-migrate / goose)
test/                         mirrors lib/ (test/platform/…, test/app/shop/…)
config/runtime.exs            ≈ envconfig: settings from environment variables
```

- **Module names follow the folders**, like Go packages:
  `lib/app/shop/services/order_service.ex` is
  `App.Shop.Services.OrderService`; `lib/platform/web/router.ex` is
  `Platform.Web.Router`. Explicit over implicit.
- **Handlers and workers belong to their domain**; `platform/` holds only
  the machinery. The router lists every route with full module names.
- **Services may use platform tools** (publish an event, read the cache),
  the way a Go service uses a Redis client; business rules never live in
  `platform/`.
- **The app name appears in no module name.** The example's OTP app is
  `acme` (`Acme.MixProject`, `config :acme`); the generator renames only
  that.

Names follow Go vocabulary (`handlers/`, `services/`, `repos/`, `models/`,
`workers/`) instead of Phoenix's (`controllers/`, contexts). Under the hood
they are ordinary Phoenix controllers and Ecto modules — the phrasebook
says so at each step.

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
`GET /orders?status=…`, `POST /orders/:id/cancel`. Enough to show:
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
- A Vue + blessing-ui frontend (§10.6) in `assets/`, left out with
  `--no-frontend` — the API and WebSocket work without it.

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

- names: `Acme` / `acme` → module / app, in paths and contents, in one regex
  pass (so a name like `acme_admin` isn't renamed twice); `Platform.*` and
  `App.Shop.*` modules stay as they are (§3.1);
- secrets: fresh `secret_key_base` values and signing salts;
- formatting: every Elixir file is re-formatted with the project's own
  formatter rules (captured from the example), since a longer or shorter
  name moves line breaks;
- `--no-example`: the `shop` domain (`lib/app/shop/`, its tests, the
  migration) is left out and three spots (routes, cron entry, job config)
  are edited — each edit fails loudly if its text is
  missing, so a change to the example can't produce a broken project.

Every generated project is the tested example, and there's no dependency on
the user's `phx_new` version. The generator's `mix.exs` copies `example/`
into `priv/templates` before every compile and package build (not
committed: `example/` is the only copy); the example's formatter rules, per
folder, are captured by `mix dandelion.sync_formatter`. Upgrading Phoenix
means upgrading the example.

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
13. Where is my Redis? pub/sub, cache, presence
14. Queues and topics: Cloud Tasks / asynq, Pub/Sub / Kafka, SQS FIFO, a real broker (Broadway)
15. Cron, and "only one does it": Cloud Scheduler, Redis locks
16. Frontend and live updates: the Vue app, channels, presence
17. One node or many: the service mesh, node failure, network splits

Written in English. (A Bahasa Indonesia translation was removed 2026-09-27:
it read unnaturally.)

## 6. Relationship to fumehood

fumehood already follows the router → controller → service split and the
error-to-JSON fallback; dandelion takes those from it. fumehood has no
repository layer yet (it stores no data of its own until its audit log), so
dandelion defines that layer, and fumehood adopts it for the audit log later.

## 7. Not goals

A new framework · a wrapper API over Oban, Cachex or Phoenix (§11 keeps the library thin) · replacing Phoenix's generators for
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
4. **Release** (hex `dandelion_new`) — pending, needs the maintainer's hex
   account. (The Bahasa Indonesia translation done here was removed
   2026-09-27: it read unnaturally.)
5. ✅ **Review fixes** (done 2026-09-27) — unpaid-order expiry is one
   `UPDATE … WHERE status = 'pending'` (a list-then-cancel could cancel an
   order paid in between); numbers too big for their columns, huge ids /
   pages and map-shaped query parameters are 4xx, not 500; `GET /health`
   (503 when the database is down, excluded from `force_ssl`); cookie
   session and method override removed (JSON API).
6. **A whole cloud in one app** (§10) — designed 2026-09-27; steps in
   §10.10.

## 9. Decisions

Decided 2026-09-27:

1. ✅ Layout and naming — Go vocabulary: `handlers/`, `services/`, `repos/`,
   `models/`.
2. ✅ Example resource — `orders` with items, the cancel rule and a
   background job.
3. ✅ Database — Postgres.
4. ✅ Delivery — generator, `mix dandelion.new`, copying the tested example (§4).
5. ✅ Linting — `credo` included.
6. ✅ Frontend — API only at first; *changed 2026-09-27*: Vue + blessing-ui
   in the template, `--no-frontend` to leave it out (§10.6).
7. ✅ Scope — a whole cloud in one app: every cloud piece but the load
   balancer, Postgres and object storage runs inside the release (§10).
8. ✅ Name — stays *dandelion*: every seed carries the whole plant.
9. ✅ Libraries used directly, no `Cloud.*` wrappers (§10.2). *Changed 2026-09-30:* the parts that are the same in every project become the `dandelion` library (§11).
10. ✅ Postgres decides; memory only makes things faster (§10.3).
11. ✅ Every node runs everything; no roles.
12. ✅ Discovery — through Postgres, with our own libcluster strategy
    (`libcluster_postgres` crash-looped on a database outage) (§10.4).
13. ✅ Private network; TLS between nodes optional.
14. ✅ No external broker — Oban queues and a job per subscriber replace
    it; Broadway only pointed to for talking to other systems (§10.7).
    Ordered queue **per key**, order = arrival at Postgres (§10.7.1).
15. ✅ Proof — local 3 nodes; N-VM guide written, untested (§10.8).
16. ✅ No rate limiting in the template — the load balancer's job.
17. ✅ Layout — `lib/platform/` + `lib/app/<domain>/`, module names follow
    folders, example app `acme` (§3.1).
18. ✅ Two pub/subs: `Platform.PubSub` durable (≈ Google Pub/Sub),
    `Platform.Broadcast` live (≈ Redis pub/sub) (§10.7).

## 10. A whole cloud in one app

Designed 2026-09-27.

### 10.1 The idea

A company service at scale usually runs as many separate pieces: web
servers, workers, Redis for pub/sub and cache, a task queue, a scheduler,
a message broker (RabbitMQ, Kafka, Google Pub/Sub), and a load balancer in
front. Each piece is its own
deployment, its own client library and its own thing to watch.

dandelion puts all of it into **one Elixir release**. One copy on one VM is
the whole stack. Start 3 or 10 copies and they find each other and act as
one system: a message published on one node reaches subscribers on every
node, a job queued on one node can run on any node, a WebSocket client on
node C sees an order made on node A.

Only three things stay outside: the **load balancer**, **Postgres** and
**object storage**.

### 10.2 The pieces

| Cloud piece | Usually | In dandelion | Across nodes | Survives a node crash |
|---|---|---|---|---|
| Load balancer | Cloud LB, nginx | **outside** | — | — |
| Backend API | Cloud Run, VM | Phoenix endpoint, every node | stateless | — |
| Frontend | static hosting | Vue + blessing-ui, built into the release (§10.6) | same files | — |
| Worker / consumer | separate deployment | Oban queues on every node | work spread over nodes | yes (Postgres) |
| Task queue | Cloud Tasks, RabbitMQ, asynq | Oban | shared | yes (Postgres) |
| Cron | Cloud Scheduler | Oban Cron | runs once per cluster | yes |
| Live broadcast | Redis pub/sub, NATS | `Platform.Broadcast` (Phoenix.PubSub) | yes | no — like Redis pub/sub |
| Message broker, work queue | RabbitMQ, Cloud Tasks | an Oban queue (§10.7) | shared | yes (Postgres) |
| Ordered queue | SQS FIFO, Kafka partition, Pub/Sub ordering key | ordered per key on Oban (§10.7.1) | shared | yes (Postgres) |
| Durable pub/sub (topic → subscribers) | Google Pub/Sub, Kafka, SNS→SQS | `Platform.PubSub`: one Oban job per subscriber (§10.7) | shared | yes (Postgres) |
| Cache | Redis, Memcached | Cachex per node, cleared across nodes via PubSub | kept in step | no — it's a cache |
| Leader / "only one does it" | Redis lock, etcd | Oban's leader (the `oban_peers` table) and unique jobs | yes | yes (Postgres) |
| WebSockets | Pusher, socket server + Redis | Phoenix Channels + Presence | yes | reconnects |
| Sessions | Redis | signed cookies (no store) | — | — |
| Service discovery | Consul, k8s DNS | libcluster + `Dandelion.Cluster.Postgres` | — | — |
| Service-to-service calls | HTTP / gRPC + mesh | direct calls between nodes | yes | — |
| Metrics | Prometheus exporters | PromEx (`/metrics`) | per node | — |
| Database | Cloud SQL | **outside**: Postgres | — | — |
| File storage | GCS, S3 | **outside** | — | — |

Each piece gets its folder in `lib/platform/` — `cluster/`, `queue/`,
`pubsub/`, `cache/`, `cron/`, `realtime/` — next to `web/` and `database/`;
the jobs and subscribers themselves live in their domain's `workers/`
(§3.1).

The generated project uses these libraries **directly** — no `Cloud.*`
wrappers. The pieces that are identical in every project (clustering, the
cache's cross-node clearing, the ordered queue, durable pub/sub) live in the
`dandelion` library (§11), thin over those libraries. The phrasebook maps each
one to the product it replaces ("where is my Redis?").

### 10.3 Rules

1. **Postgres decides; memory only makes things faster.** Anything that must
   survive a crash or happen exactly once — queued work, cron, "only one
   node does this", data changes — goes through Postgres (Oban, transactions,
   row locks). Cache, pub/sub and presence live in memory and
   may be lost or briefly stale.
2. **Every node runs everything.** Same image, same config, no roles. Scale
   by adding nodes.
3. **Private network only.** Connected nodes trust each other fully: anyone
   holding the cookie can run code on every node. Nodes must be on a private
   network, with the distribution ports firewalled from everything else. TLS
   between nodes is a nice-to-have, documented as an option (§10.8).
4. **Network splits are survivable by rule 1.** Nothing prevents a split;
   what matters is what each half can do:

   | Piece | During a split | Handled by |
   |---|---|---|
   | Jobs, cron, leader | could run twice | Postgres: Oban's leader and unique jobs live in the database, so a half that can't reach it can't act |
   | Data | — | transactions and row locks |
   | Cache | halves drift | short TTLs; clear on node reconnect |
   | Broadcast | messages between halves lost | at-most-once, like Redis pub/sub; events that must arrive go through `Platform.PubSub` |
   | Presence | each half sees its own users | merges on heal (CRDT) |

   `:global` locks are not used for anything that matters (in a split
   both halves elect a leader; one is killed on heal).

### 10.4 Finding each other

`libcluster` with our own strategy, `Dandelion.Cluster.Postgres`
(`lib/dandelion/cluster/postgres.ex` in the library, ~60 lines): each node sends its name
with `pg_notify` every 5 s and `LISTEN`s on the channel, connecting to the
names it hears. Nothing extra to run — Postgres is already there.

*Changed while building (2026-09-27):* the plan was `libcluster_postgres`
0.2. In the 3-node test, stopping Postgres made every node crash-loop
(restarted ~every 6 s): its connections don't reconnect, so the strategy
died, restarted at millisecond speed and took the app down. Ours starts
both connections without waiting for the database and lets them
reconnect by themselves — an outage only pauses discovery. It also uses a
named channel (`<app>_cluster`); the library's default was the Erlang
cookie, visible to anyone who can see the database's queries.

- Discovery only decides who joins; once joined, nodes talk directly over
  Erlang distribution, so it adds no latency to requests.
- Needs a **direct** Postgres connection: `LISTEN` doesn't work through
  PgBouncer in transaction mode. `CLUSTER_DATABASE_URL` points past a
  pooler; otherwise `DATABASE_URL`.
- If Postgres is down, running nodes stay connected and nothing crashes;
  new nodes join once it's back (tested).
- A dead node is noticed when its connection drops — at once for a crash,
  within `net_ticktime` (60 s) if the network goes silent.
- Only when the node runs distributed (a release, `iex --name`);
  `mix phx.server` and tests stay single.
- Alternatives, if Postgres discovery doesn't fit: DNS (`dns_cluster`) or
  a static host list — one line in `Dandelion.Cluster.topologies/1`.

Release config (`rel/env.sh.eex`, `rel/vm.args.eex`): the node is
`<app>@$NODE_IP` (or the container's IP); `RELEASE_COOKIE` must come from
the environment — the node refuses to start without it; distribution on
**one port, 9100, without epmd**, so the firewall rule between nodes is one
port.

### 10.5 The example, grown

The `orders` example gains a flow that touches every piece:

1. `POST /api/orders` creates the order and, **in the same transaction**,
   publishes `order.created` on `Platform.PubSub`: one Oban job per
   subscriber (§10.7). Either
   the order and its jobs are saved, or neither is.
2. Subscribers: send the confirmation (logged, no real mail) and update the
   customer's order count — the **topic with subscribers**, each retried on
   its own.
3. After commit, `order.created` also goes out on **`Platform.Broadcast`**
   for live views.
4. The payment provider calls `POST /api/payments/webhook` (as Midtrans,
   Xendit or Stripe do); the handler enqueues a job on the **ordered
   queue** with key `order:<id>` (§10.7.1): `payment.succeeded` marks the
   order `paid`, `payment.refunded` marks it `refunded`, always in the order
   they arrived for that order. This is also the first code path that sets
   `paid`.
5. Unpaid orders expire via **Oban Cron** — once per cluster, replacing
   today's per-node timer.
6. Product prices are read through the **cache** (a small `products`
   table), cleared on every node when a price changes.
7. The Vue page shows a **live order feed** over Channels and **who's
   online** with Presence — an order made through node A appears for a
   browser connected to node C.

### 10.6 Frontend

Vue 3 + blessing-ui (from npm), built by Vite into `priv/static` and served
by the same release — the fumehood setup. Pages: orders list with the live
feed and presence, create order, order detail.

`mix dandelion.new --no-frontend` leaves it out (no Node needed), like
`--no-example`. The image build gets a Node stage only when the frontend is
there.

### 10.7 No external broker

A message broker does two jobs, and both run inside the app:

| Broker job | Usually | In dandelion |
|---|---|---|
| Work queue: each message handled once, retried | RabbitMQ queue, Cloud Tasks | an Oban queue |
| Topic: one event, several subscribers, each gets it reliably | Google Pub/Sub subscriptions, Kafka consumer groups | `Platform.PubSub.publish/2` enqueues one Oban job per subscriber |
| Fan-out that may drop messages (live updates) | Redis pub/sub | `Platform.Broadcast` (Phoenix.PubSub) |

**Two kinds of pub/sub, two names.** Redis pub/sub and Google Pub/Sub look
alike but aren't:

| | `Platform.PubSub` — durable | `Platform.Broadcast` — live |
|---|---|---|
| Like | Google Pub/Sub, Kafka topics | Redis pub/sub |
| Stored | yes, in Postgres | no, memory only |
| Delivery | each subscriber at least once, retried, survives crashes | whoever listens right now, on every node; lost if nobody is |
| Order | none (a subscriber that needs it uses the ordered queue, §10.7.1) | none across publishers |
| For | work that must happen | live views, presence, clearing caches |

`Platform.PubSub` (`lib/platform/pubsub.ex`) holds `publish/2` and the
subscriptions — which workers receive each topic, listed in one place like
the crontab. Subscribers are Oban workers in their domain and must tolerate
running twice (at least once), as with Google Pub/Sub.

What this gets right that an external broker makes hard: the jobs live in
the same Postgres as the data, so saving a change and publishing its event
happen in **one transaction**. With Kafka or RabbitMQ that is the
dual-write problem (save, crash before publishing, event lost), usually
solved with an outbox table and a relay process.

#### 10.7.1 Ordered queue, per key

Most queues don't keep order: Cloud Tasks doesn't, RabbitMQ only with a
single consumer. Where order matters it's usually **per key** — the events
of one order, one customer — which is what Kafka partitions, SQS FIFO
message groups and Pub/Sub ordering keys give. dandelion does the same on
Oban.

**The queue is in Postgres, not on a VM.** Every node adds jobs and every
node runs them; no node is special.

```
req A (order 42) → VM1 ─┐
req C (order 77) → VM3 ─┼─► Postgres numbers them: A=101, C=102, B=103
req B (order 42) → VM2 ─┘
                            line order:42 → A(101), then B(103)
                            line order:77 → C(102), doesn't wait for A
```

- **Order means arrival at Postgres**, not the VMs' clocks (they drift).
  If order must follow the source (the time a payment happened), the
  source sends a sequence number and the worker checks it.
- **Enqueue**: in the caller's transaction, take
  `pg_advisory_xact_lock` on the key, then insert the job with the key in
  its `meta`. The lock makes the job id order equal to commit order for
  that key — without it, job 102 could become visible before 101 commits,
  and run first.
- **Run**: before doing its work, a job checks for an unfinished job with
  the same key and a lower id (`available`, `scheduled`, `executing` or
  `retryable`). If there is one, it snoozes a moment and tries again. One
  partial index on the key (unfinished jobs only) keeps the check cheap.
- **Different keys run in parallel** on all nodes; within a key, one at a
  time, in order.
- **A failing job blocks its key** while it retries — that's what
  "ordered" means (Kafka does the same). When it has used up its retries
  (discarded), it stops blocking and is logged, like SQS FIFO's
  dead-letter queue.
- **Idempotent**: webhooks get retried by the provider, so the job is
  unique on the provider's event id — the same event enqueued twice runs
  once.
- **A global queue** — everything in one line — is the same with one fixed
  key. It runs one job at a time for the whole cluster, however many nodes;
  the docs say so, and it's rarely what you want.

To check while building: a job running on a node that dies stays
`executing` until Oban's Lifeline plugin rescues it, and it blocks its key
until then — the rescue time has to be set short enough (the default is
long).

#### What it doesn't replace

Said plainly in the docs:

- **Other systems sending you events.** They call your HTTP API, or you
  keep a real broker at that edge and consume it with Broadway.
- **Kafka-style replay at high volume** (a new consumer re-reading months
  of events). An events table in Postgres covers the modest version.

### 10.8 Running it

**Local, 3 nodes** (`compose.cluster.yaml`): Postgres, three app
containers on one Docker network, and nginx in front as the load
balancer. No privileged containers. The proof, as a script and in the docs:

- all three nodes see each other;
- an order created through node 1 shows up live in a browser on node 3;
- kill node 2 while jobs are queued: the jobs finish on nodes 1 and 3;
- cron runs once per tick across the cluster, before and after the kill;
- each `order.created` subscriber runs exactly once, even with a node
  killed mid-way;
- payment events for one order run in arrival order across the three
  nodes, other orders' events in parallel, and a killed node's job is
  rescued before the next one for its key runs;
- node 2 comes back and rejoins without a restart of the others.

**N VMs behind a load balancer** (a guide, not tested on real VMs — no
cloud budget):

- VMs on a private network, no public IPs; the load balancer the only way in.
- Each VM runs the same image (Docker) or release (systemd), with
  `RELEASE_NODE` from its private IP and a shared `RELEASE_COOKIE` from a
  secret store.
- Firewall: the distribution port (9100, no epmd) open only between the app
  VMs; HTTP open only to the load balancer.
- Health check: `GET /health`.
- Rolling deploy: one VM at a time; Oban jobs of a stopped node are picked
  up by the others.
- Optional: TLS for distribution (`-proto_dist inet_tls`), with the
  certificate setup.

### 10.9 Decided while building

- **Cache**: Cachex per node plus PubSub invalidation (simple, one
  library) — Nebulex's distributed modes only if a real need shows up.
- **Metrics**: PromEx on `/metrics`, or telemetry only.

Not in the template: **rate limiting** — until a service is very large, the
load balancer does it (Cloud Armor, nginx `limit_req`).

### 10.10 Steps

1. ✅ Clustering (2026-09-27; moved into the library 2026-09-30): libcluster + `Dandelion.Cluster.Postgres`,
   release node / cookie / port config, `deploy/compose.cluster.yaml` with
   3 nodes + nginx, `deploy/cluster-proof.sh` (nodes connect, a broadcast
   crosses nodes, a killed node drops out and rejoins, a database outage
   crashes nothing).
2. ✅ Oban (2026-09-30): `Platform.Queue`, `Platform.Cron`, expiry via Oban
   Cron (the per-node timer is gone), `SendOrderConfirmation` queued by
   `OrderService.create/1` in the order's transaction (step 3 moves it
   behind `Platform.PubSub`), and the cluster proof: a job runs once; a job
   left `executing` by a killed node is run again by another node
   (`OBAN_RESCUE_AFTER_SECONDS=10` in the compose file; the orphan row is
   written by hand — no job runs long enough to catch one mid-flight).
3. ✅ Events (2026-09-30): `Platform.PubSub` (`publish/2` and the subscription
   list; one Oban job per subscriber, in the caller's transaction),
   `order.created` with two subscribers (`SendOrderConfirmation`,
   `UpdateCustomerStats` — a recount, so safe to run twice), a live
   broadcast on `Platform.Broadcast` after the commit, `Platform.Queue.Ordered`
   (advisory lock on the key at enqueue, "is an earlier job unfinished?" at
   run, partial index), `POST /api/payments/webhook` (token in
   `x-callback-token`; unique on `event_id`) → `ProcessPaymentEvent` on the
   `ordered` queue: `payment.succeeded` → `paid`, `payment.refunded` →
   `refunded`. Order status `refunded` added. Proof: both subscribers ran
   once; 10 orders' payment+refund raced by three nodes all end `refunded`
   (it fails with the order check removed); a dead node's stuck job holds
   its order back until rescued while other orders go on.
4. ✅ Cache (2026-09-30): `products` table, `Dandelion.Cache` (now in the
   library; Cachex, 60 s TTL; `fetch/2`, `delete/1` clears the key on every
   node through the app's PubSub, after the commit), `Dandelion.Cache.Listener` (applies
   other nodes' deletes; empties the cache on `:nodeup`), `GET` / `PUT
   /api/products/:sku`. Proof: a price changed through one node is read
   fresh on all three; a node that loses a node and gets it back starts with
   an empty cache. Not done: orders still take `price_cents` from the
   request, not from the products table.
5. ✅ Frontend (2026-09-30): `assets/` (Vue 3 + blessing-ui from npm, Vite,
   npm) built into `priv/static/app`, served at `/` by
   `Platform.Web.PageHandler`; the Dockerfile gets a Node stage. Page: new
   order form, the live order feed and who's online over
   `Platform.Web.UserSocket` → `App.Shop.Channels.OrderFeedChannel` with
   `Platform.Realtime.Presence`; order detail with cancel (`#/orders/42`).
   An order now broadcasts the order itself (`{:order_created, order}`).
   Generator: `--no-frontend` drops `assets/`, the page, the route and the
   Dockerfile stage; `--no-example` drops the frontend and the order channel
   too (generated projects checked: with everything, `--no-frontend`,
   `--no-example`). Checked in a real browser (Playwright) against the
   3-node cluster: two browsers, an order made in one appears in the other,
   presence counts both and drops one on close. Migrations split so
   `--no-example` has none that touch `orders`.
6. ✅ Docs (2026-09-30): phrasebook pages 13–17 (Redis → `Platform.Broadcast`
   / `Dandelion.Cache` / Presence; Cloud Tasks and asynq → Oban; Google Pub/Sub
   and Kafka → `Platform.PubSub` with the one-transaction publish; SQS FIFO →
   the ordered queue; "I still need a real broker" → Broadway; Cloud
   Scheduler and Redis locks → Oban Cron, leader and unique jobs; the frontend
   and channels; service mesh → node calls; network splits), pages 02 and 09
   brought up to date, `example/deploy/vms.md` (the N-VM guide), READMEs.
7. ✅ Generator (2026-09-30): templates are the example itself (copied at build
   time); the parts that belong to the example or the frontend sit between
   `@example-` / `@frontend-start`…`end` marker lines (Dockerfile, cluster
   proof, deploy README) and go whole with `--no-example` / `--no-frontend`,
   markers never reach a generated project. Integration tests (`mix test
   --include integration`, needs Docker, network, Postgres on :55432):
   default, `--no-frontend` and `--no-example` projects compile with
   warnings as errors, pass format, tests and credo; the generated frontend
   builds; the generated cluster proof passes on three containers, with
   everything and with `--no-example`. Fixed on the way: the generated
   `deploy/cluster-proof.sh` wasn't executable.

## 11. The library

Decided 2026-09-30. Two hex packages, like Phoenix's `phoenix` and `phx_new`:

| Package | Is | Used as |
|---|---|---|
| `dandelion` | the library: the cloud pieces that are the same in every project | `{:dandelion, "~> 0.1"}` in a project's deps |
| `dandelion_new` | the generator | `mix archive.install hex dandelion_new`, then `mix dandelion.new` |

A generated project depends on the library and keeps, in its own repo, what is
shaped by the app: router, endpoint, sockets, Presence (it needs the app's
`otp_app`), the cron schedule, the subscription list, `application.ex`, the
repo, and every `lib/app/<domain>/`. The library is thin over Oban, Cachex,
Phoenix.PubSub and libcluster — not a new API on top of them.

Why: a fix (the libcluster crash-loop was one) reaches every project through
`mix deps.update dandelion`; today each project would carry its own copy. The
cost is that these modules are read in `deps/`, not in `lib/` — so they stay
small and documented, and the phrasebook points at them.

| Was (`lib/platform/…`) | Library module | The project passes |
|---|---|---|
| `cluster.ex`, `cluster/postgres.ex` | `Dandelion.Cluster` | `otp_app:`, `repo:`; `config :app, Dandelion.Cluster, database_url:` |
| `cache.ex`, `cache/listener.ex` | `Dandelion.Cache` | — |
| `queue/ordered.ex` | `Dandelion.Queue.Ordered` | — |
| `pubsub.ex` | `Dandelion.PubSub` | the topic → subscribers list (config) |
| `queue.ex` | `Dandelion.Queue.config/1` | Oban overrides, cron schedule |
| the ordered-queue index migration | `Dandelion.Migration.up/0` | called from the project's migration |

### 11.1 Layout and working in the checkout

```
dandelion/          mix.exs, lib/   the library (hex: dandelion)
  installer/        the generator (hex: dandelion_new)
  example/          depends on the library by path ("..")
```

`example/mix.exs` has a dev-only `dandelion/0`: the library from `..` (or
`DANDELION_PATH`) in a checkout, hex elsewhere. The generator writes the plain
hex line and drops the function. The Docker build can't see `..`, so
`deploy/vendor-dandelion.sh` copies the library into `example/vendor/dandelion`
first (gitignored; a named build context would do it but needs buildx).
Integration tests do the same for generated projects until the library is on
hex.

### 11.2 Steps

1. ✅ Library skeleton + `Dandelion.Cluster` (2026-09-30); hex package back to
   `dandelion_new` for the generator; 3-node proof passes with the library.
2. ✅ `Dandelion.Cache` (2026-09-30): `{Dandelion.Cache, pubsub: Platform.Broadcast}`; the PubSub name is an option, kept in a `:persistent_term` for `delete/1`; the example's cachex dependency is gone (it comes with the library); proof passes.
3. `Dandelion.Queue.Ordered` and `Dandelion.Migration`.
4. `Dandelion.PubSub` and `Dandelion.Queue.config/1`.
5. Docs: phrasebook links and the hex docs of the library; publish both.
