# dandelion: design notes

> A whole cloud in one app. The usual cloud setup has web servers, workers, pub/sub, a cache, a task queue, cron, and message brokers. dandelion puts all of them in one Elixir release. The layout is the layout of a Go service: router, handlers, services, and repositories. Run one copy on one VM. If you run 3 or 10 copies, they join into one system. Every seed carries the whole plant.

Name: *dandelion*. The motto is **simplicity with resilience and joy.** The dandelion is the plainest flower. It grows through cracks in concrete. It comes back each time you pull it. Its seeds scatter on the wind, and one flower becomes many. A service starts as one copy and grows into a cluster in the same way.

Tagline: **Simplicity with resilience and joy.** The tagline carries the philosophy of Go into Elixir. In Go, simplicity means clear over clever, errors as values, and communication by messages. In Elixir, resilience means let it crash and supervisors. Joy means data that flows through transformations and developer happiness. Clustering is part of the same project (§10).

Status: **design decided (2026-09-27).** The decisions are in §9.

## 1. Problem

A Go developer who wants to try Elixir meets Phoenix first. Phoenix asks them to learn many things at once: generators, contexts, the Plug pipeline, LiveView, sockets, and OTP underneath. None of it looks like the Go service that they already know how to write:

```
cmd/server/main.go
internal/http/router.go       chi routes
internal/http/orders.go       handlers: decode → call service → encode
internal/service/orders.go    business rules, no HTTP
internal/repo/orders.go       SQL, no business rules
internal/model/order.go       structs
```

The developer then gives up, or learns the conventions of Phoenix before they see why Elixir is worth it.

dandelion gives them a service with the same shape that they already know. The only new thing is the language. The DITF goal (`../PLANNING.md`) is to make Elixir approachable for the community, especially in Indonesia.

## 2. What dandelion is

dandelion has two parts:

1. A project template. It is a small, complete JSON API service in Go-style layers. It has one worked example resource, tests, and a one-command setup.
2. A guide (the "phrasebook"). For each Go habit, it shows the Elixir way. It points at the exact file in the template where the habit happens.

dandelion is not a framework. At first it was also not a library, and the project had nothing to depend on at runtime. This changed in §11. The generated project is plain Phoenix and Ecto. dandelion decides the layout and explains it.

## 3. The template

### 3.1 Layout

*Changed 2026-09-27.* The layout was `lib/my_app/` and `lib/my_app_web/`, the habit of Phoenix. Now the layout has two parts. `lib/platform/` has what every app runs on, and it is the same in every dandelion project. `lib/app/<domain>/` has the business, with one folder for each domain, in the layout of a Go service.

```
lib/
  platform/                   what every app runs on
    application.ex            ≈ main.go: what starts, in order
    database/repo.ex          ≈ *sql.DB pool (Ecto.Repo) — Cloud SQL
    web/                      ≈ the web server
      endpoint.ex             ≈ http.Server + middleware
      routes.ex               the routes every project has: /health, /metrics, the shell page
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
    router.ex                 ≈ chi router in main.go: mounts each domain's routes, holds the shared pipelines
    shop/                     one domain; landing/, dashboard/, … the same way
      routes.ex               ≈ the domain's sub-router: its paths, and who may call them
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

- Module names follow the folders, like Go packages. For example, `lib/app/shop/services/order_service.ex` is `App.Shop.Services.OrderService`, and `lib/app/router.ex` is `App.Router`. Explicit is better than implicit.
- Handlers and workers belong to their domain. `platform/` holds only the machinery. The router is `App.Router`, on the app side, because it names the domains of the app. Each domain lists its own routes in `lib/app/<domain>/routes.ex` with full module names.
- Services can use platform tools, for example to publish an event or read the cache. A Go service uses a Redis client in the same way. Business rules never live in `platform/`.
- The app name appears in no module name. The OTP app of the example is `acme` (`Acme.MixProject` and `config :acme`). The generator renames only that.

The names follow the vocabulary of Go (`handlers/`, `services/`, `repos/`, `models/`, and `workers/`) and not the vocabulary of Phoenix (`controllers/` and contexts). Under the hood, they are ordinary Phoenix controllers and Ecto modules. The phrasebook says so at each step.

### 3.2 Conventions the template shows

| Go | dandelion |
|---|---|
| `(value, err)` returns | `{:ok, value}` / `{:error, reason}` + `with` for the happy path |
| `if err != nil { return … }` chains | `with` … `else` |
| struct + methods | struct + module functions, with data and functions apart |
| interface for a repo (mocking) | a behaviour (`@callback`) only where a test needs a fake; or else call the module |
| `context.Context` cancel/timeout | a process with a timeout (`Task.async` + `Task.yield`/`shutdown`) |
| goroutine + `WaitGroup` | `Task.async_stream` |
| `sync.Mutex` / shared state | a `GenServer` owning the state (only where needed) |
| `database/sql` tx | `Repo.transaction` / `Ecto.Multi` |
| table-driven tests | `for` over cases inside one `test`, or one `test` per case with a loop at module level |
| `go vet` / `gofmt` / `golangci-lint` | compiler warnings as errors / `mix format` / `credo` |
| `panic` / `recover` | "let it crash" + supervisor restart (explained, used sparingly) |
| env config (envconfig / viper) | `config/runtime.exs` reading `System.get_env` |
| Dockerfile multi-stage | `mix release` in a multi-stage Dockerfile |

### 3.3 The worked example: `orders`

The example has one resource, end to end: `POST /orders`, `GET /orders/:id`, `GET /orders?status=…`, and `POST /orders/:id/cancel`. It is enough to show these things:

- Validation errors give 422 with field messages.
- A missing record gives 404.
- A business rule (a shipped order cannot be cancelled).
- A transaction that touches two tables (order and order_items).
- Pagination.
- A background job. For example, a timeout cancels unpaid orders. This is the place where the processes of Elixir show their value. The rest of the code stays familiar.

### 3.4 Stack

- Phoenix, used minimally. It has the router, the controllers, and JSON. It has no HTML, LiveView, assets, mailer, dashboard, or gettext. This is the same as fumehood.
- Ecto and **Postgres**. Most Go services in Indonesian companies use Postgres. `compose.yaml` runs the local database.
- `mise.toml` pins Erlang and Elixir.
- A Vue and blessing-ui frontend (§10.6) in `assets/`. `--no-frontend` leaves it out. The API and the WebSocket work without it.

## 4. How people get it

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Generator** ← decided | `mix archive.install hex dandelion_new` then `mix dandelion.new my_app` | one command, project named correctly, like `phx.new` | a generator to maintain; it must track Phoenix releases |
| B. Template repository | "Use this template" on GitHub, then rename | no code to maintain | renaming modules by hand (`MyApp` everywhere) is a bad first experience |

Decision: **A**. *Changed while we built milestone 3.* The plan was to run `phx.new` and then edit its output. But `example/` is already `phx.new` output plus the dandelion edits, and it is the tested version. `dandelion.new` therefore copies the example. The archive embeds the example as `installer/priv/templates`. The generator changes only what must differ for each project:

- Names. `Acme` and `acme` become the module name and the app name, in paths and contents, in one regex pass. A name like `acme_admin` is therefore not renamed twice. The `Platform.*` and `App.Shop.*` modules stay as they are (§3.1).
- Secrets. The generator makes fresh `secret_key_base` values and signing salts.
- Formatting. The generator formats every Elixir file again with the formatter rules of the project (captured from the example), because a longer or shorter name moves line breaks.
- `--no-example`. The generator leaves out the `shop` domain (`lib/app/shop/`, its tests, and the migration). It edits three spots: routes, the cron entry, and the job configuration. Each edit fails loudly if its text is missing. A change to the example therefore cannot produce a broken project.

Every generated project is the tested example, and the project has no dependency on the `phx_new` version of the user. The `mix.exs` of the generator copies `example/` into `priv/templates` before every compile and package build. We do not commit that copy, because `example/` is the only copy. `mix dandelion.sync_formatter` captures the formatter rules of the example for each folder. To upgrade Phoenix, upgrade the example.

## 5. The phrasebook (guide)

The phrasebook has short pages. Each page has the Go code, the Elixir code, the file in the template, and one sentence on why Elixir does it that way. The order follows the path of a request:

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
18. Metrics and traces: `promhttp` / `otel-go` vs telemetry events, a trace that crosses nodes
19. Logins, tokens, and who can see what: middleware vs plugs, JWT vs signed tokens, ownership in the service

The phrasebook is in English. We removed a Bahasa Indonesia translation on 2026-09-27, because it read unnaturally.

## 6. Relationship to fumehood

fumehood already follows the split of router, controller, and service. It also has the error-to-JSON fallback. dandelion takes both from it. fumehood has no repository layer yet, because it stores no data of its own until its audit log. dandelion therefore defines that layer, and fumehood adopts it later for the audit log.

## 7. Not goals

These are not goals of dandelion:

- A new framework.
- A wrapper API over Oban, Cachex, or Phoenix (§11 keeps the library thin).
- A replacement for the generators of Phoenix for people who already know Phoenix.
- LiveView or HTML front ends.
- The equivalent of every Go library.

## 8. Milestones

1. ✅ **The example service by hand** (done 2026-09-27, `example/`). The `orders` service in the dandelion layout, with tests, compose, and mise, running. It has a background job and a release Dockerfile (a 130 MB image, with migrate and server verified). The generator will produce this service, so we built and reviewed it first.
2. ✅ **Phrasebook v1** (done 2026-09-27, `phrasebook/`). The 12 pages in English, each pointing into the example. We checked links and line anchors. The standalone snippets (Task fan-out, timeout, GenServer counter) run.
3. ✅ **Generator** (done 2026-09-27, `installer/`). `mix dandelion.new` produces the example (`--no-example` leaves it out). The integration test generates a project, with and without the example. The project fetches deps, compiles with warnings as errors, and passes `mix format --check-formatted`, its tests, and `credo --strict`. The built archive installs and generates from outside the repo.
4. ✅ **Release.** `dandelion` and `dandelion_new` 0.1.0 are on hex (the library and the generator, §11). We removed the Bahasa Indonesia translation done here on 2026-09-27, because it read unnaturally.
5. ✅ **Review fixes** (done 2026-09-27):
   - The expiry of unpaid orders is one `UPDATE … WHERE status = 'pending'`. A list-then-cancel can cancel an order that was paid in between.
   - Numbers that are too big for their columns, huge ids and pages, and map-shaped query parameters give 4xx and not 500.
   - `GET /health` gives 503 when the database is down, and `force_ssl` excludes it.
   - We removed the cookie session and the method override (JSON API).
6. **A whole cloud in one app** (§10). We designed it on 2026-09-27. The steps are in §10.10.

## 9. Decisions

Decided on 2026-09-27:

1. ✅ Layout and naming. Use Go vocabulary: `handlers/`, `services/`, `repos/`, `models/`.
2. ✅ Example resource. `orders` with items, the cancel rule, and a background job.
3. ✅ Database. Postgres.
4. ✅ Delivery. A generator, `mix dandelion.new`, that copies the tested example (§4).
5. ✅ Linting. Include `credo`.
6. ✅ Frontend. API only at first. *Changed 2026-09-27:* Vue and blessing-ui in the template, and `--no-frontend` leaves it out (§10.6).
7. ✅ Scope. A whole cloud in one app. Every cloud piece except the load balancer, Postgres, and object storage runs inside the release (§10).
8. ✅ Name. The name stays *dandelion*, because every seed carries the whole plant.
9. ✅ Use libraries directly, with no `Cloud.*` wrappers (§10.2). *Changed 2026-09-30:* the parts that are the same in every project become the `dandelion` library (§11).
10. ✅ Postgres decides, and memory only makes things faster (§10.3).
11. ✅ Every node runs everything. There are no roles.
12. ✅ Discovery. It goes through Postgres, with our own libcluster strategy, because `libcluster_postgres` crashed in a loop on a database outage (§10.4).
13. ✅ Private network. TLS between nodes is optional.
14. ✅ No external broker. Oban queues and a job for each subscriber replace it. Broadway is only a pointer for talking to other systems (§10.7). The ordered queue works for each key, and order means arrival at Postgres (§10.7.1).
15. ✅ Proof. Three local nodes. The guide for N VMs is written and untested (§10.8).
16. ✅ No rate limiting in the template. The load balancer does it. (§10.13 changed this later.)
17. ✅ Layout. `lib/platform/` and `lib/app/<domain>/`, with module names that follow the folders, and the example app `acme` (§3.1).
18. ✅ Two pub/subs. `Platform.PubSub` is durable (≈ Google Pub/Sub), and `Platform.Broadcast` is live (≈ Redis pub/sub) (§10.7).

## 10. A whole cloud in one app

We designed this on 2026-09-27.

### 10.1 The idea

A company service at scale usually runs as many separate pieces. These are web servers, workers, Redis for pub/sub and cache, a task queue, a scheduler, a message broker (RabbitMQ, Kafka, or Google Pub/Sub), and a load balancer in front. Each piece is its own deployment, with its own client library, and you must watch each one.

dandelion puts all of it into one Elixir release. One copy on one VM is the whole stack. If you start 3 or 10 copies, they find each other and act as one system. A message that one node publishes reaches subscribers on every node. A job that one node queues can run on any node. A WebSocket client on node C sees an order made on node A.

Only three things stay outside: the **load balancer**, **Postgres**, and **object storage**.

### 10.2 The pieces

| Cloud piece | Usually | In dandelion | Across nodes | Survives a node crash |
|---|---|---|---|---|
| Load balancer | Cloud LB, nginx | **outside** | none | none |
| Backend API | Cloud Run, VM | Phoenix endpoint, every node | stateless | none |
| Frontend | static hosting | Vue + blessing-ui, built into the release (§10.6) | same files | none |
| Worker / consumer | separate deployment | Oban queues on every node | work spread over nodes | yes (Postgres) |
| Task queue | Cloud Tasks, RabbitMQ, asynq | Oban | shared | yes (Postgres) |
| Cron | Cloud Scheduler | Oban Cron | runs once per cluster | yes |
| Live broadcast | Redis pub/sub, NATS | `Platform.Broadcast` (Phoenix.PubSub) | yes | no, like Redis pub/sub |
| Message broker, work queue | RabbitMQ, Cloud Tasks | an Oban queue (§10.7) | shared | yes (Postgres) |
| Ordered queue | SQS FIFO, Kafka partition, Pub/Sub ordering key | ordered per key on Oban (§10.7.1) | shared | yes (Postgres) |
| Durable pub/sub (topic → subscribers) | Google Pub/Sub, Kafka, SNS→SQS | `Platform.PubSub`: one Oban job per subscriber (§10.7) | shared | yes (Postgres) |
| Cache | Redis, Memcached | Cachex per node, cleared across nodes via PubSub | kept in step | no, it is a cache |
| Leader / "only one does it" | Redis lock, etcd | Oban's leader (the `oban_peers` table) and unique jobs | yes | yes (Postgres) |
| WebSockets | Pusher, socket server + Redis | Phoenix Channels + Presence | yes | reconnects |
| Sessions | Redis | signed cookies (no store) | none | none |
| Service discovery | Consul, k8s DNS | libcluster + `Dandelion.Cluster.Postgres` | none | none |
| Service-to-service calls | HTTP / gRPC + mesh | direct calls between nodes | yes | none |
| Metrics | Prometheus exporters | `GET /metrics` (`telemetry_metrics_prometheus_core`) | each node reports itself; Prometheus scrapes them all | counters restart with the node |
| Database | Cloud SQL | **outside**: Postgres | none | none |
| File storage | GCS, S3 | **outside** | none | none |

Each piece gets its folder in `lib/platform/`: `cluster/`, `queue/`, `pubsub/`, `cache/`, `cron/`, and `realtime/`. They sit next to `web/` and `database/`. The jobs and subscribers themselves live in `workers/` of their domain (§3.1).

The generated project uses these libraries directly. It has no `Cloud.*` wrappers. The pieces that are identical in every project live in the `dandelion` library (§11). These are clustering, the cross-node clearing of the cache, the ordered queue, and durable pub/sub. The library is thin over the other libraries. The phrasebook maps each piece to the product that it replaces ("where is my Redis?").

### 10.3 Rules

1. **Postgres decides, and memory only makes things faster.** Anything that must survive a crash or happen exactly one time goes through Postgres (Oban, transactions, and row locks). Examples are queued work, cron, "only one node does this", and data changes. The cache, pub/sub, and presence live in memory. They can be lost or be stale for a short time.
2. **Every node runs everything.** It is the same image and the same configuration, with no roles. To scale, add nodes.
3. **Use a private network only.** Connected nodes trust each other fully. Anyone who has the cookie can run code on every node. The nodes must be on a private network. A firewall must block the distribution ports from everything else. TLS between nodes is optional and the docs describe it (§10.8).
4. **Rule 1 makes network splits survivable.** Nothing prevents a split. What matters is what each half can do:

   | Piece | During a split | Handled by |
   |---|---|---|
   | Jobs, cron, leader | can run twice | Postgres. The leader and the unique jobs of Oban live in the database, so a half that cannot reach the database cannot act. |
   | Data | no change | transactions and row locks |
   | Cache | the halves drift | short TTLs, and a clear when a node reconnects |
   | Broadcast | messages between halves are lost | at-most-once, like Redis pub/sub. Events that must arrive go through `Platform.PubSub`. |
   | Presence | each half sees its own users | it merges after the heal (CRDT) |

   The project does not use `:global` locks for anything that matters. In a split, both halves elect a leader, and the heal kills one of them.

### 10.4 Finding each other

The project uses `libcluster` with our own strategy, `Dandelion.Cluster.Postgres` (`lib/dandelion/cluster/postgres.ex` in the library, about 60 lines). Each node sends its name with `pg_notify` every 5 s and runs `LISTEN` on the channel. It connects to the names that it hears. You run nothing extra, because Postgres is already there.

*Changed while we built it (2026-09-27).* The plan was `libcluster_postgres` 0.2. In the 3-node test, when we stopped Postgres, every node crashed in a loop (a restart about every 6 s). The connections of that package do not reconnect, so the strategy died and restarted at millisecond speed, and it took the app down. Our strategy starts both connections without a wait for the database, and the connections reconnect by themselves. An outage therefore only pauses discovery. Our strategy also uses a named channel (`<app>_cluster`). The default of that package was the Erlang cookie, and anyone who can see the queries of the database can see the cookie.

- Discovery only decides who joins. After the join, nodes talk directly over Erlang distribution. Discovery therefore adds no latency to requests.
- Discovery needs a direct Postgres connection. `LISTEN` does not work through PgBouncer in transaction mode. `CLUSTER_DATABASE_URL` points past a pooler. Without it, discovery uses `DATABASE_URL`.
- If Postgres is down, running nodes stay connected and nothing crashes. New nodes join after Postgres is back (tested).
- A node notices a dead node when its connection drops. This is at once for a crash. If the network goes silent, it takes up to `net_ticktime` (60 s).
- Discovery runs only when the node runs distributed (a release or `iex --name`). `mix phx.server` and tests stay single.
- If Postgres discovery does not fit, use DNS (`dns_cluster`) or a static host list. This is one line in `Dandelion.Cluster.topologies/1`.

The release configuration is in `rel/env.sh.eex` and `rel/vm.args.eex`. The node is `<app>@$NODE_IP` (or the IP of the container). `RELEASE_COOKIE` must come from the environment, and the node refuses to start without it. Distribution uses one port, 9100, without epmd. The firewall rule between nodes is therefore one port.

### 10.5 The example, grown

The `orders` example gets a flow that touches every piece:

1. `POST /api/orders` creates the order. In the same transaction, it publishes `order.created` on `Platform.PubSub`. This makes one Oban job for each subscriber (§10.7). The service saves the order and its jobs, or it saves neither.
2. The subscribers send the confirmation (logged, no real mail) and update the order count of the customer. This is the topic with subscribers. The service retries each one on its own.
3. After the commit, `order.created` also goes out on `Platform.Broadcast` for live views.
4. The payment provider calls `POST /api/payments/webhook`, as Midtrans, Xendit, or Stripe do. The handler queues a job on the ordered queue with the key `order:<id>` (§10.7.1). `payment.succeeded` marks the order `paid`, and `payment.refunded` marks it `refunded`. The jobs always run in the order that they arrived for that order. This is also the first code path that sets `paid`.
5. Unpaid orders expire with Oban Cron. This runs one time for each cluster and replaces the timer of each node.
6. The service reads product prices through the cache (a small `products` table). It clears the cache on every node when a price changes.
7. The Vue page shows a live order feed over Channels and who is online with Presence. An order made through node A appears for a browser that connects to node C.

### 10.6 Frontend

The frontend uses Vue 3 and blessing-ui (from npm). Vite builds it into `priv/static`, and the same release serves it. This is the fumehood setup. The pages are the orders list with the live feed and presence, create order, and order detail.

`mix dandelion.new --no-frontend` leaves it out, and you do not need Node. This is like `--no-example`. The image build gets a Node stage only when the frontend is there.

### 10.7 No external broker

A message broker does two jobs, and both run inside the app:

| Broker job | Usually | In dandelion |
|---|---|---|
| Work queue: each message is handled once and retried | RabbitMQ queue, Cloud Tasks | an Oban queue |
| Topic: one event, several subscribers, each gets it reliably | Google Pub/Sub subscriptions, Kafka consumer groups | `Platform.PubSub.publish/2` queues one Oban job for each subscriber |
| Fan-out that can drop messages (live updates) | Redis pub/sub | `Platform.Broadcast` (Phoenix.PubSub) |

**Two kinds of pub/sub, two names.** Redis pub/sub and Google Pub/Sub look alike, but they are not the same:

| | `Platform.PubSub`: durable | `Platform.Broadcast`: live |
|---|---|---|
| Like | Google Pub/Sub, Kafka topics | Redis pub/sub |
| Stored | yes, in Postgres | no, memory only |
| Delivery | each subscriber at least once, retried, survives crashes | whoever listens right now, on every node. It is lost if nobody listens. |
| Order | none (a subscriber that needs order uses the ordered queue, §10.7.1) | none across publishers |
| For | work that must happen | live views, presence, clearing caches |

`Platform.PubSub` (`lib/platform/pubsub.ex`) holds `publish/2` and the subscriptions. The subscriptions say which workers receive each topic, and they are listed in one place like the crontab. Subscribers are Oban workers in their domain. They must tolerate two runs (at least once), as with Google Pub/Sub.

An external broker makes one thing hard, and dandelion gets it right. The jobs live in the same Postgres as the data. Saving a change and publishing its event therefore happen in one transaction. With Kafka or RabbitMQ, this is the dual-write problem: you save, the service crashes before it publishes, and the event is lost. Teams usually solve it with an outbox table and a relay process.

#### 10.7.1 Ordered queue, per key

Most queues do not keep order. Cloud Tasks does not, and RabbitMQ does only with a single consumer. When order matters, it usually matters for each key, for example the events of one order or one customer. Kafka partitions, SQS FIFO message groups, and Pub/Sub ordering keys give this. dandelion does the same on Oban.

**The queue is in Postgres and not on a VM.** Every node adds jobs and every node runs them. No node is special.

```
req A (order 42) → VM1 ─┐
req C (order 77) → VM3 ─┼─► Postgres numbers them: A=101, C=102, B=103
req B (order 42) → VM2 ─┘
                            line order:42 → A(101), then B(103)
                            line order:77 → C(102), doesn't wait for A
```

- **Order means arrival at Postgres.** It does not mean the clocks of the VMs, because they drift. If order must follow the source (for example the time of a payment), the source sends a sequence number and the worker checks it.
- **Enqueue.** In the transaction of the caller, take `pg_advisory_xact_lock` on the key. Then insert the job with the key in its `meta`. The lock makes the job id order equal to the commit order for that key. Without the lock, job 102 can become visible before job 101 commits and run first.
- **Run.** Before a job does its work, it looks for an unfinished job with the same key and a lower id (`available`, `scheduled`, `executing`, or `retryable`). If there is one, the job snoozes for a moment and tries again. One partial index on the key (unfinished jobs only) keeps this check cheap.
- **Different keys run in parallel** on all nodes. Within a key, jobs run one at a time, in order.
- **A failing job blocks its key** while it retries. This is what "ordered" means, and Kafka does the same. When the job has used up its retries (it is discarded), it stops blocking and the service logs it, like the dead-letter queue of SQS FIFO.
- **Idempotent.** The provider retries webhooks. The job is therefore unique on the event id of the provider. If the service queues the same event twice, it runs once.
- **A global queue** has everything in one line. It is the same with one fixed key. It runs one job at a time for the whole cluster, with any number of nodes. The docs say so. It is rarely what you want.

One thing to check while we build: a job that runs on a node that dies stays `executing` until the Lifeline plugin of Oban rescues it. It blocks its key until then. The rescue time must be short enough, because the default is long.

#### What it does not replace

The docs say this plainly:

- **Other systems that send you events.** They call your HTTP API, or you keep a real broker at that edge and consume it with Broadway.
- **Kafka-style replay at high volume.** A new consumer re-reads months of events. An events table in Postgres covers the modest version.

### 10.8 Running it

**Local, 3 nodes** (`compose.cluster.yaml`). It has Postgres, three app containers on one Docker network, and nginx in front as the load balancer. There are no privileged containers. The proof is a script, and the docs describe it. These statements are true:

- All three nodes see each other.
- An order created through node 1 shows up live in a browser on node 3.
- If you kill node 2 while jobs are queued, the jobs finish on nodes 1 and 3.
- Cron runs one time for each tick across the cluster, before and after the kill.
- Each `order.created` subscriber runs exactly one time, also when a node is killed in the middle.
- Payment events for one order run in arrival order across the three nodes. The events of other orders run in parallel. The service rescues the job of a killed node before the next job for its key runs.
- Node 2 comes back and joins again. The other nodes do not restart.

**N VMs behind a load balancer.** This is a guide. We did not test it on real VMs, because we have no cloud budget.

- The VMs are on a private network with no public IPs. The load balancer is the only way in.
- Each VM runs the same image (Docker) or release (systemd). `RELEASE_NODE` comes from its private IP, and a shared `RELEASE_COOKIE` comes from a secret store.
- Firewall: open the distribution port (9100, no epmd) only between the app VMs. Open HTTP only to the load balancer.
- Health probe: `GET /health`.
- Rolling deploy: one VM at a time. The other nodes pick up the Oban jobs of a stopped node.
- Optional: TLS for distribution (`-proto_dist inet_tls`), with the certificate setup.

### 10.9 Decided while building

- **Cache.** Use Cachex on each node plus PubSub invalidation. It is simple and uses one library. Use the distributed modes of Nebulex only if a real need shows up.
- **Metrics** (decided and built 2026-10-01). Use `telemetry_metrics_prometheus_core` and a handler at `GET /metrics`. Do not use PromEx. PromEx brings dashboards and plugins that nothing here needs, and the app already defines its metrics with `Telemetry.Metrics`. The app reports these metrics:
  - The request duration by status and the handler duration by route (histograms).
  - Channel joins and socket connections.
  - Database query time and pool-queue time.
  - The Oban job duration by queue, worker, and outcome, and job exceptions.
  - The hits and misses of the dandelion cache. The library emits `[:dandelion, :cache, :fetch]`.
  - The cluster size as this node sees it.
  - VM memory and run queue.

  `METRICS_TOKEN` (optional) makes the endpoint need a bearer token. The endpoint belongs on a private network in either case.

Not in the template at first: **rate limiting**. Until a service is very large, the load balancer does it (Cloud Armor or nginx `limit_req`). §10.13 changed this later.

### 10.10 Steps

1. ✅ Clustering (2026-09-27, moved into the library 2026-09-30). It uses libcluster and `Dandelion.Cluster.Postgres`, the release node, cookie, and port configuration, and `deploy/compose.cluster.yaml` with 3 nodes and nginx. `deploy/cluster-proof.sh` proves that the nodes connect, a broadcast crosses nodes, a killed node drops out and joins again, and a database outage crashes nothing.
2. ✅ Oban (2026-09-30). It adds `Platform.Queue` and `Platform.Cron`. Expiry runs through Oban Cron, and the timer of each node is gone. `OrderService.create/1` queues `SendOrderConfirmation` in the transaction of the order. Step 3 moves it behind `Platform.PubSub`. The cluster proof shows that a job runs one time, and that another node runs again a job that a killed node left in `executing`. The compose file sets `OBAN_RESCUE_AFTER_SECONDS=10`. We write the orphan row by hand, because no job runs long enough to catch one in the middle of its run.
3. ✅ Events (2026-09-30).
   - `Platform.PubSub` has `publish/2` and the subscription list. It makes one Oban job for each subscriber, in the transaction of the caller.
   - `order.created` has two subscribers: `SendOrderConfirmation` and `UpdateCustomerStats`. The second one recounts, so it is safe to run twice.
   - A live broadcast goes out on `Platform.Broadcast` after the commit.
   - `Dandelion.Queue.Ordered` is now in the library. It takes an advisory lock on the key at enqueue and asks "is an earlier job unfinished?" at run. It has a partial index.
   - `POST /api/payments/webhook` takes a token in `x-callback-token` and is unique on `event_id`. It leads to `ProcessPaymentEvent` on the `ordered` queue. `payment.succeeded` gives `paid`, and `payment.refunded` gives `refunded`. We added the order status `refunded`.
   - The proof shows that both subscribers ran one time. The payment and refund of 10 orders race on three nodes, and all end as `refunded`. The proof fails when we remove the order check. The stuck job of a dead node holds its order back until the rescue, and other orders go on.
4. ✅ Cache (2026-09-30).
   - The `products` table and `Dandelion.Cache` (now in the library). It uses Cachex with a 60 s TTL. `fetch/2` reads. `delete/1` clears the key on every node through the PubSub of the app, after the commit.
   - `Dandelion.Cache.Listener` applies the deletes of other nodes. It empties the cache on `:nodeup`.
   - `GET` and `PUT /api/products/:sku`.
   - The proof shows that a price changed through one node is read fresh on all three. A node that loses a node and gets it back starts with an empty cache.
   - The service also prices orders from this table (2026-09-30, see below).
5. ✅ Frontend (2026-09-30).
   - `assets/` has Vue 3 and blessing-ui from npm, built by Vite with npm into `priv/static/app`. `Platform.Web.PageHandler` serves it at `/`. The Dockerfile gets a Node stage.
   - The page has a new-order form, the live order feed, and who is online. They use `Platform.Web.UserSocket`, `App.Shop.Channels.OrderFeedChannel`, and `Platform.Realtime.Presence`. The page also has the order detail with cancel (`#/orders/42`).
   - An order now broadcasts the order itself (`{:order_created, order}`).
   - Generator: `--no-frontend` drops `assets/`, the page, the route, and the Dockerfile stage. `--no-example` also drops the frontend and the order channel. We checked the generated projects: with everything, `--no-frontend`, and `--no-example`.
   - We checked in a real browser (Playwright) against the 3-node cluster. In two browsers, an order made in one appears in the other. Presence counts both and drops one on close.
   - We split the migrations so that `--no-example` has none that touch `orders`.
6. ✅ Docs (2026-09-30). Phrasebook pages 13 to 17 map these items:
   - Redis maps to `Platform.Broadcast`, `Dandelion.Cache`, and Presence.
   - Cloud Tasks and asynq map to Oban.
   - Google Pub/Sub and Kafka map to `Platform.PubSub` with the one-transaction publish.
   - SQS FIFO maps to the ordered queue.
   - "I still need a real broker" maps to Broadway.
   - Cloud Scheduler and Redis locks map to Oban Cron, the leader, and unique jobs.
   - The frontend and channels, the service mesh (node calls), and network splits have pages.

   We brought pages 02 and 09 up to date. We wrote `example/deploy/vms.md` (the N-VM guide) and the READMEs.
7. ✅ Generator (2026-09-30). The templates are the example itself, copied at build time. The parts that belong to the example or the frontend sit between marker lines `@example-start` / `@example-end` and `@frontend-start` / `@frontend-end`. These parts are in the Dockerfile, the cluster proof, and the deploy README. They go whole with `--no-example` and `--no-frontend`. Markers never reach a generated project. The integration tests (`mix test --include integration`) need Docker, network, and Postgres on :55432. They check that the default, `--no-frontend`, and `--no-example` projects compile with warnings as errors and pass format, tests, and credo. The generated frontend builds. The generated cluster proof passes on three containers, with everything and with `--no-example`. We fixed one problem on the way: the generated `deploy/cluster-proof.sh` was not executable.

### 10.11 Orders are priced from the products table

Decided 2026-09-30. This was the one thing that step 4 left open. `OrderService.create/1` reads the price of each item from `ProductService.get/1`. This is the cache, so a hot product costs no query. The service ignores any `price_cents` in the request, because a client must not set its own prices. The service copies the price onto the order line (`order_items.price_cents`), so a later price change does not rewrite old orders. An unknown SKU gives `400 unknown product: …`, and the message names every unknown SKU. Product prices have the same ceiling as an order line (10¹² cents), so a price cannot fail the validation of the line. The UI sends only `sku` and `quantity`. The Docker cluster has no products or users until `deploy/seed.sh` adds some. `mix setup` seeds the same for local development.

### 10.12 Logins in the example

Decided 2026-10-02. "Where do I put my auth plug?" is the first question of a Go developer. The example answers it with a small, real login. The login is in the example and not in the library, because auth belongs to the app.

- **A domain, `accounts/`,** in the usual layout: the user model, repo, service, handlers, and the plug. It belongs to the example, so `--no-example` projects do not have it. Their socket takes any connection, and a comment says where to put an identity check.
- **No new dependency.** Passwords use PBKDF2-SHA256 from `:crypto` (600 000 iterations, a salt for each hash, and the count stored in the hash). Tokens use `Phoenix.Token` (signed, they expire after a day, and nothing is stored). The cost is that you cannot revoke a token before it expires. The code says so. A stronger hash (argon2 or bcrypt) is one module to swap.
- **Stateless on purpose.** Every node shares `SECRET_KEY_BASE`, so a login on one node is valid on all nodes. The cluster proof logs in one time, and three nodes answer. A session table or Redis is exactly what the project avoids.
- **Roles are two strings** (`customer` and `admin`). The service never takes them from a request.
- **Ownership is a service rule.** `orders.user_id` says who made an order. `OrderService.get/list/cancel` take a viewer and scope the query. A customer sees their own orders and gets `:not_found` (404) for the orders of others. An admin and the system (workers, the webhook, with no viewer) see all orders. Prices and the live feed are for admins only.
- **Router pipelines say what each route needs** (`:authenticated` and `:admin`). These routes are public: the catalog, `/health`, `/metrics` (its own token), and the payment webhook (its own token).
- **Not covered at that time:** password reset, email confirmation, account lockout, 2FA, and token revocation. (§10.13 covers rate limiting for each address. §10.23 adds the reset, the confirmation, and the lockout.)

### 10.13 Reliability of the web layer

Decided 2026-10-08. The database failures (§11.7) were about what Postgres does to the app. This section covers what clients, load, and a stop signal do to the app. There are four items. Each has a number in the configuration and a check in `deploy/reliability-proof.sh` (claim 14).

- **Request timeouts.** The service cuts off a body that stops arriving after 10 s (408, `read_timeout` of `Plug.Parsers`). It closes a connection that sends nothing after `READ_TIMEOUT_MS` (60 s). Bandit answers 408 and closes after about two of these. A query that has not answered in 5 s fails (`DB_QUERY_TIMEOUT_MS`), and the API turns this into a 503. There is no deadline around a handler as a whole. To kill a process in the middle of a transaction is a worse failure than a slow request. Every handler here waits on the database, and its timeout bounds the handler. `READ_TIMEOUT_MS` must stay above the WebSocket heartbeat (30 s). Otherwise the service disconnects idle browsers.
- **Connection limit.** Each node has at most `MAX_CONNECTIONS` (4096) open connections. The other connections wait in the queue of the operating system (Thousand Island). A flood therefore costs time and not memory. The proof sets the limit and reads it back. It does not fill the limit (see LIMITS.md).
- **Graceful shutdown.** `Dandelion.Drain` (library) works like this. On SIGTERM, `Platform.Application.prep_stop/1` sets the node to draining, and `/health` answers 503. The node keeps serving for `DRAIN_DELAY_MS` (5 s) so that the load balancer notices. Then the supervision tree stops in reverse order. The endpoint stops first and finishes its requests for up to `SHUTDOWN_TIMEOUT_MS` (20 s). Then the jobs stop, and then the database. The `stop_grace_period` of the container (40 s) must be longer than all of this. A load balancer that does not read `/health` still loses nothing. The node keeps accepting until the end of the delay, and clients retry refused connections.
- **Rate limiting.** `Dandelion.RateLimit` (library) uses fixed windows in ETS, for each node. `Platform.Web.RateLimit` applies two buckets for each client address on `/api`. One bucket is for logging in and registering (10 a minute). The other bucket is for everything else (300 a minute). The service never limits `/health`, `/metrics`, and the payment webhook. A 429 carries `retry-after`. The limit works for each node on purpose. A limit that asks Postgres or the other nodes on every request becomes the thing that fails when the cluster struggles. A cluster of three allows about three times the limit. This is fine for the stop of a loop or a password guesser. The client address is the address of the connection. Behind a load balancer that overwrites `x-forwarded-for`, `TRUST_FORWARDED_FOR=1` makes the service use the header. The nginx in the compose file does this, with `$remote_addr`.

### 10.14 Asking again: idempotency keys, and a rolling deploy

Decided 2026-10-08. We tell clients "503, retry" (§10.13, §11.7). This is safe only if a retry cannot make a second order. `POST /api/orders` takes an `Idempotency-Key` header (1 to 255 characters, optional).

- **The service saves the key with the order, in its transaction.** The fields are `orders.idempotency_key` and `request_hash`, with a unique index on `(user_id, idempotency_key)`. An order exists exactly when its key exists. Whatever happened to the first request, the retry finds the order or makes it, and never both. The cause can be a stopped node, a lost answer, or a stalled database. Postgres decides. There is no cache, no lock, and nothing in memory that a restart can lose.
- **The same key with the same request gives the same order.** The answer is 200 with `idempotent-replayed: true`, and no new event. **The same key with a different request gives 409**, and the service makes nothing. Keys belong to one customer. A request that failed validation made nothing, so its key is free. The fingerprint covers what the client sent (email, SKUs, and quantities). It does not cover the prices that we added. A price change between a request and its retry is therefore still the same request.
- **Two retries that race** (twenty at once in the proof) are safe because of the unique index. The insert of the loser fails, and it answers with the order of the winner.
- **Not covered.** Keys live as long as the order, and they do not expire. Only `POST /api/orders` takes a key. Other writes (cancel and mark paid) are already safe to repeat. `mix dandelion.gen.domain` does not generate keys.
- **A rolling deploy** stops and starts the nodes one at a time under load. This test ties §10.13 together. Each node drains, exits with code 0, and joins again. Clients that got 503 retry with their key. Streaming request bodies hold the requests on the node (`proxy_request_buffering off` in nginx). With buffering, the balancer absorbs a slow client, and the node never sees it.
- **Found while we tested it.** On this machine, when we stopped a container, one Postgres `COMMIT` waited several seconds on the disk (`IO:WalSync`). Every commit that sends a `NOTIFY` waits behind it. Postgres takes a database-wide lock while it queues a notification, and it holds the lock until the commit is on disk. Our order inserts notify through Oban. A slow disk therefore stalls every writer and not only one. Those requests hit the statement timeout of 5 s. The service now answers them with 503. Before, it answered 500 (`Postgrex.Error` `query_canceled`). This is the reason that retries with a key matter. We did not prove that the cause is the disk of the host and not the app. It did not happen with the same load and no stopped node, or with another container stopped (LIMITS.md).

### 10.15 Webhooks we send, and calling other people's servers

Decided 2026-10-08. The example received a webhook (from the payment provider) from the start. Sending a webhook is the other half. It is also the first place where the app calls a server that it does not control. A slow or dead server can therefore hurt the app here first.

- **Library:** `Dandelion.Webhook` (sign and verify, pure) and `Dandelion.Resilience` (timeout, retries, and circuit breaker). They work for each node, like `RateLimit`, and nothing asks Postgres on a call. **App:** the `webhooks` domain. It has endpoints in a table. A subscriber (`FanOut`) on `order.created` makes one `Deliver` job for each endpoint. A worker delivers.
- **At least once, one id.** An event is `evt_<topic>_<order id>`. It is the same on every attempt and for every endpoint. It is the `webhook-id` header. A receiver that sees an id twice has seen the event. Delivery jobs are unique for each (endpoint, event). A `FanOut` that runs twice therefore queues once.
- **Signed.** The headers are `webhook-id`, `webhook-timestamp`, and `webhook-signature`. The signature is HMAC-SHA256 over `id.timestamp.body` with the secret of the endpoint, which the service shows one time. It follows Standard Webhooks, so receivers can use existing libraries. The service stores secrets in the clear, because it needs them to sign. The key management of the deployment must encrypt them at rest.
- **What the service retries.** It retries 5xx, 408, 429, timeouts, and connection errors. It uses the backoff of Oban (30 s doubling to an hour, ±20 %) and 10 attempts. A 410 deactivates the endpoint. Another 4xx means that the receiver said no, and the service does not retry it.
- **The circuit.** After 5 failures in a row for a host, this node stops calling it for 30 s. The jobs snooze (30 s, no attempt used). They do not each wait out a 5 s timeout. Then the circuit lets one call through. A dead receiver costs a timestamp and not worker time. The `webhooks` queue is separate, so a slow receiver cannot starve the jobs of others.
- **The service checks where it sends.** It allows `https` only (http by configuration). It refuses `localhost` and private addresses (by configuration). It follows no redirects. It resolves the name again at delivery time and refuses it if the name now points inside. One gap remains: a name that changes between our check and the connection. The gap is real and is in LIMITS.md.

### 10.16 Flags: settings that change while the app runs

Decided 2026-10-08. A kill switch is the first thing that you want in an incident. "Redeploy with the new value" is the wrong speed for it.

- **Library:** `Dandelion.Flags`. A table (`dandelion_flags`: key and a jsonb value) holds the flags. The library reads them through `Dandelion.Cache`, so a read costs nothing. `put/2` saves the flag, and then it clears the cached copy on every node (`Cache.delete/1`, after the commit). This is the rule that §10.2 already has. Nothing new moves between nodes. It is the own message of the cache.
- **Postgres decides.** A node that the others cut off misses the message. It serves its old value until the cache entry expires (a minute). Then it reads the table. The proof splits one node off and measures it. The node is stale at once and fresh at 51 to 57 s. The cache also keeps a flag that nobody set (as "not set"). A request for a flag that nobody set therefore does not query each time.
- **It fails to the default that you chose.** If Postgres cannot be read and the value is not cached, `get/2` returns the default and logs. For a kill switch, choose the safe side. For example, `enabled?("orders.enabled", true)` keeps orders on if the table cannot be read. A database that is down fails the order anyway.
- **Not here:** targeting for each user or percentage rollouts (a flag is one value for everyone, but a map value and your own code can do more), a history of who changed what, and a UI. `Flags.put/2` takes no actor. Audit what matters in the admin handler.
- **The example.** `orders.enabled` pauses new orders (503 and `retry-after`, also for a retry with an idempotency key). Admins change flags at `/api/flags`. Every project, with or without the example, starts `Dandelion.Flags` and gets its table.

### 10.17 Uploads on a directory the nodes share

Decided 2026-10-08, for local disk. We have no cloud budget, and S3 is one adapter away (§10.26).

- **Bytes in files, meaning in Postgres.** `Dandelion.Storage.Local` (library) keeps the bytes under a random key. The `stored_files` row of the app says whose the bytes are. It also has the name to show, the type, the size, and the SHA-256. The service never makes a key from what the client sent. No name can therefore reach outside the directory.
- **Write the file first, then the row.** A crash between the two steps leaves a file that nothing points at. The service can collect it, because `Local.keys/1` lists what is there. A row that points at nothing never happens. If the service cannot save the row, it removes the file. `put/2` copies to a temporary file and renames it. A reader therefore never sees half a file, and a node that is killed in the middle of an upload leaves no file at all. The proof kills all three nodes.
- **The bytes decide what a file is.** The service finds PNG and JPEG and PDF by their magic numbers. It finds text if the first 8 KB are valid UTF-8 with no NUL. A script with the name `picture.png` and the type `image/png` is kept as `text/plain`. The service refuses an executable with the name `picture.png`. The name is only for showing back (no path, no control characters, 255 characters). Downloads are `attachment` and `nosniff`, with the type that we worked out. A browser therefore never runs or renders an upload as a page of ours.
- **The directory must be shared.** The load balancer sends a download to any node. The other nodes must be able to read the file that one node took. Use a mount: NFS, EFS, a `ReadWriteMany` volume, or a Docker volume on one host. The proof shares one volume. Its negative control gives each node its own volume and fails. Without a shared mount, put the files in object storage. That adapter has the same three functions.
- **Limits.** A file has 5 MB at most (`UPLOAD_MAX_BYTES`, at most 5 000 000). The endpoint reads a multipart body of up to 6 000 000 bytes (413 beyond that). The wait between reads of the body is 10 s. The load balancer (nginx, `client_max_body_size 6m`) answers 413 above that size itself. The default of nginx is 1 MB. If we left it alone, the 5 MB limit of the service is unreachable through nginx. The browser proof of the console found this. Uploads are not resumable. There is no virus scan, no image processing, and no quota for each user. The rate limit is the only brake.

### 10.18 An audit log

Decided 2026-10-09. The admin API (flags, webhooks, and prices) and the states near money (cancel, paid, and refunded) change things that people will ask about later. The application logs rotate. They must not be the answer to "who set that flag?".

- **Library:** `Dandelion.Audit`. It has one table, `record/4`, and `list/1`. It records in the same transaction as the change. `Dandelion.PubSub` already has this rule. An entry exists exactly when its change exists. A refused or rolled-back change leaves nothing, and a committed change cannot lack its record. Flags needed a hook for this (`in_transaction:`), because they save first and clear caches after the commit.
- **The database makes it append-only.** A trigger refuses UPDATE, DELETE, and TRUNCATE, from any node and any code path. `prune/1` sets the retention. It says so for the length of its own transaction. A superuser can still disable the trigger, and entries are not hash-chained. This stops accidents and honest bugs. It does not stop a person who owns the database.
- **What an entry holds.** The actor (`user:5`, `system:payment`, or `anonymous`). The action (`order.cancelled`). To filter by family, add a trailing dot. The subject (`order:42`). JSON details (the old and new values). The request id of the request that made the entry. This is the same id that the response carried, and the logs and the trace have it. An entry never holds secrets. The secret of the webhook and passwords are in no entry, and the proof searches for them.
- **Who is recorded.** For a viewer, it is `user:<id>`. The webhook of the payment provider is `system:payment`, through its job. The sweep of unpaid orders is `system:expiry`. Logins record success and failure. The failed login is `anonymous`, with the email as typed, trimmed, and cut to 100 characters. The rate limit applies (10 a minute for each node), but each attempt is a row. Prune on a schedule.
- **Not recorded:** reads, order creation (the order is its own record), and uploads. To answer for something else, add a `record/4` in its transaction.

### 10.19 Email

Decided 2026-10-09. The order confirmation was a log line that said "sent". For a service that sends mail, the main question is what happens when it cannot send.

- **App, not library.** [Swoosh](https://hexdocs.pm/swoosh) is the library, and it does the SMTP. What is ours is the policy around it (`App.Notifications.Services.EmailService`). That policy is specific to each app, so it stays in the example.
- **Never in the request.** The service saves and answers an order long before any mail. The confirmation is a subscriber of `order.created` (§10.2). It is a job in its own `mail` queue. As with webhooks, a slow server cannot use up the slots of other jobs.
- **Written down, then sent.** `send_once/5` first makes (or finds) a row in `outgoing_emails` under a `dedupe_key` (`order_confirmation:<id>`). Then it sends. Then it marks the row `sent`. A rerun of the job (jobs are at least once) finds the row, sees `sent`, and does nothing. One window remains, as usual. The server accepted the message and we died before the update of the one row. The retry then mails again. The service deduplicates everything else.
- **What a failure means.** The send goes through `Dandelion.Resilience` with a circuit for each mail server. A server that keeps failing is left alone, and the jobs snooze (30 s, no attempt used). They do not each wait out a connection timeout. Oban retries a temporary failure (a timeout, a refused connection, or a 4xx) with a doubling wait (10 attempts). A permanent failure (the server says 5xx, for example no such user) marks the row `failed` and ends the job. To retry a mistake only delays finding it. The row and `/api/emails?status=failed` show it.
- **No configured server is not an error.** Without `SMTP_HOST`, the message goes to the log (the logger adapter of Swoosh) and counts as sent. A new project therefore works.
- **Found by running it.** Swoosh refuses an SMTP configuration whose `username` is `nil`, also with `auth: :never`. The first cluster run raised an error on every send. The system did what it must do until we fixed the configuration: it kept the mail queued, retried, and counted the attempts.
- **Not here:** HTML mail and templates, attachments, bounces and complaints (a webhook of a mail server back to us), unsubscribe handling, a send rate for each recipient, and DKIM and SPF (the job of the mail server).

### 10.20 Search

Decided 2026-10-10. "Postgres replaces Elasticsearch" is believable only for the part that is true: a catalog, a help center, a few hundred thousand rows. It is believable only if we show where Postgres is weaker.

- **No second system.** A generated `tsvector` column and a GIN index sit on the table itself. A row is searchable when its transaction commits. A deleted row is gone from the next search on every node. Nothing is indexed on the side, so nothing can be late or lost, and no deploy needs a reindex. The proof renames a product ten times through the load balancer. Straight after each rename, it searches for the new name and the old name from all three nodes. It finds no stale answer. An external search index cannot give you this property cheaply.
- **The text of the user is data.** `Dandelion.Search.tsquery/1` keeps only letters and digits and builds the query itself (`gre:* & tea:*`). The operators of the query language of Postgres never see user input. No input can therefore make it fail. The proof sends a SQL injection, quotes, operators, and 600 characters. The text is a bound parameter anyway. `websearch_to_tsquery` is also safe from errors, but it has no prefix matching, and a search box needs prefix matching.
- **`simple`, not a language.** The default configuration lowercases and splits. It does not stem and has no stop words. This suits product names and any language. Stemming (`english`, `indonesian`, and others) is an option of the migration and of the search. The service removes accents on both sides with an immutable `unaccent` wrapper, because an index can use only immutable functions.
- **Ranking** uses weights for each column (`:a` for the name and `:b` for the description) and `ts_rank_cd`. Ties go by name. This is good enough to put the product that is called "Green tea" before the cup that mentions it. It is not relevance tuning.
- **Typos are a fallback.** If the words match nothing, the search tries similar words (trigram `word_similarity` with a lowered threshold), and the answer says `"match": "fuzzy"`. A query that finds something never mixes in guesses.
- **Where it is weaker than a search engine.** It has no synonyms, no "did you mean", no faceting, no analysis for each language beyond what Postgres ships, and no relevance learning. A very large corpus (tens of millions of rows) or a heavy write load on the same table is where a dedicated engine is worth its cost. Postgres cuts snippets from the stored text. They are plain text with `[[` and `]]` around matches. The client must escape them, and they are never HTML of ours.

### 10.21 The dashboard

Decided 2026-10-10. `/metrics` (§10.7) is the data, and nobody reads it as text. The project has one dashboard, provisioned from a file. Reviewers can review and version it like code, and the same dashboard comes up on every machine.

- **The dashboard is laid out as questions and not as metrics.**
  - *Is it up?* shows the nodes in the cluster and the nodes scraped, draining, 5xx, request rate, p95, cache hit ratio, and jobs that wait.
  - *Traffic* shows requests by status and by node, latency, and the slowest routes.
  - *Protecting itself* shows 429 and 503, calls to other services by circuit and result, circuit changes, and draining.
  - *Background work* shows queue depth, jobs by worker and outcome, job time, and jobs that raised an error.
  - *Database, cache and the VM* shows those three.
- **`deploy/dashboard-proof.sh` checks every query against live metrics.** It makes the things happen that the panels are for: traffic, a client over its limit, orders paused by a flag, a mail server that goes away, and a node that gets the stop signal. Then it runs every query of the dashboard. It requires the 16 panels that show those things to have data. A panel with a misspelled metric, or a metric that nothing emits, fails there. Without the proof, the panel stays quietly empty on a screen that nobody looks at until the incident.
- **New metrics for it.**
  - Calls and circuit changes by circuit (`smtp:mailpit` and `webhook:example.com`).
  - Queue depth by queue and state. The metric reads the table, and every node reports it. The dashboard takes the `max`. The service reports every queue and state, with zero when empty. A flat line therefore means empty, and a missing line means nothing.
  - `draining`. The service sets it when draining starts and not at the next 10 s poll. Otherwise a drain of 5 s never shows.
- **Not shipped.** The project ships no alert rules (Prometheus Alertmanager or Grafana alerting). What to page on depends on what the service is for. The descriptions of the panels say what each number must be. Prometheus keeps its data in the container (not in a volume), so a restart starts a new history. The compose file scrapes every 2 s so that a short test shows something. Use 15 s in real life.

### 10.22 A deploy that changes the database

Decided 2026-10-11. A rolling deploy (§10.14) puts two versions of the app on the same table for a while. Suppose a schema change works only with the new version. Then that while becomes an outage. "Run the migration, then restart" does exactly that.

- **Expand, then roll.** First, run a migration that the old code does not notice. Examples are a new column with a default or a nullable column, a new table, and a new index built `CONCURRENTLY`. Second, deploy the new code (it reads and writes the new column), one node at a time. Last, when no old node is left, do the contraction: drop the column that nobody reads, and add the `NOT NULL`. You can deploy each step on its own, and you can reverse each step on its own. Do not rename or drop in the same release as the code that stops using the old name. The control of the proof does this, and both versions fail.
- **The proof builds two versions for real.** The example tree plus a patch (`deploy/versions/order-channel.patch`) becomes a second image. The migration runs from that image while all three nodes still run the first version. Then the proof replaces each node. It tells the load balancer about the new address of the node (nginx resolves names one time, and a real balancer discovers nodes). The cluster must be whole again before the next replacement. The load runs throughout: slow clients, retries with idempotency keys, and every order read back through any node. A request that fails with anything but a 503 fails the proof.
- **The patch is a real maintenance cost.** It must apply to the current code. When it stops applying, the proof says so. It does not test something else.
- **Not covered.**
  - A migration that locks a big table. The table of the proof is small. Take the usual care: `lock_timeout`, concurrent index builds, and batched backfills.
  - A rollback of a version. The old code over the new column is the same situation. It works because the column has a default.
  - A change in what jobs carry between versions.
  - A change of the Erlang or Elixir version between nodes.

### 10.23 Keeping an account yours

Decided 2026-10-12. The login (§10.12) said in its not-covered list: no reset, no confirmation, and no lockout. Email (§10.19) made the first two possible. The rest followed from careful use of it.

- **A link is a secret with a hash.** It has 256 random bits, and the service keeps only the SHA-256 (`user_tokens`). One `UPDATE … RETURNING` uses it up. If two requests have the same link, one wins. A new link of a kind replaces the earlier links. The link lives in one place, the email. It is not in the arguments of the job, because those stay for a week. The service blanks the body of the email row after the mail server has it. The proof looks for the link in every table.
- **A request for a reset says nothing.** An address with an account and an address without an account get the same 202. A job sends the email (`SendAccountEmail`, retried, protected by a circuit like all mail). A mail server that is down therefore delays the email. A registration or a request never waits for mail. A second request within a minute sends nothing more. Admins can see in the audit log whether the address was known.
- **A reset ends the old sessions.** Login tokens are signed and stateless (§10.12), so the service cannot revoke them. Each token now carries a fingerprint of the password hash of the user, and the service checks it against the current one. A new password makes every token invalid that was made before it, on every node, and the service stores nothing. (To revoke one session without a change of the password, you still need a session table.) A reset also confirms the address, because only its owner can have read the email. A reset also unlocks the account.
- **The lockout works for each address and lives in Postgres.** The table `login_throttle` has one row for each address typed. The service counts under `SELECT … FOR UPDATE`, so simultaneous guesses on different nodes are counted exactly. Five wrong passwords in a row lock the address for 15 minutes, also for the right password. Otherwise the guessing continues. An address that nobody has is locked in the same way. A lock therefore does not tell an attacker which addresses have accounts. This sits next to the rate limit for the address of the client (§10.13, in memory, for each node). One slows a client, and the other protects an account from everybody. The price is the classic one: a person who knows an address can lock its owner out for 15 minutes. A reset (a message to the owner) unlocks the address for this reason.
- **The service records the confirmation, and a setting decides what it gates.** The field is `email_confirmed_at`. `require_confirmed_email` (off by default) makes an order need it. The app decides which actions to gate. The library does not decide.
- **Not here:** two-factor login, "remember this device", password strength beyond length, breach checks, and a UI beyond the API. The Vue console has the pages (§10.24).

### 10.24 The console

Decided 2026-10-12. The console was one page of orders. A service that has search, uploads, an audit log, and a kill switch needs a face for them. The Vue half of the aim of the project needs more than a list. It needs a place to see how an Elixir API and a Vue app fit together.

- **One page for each thing the service does.** The console has a sidebar and a hash router (`src/router.ts`, 20 lines) with no router library. The pages are `src/pages/*.vue`. Each page is a few small functions over `src/api.ts`, one typed client. Every call returns `{ok, data}` or `{ok: false, error}`. Staff see everything. A customer sees Products and Files. A staff page that is opened by hand says that it is for staff. The server enforces this, and the console only does not offer the page.
- **Text is text.** Search snippets arrive as plain text with `[[` and `]]` around the matches (§10.20). `src/highlight.ts` cuts them into pieces, and the template shows each piece with `{{ }}`. The console has no `v-html` anywhere. The name or description of a product that an admin writes appears as the characters typed, however the admin writes it. The browser proof adds a product whose name is `<i>…</i>` and makes sure that nothing is italic.
- **Typing is not a request for each key.** The search waits 150 ms after the last key. It drops the answer of a search that a newer search has replaced (a counter). It aborts the request that it no longer needs (`AbortController`). If you type "green" fast, the page shows the answer for "green" and not the late answer for "gre".
- **The links in emails open console pages.** They carry their secret after the `#`. A browser never sends that part. No request line, proxy, or access log has it. The server cannot redirect it either. The secret never reaches the server until the page posts it. `PUBLIC_URL` says where the console is.
- **The shared failure messages say what to do.** A 503 with no message of its own says "the service is busy: try again in a moment" (a person presses the button again). A locked address says for how many minutes. A paused service says that it is paused.
- **A real browser tests it,** because what can go wrong is in the page and not in a function. A component that is a fragment cannot be hidden with `v-show`. The orders list stayed on every page until the screenshot of the proof showed it. A confirm dialog that nothing tells to close stays open over the page. A switch is enabled before its data has loaded. `npm test` covers the one pure piece (the highlighter) with the built-in runner of Node. You install nothing.
- **Not here:** type checking (`vue-tsc` is not wired in), end-to-end tests of other browsers (Chromium only), translations, a dark theme beyond what the component library does, and offline use.

### 10.25 Backup and restore

Decided 2026-10-13. The cluster survives a node failure, a partition, and a deploy. None of them touches the one thing that it cannot survive: the loss of the state itself. "Postgres decides" helps only while a Postgres exists.

- **Two kinds of state, two copies, in an order.** The database goes first, in one `pg_dump`. This is a single snapshot, so what the service committed together is in the dump together or not at all. An example is an order, its items, and the events queued with it. The service copies the uploaded files after the dump. Every file row in the dump then has its bytes in the copy. A file stored in between is an extra that nobody lists. The other order leaves rows without bytes.
- **The cluster keeps serving.** `pg_dump` takes its snapshot without a block on writers. A backup is of the moment that the dump began and not of the last order.
- **A restore replaces, and starts what it can start.** It checks `SHA256SUMS` first, so it refuses a damaged backup before it drops anything. It drops and recreates `acme` and restores. It puts the files on the volume with a one-off container, so no node has to run. It starts the rest. The schema comes in the dump, so the migrate step finds nothing to do. Sequences come back, so the id of a new order is after the restored ids.
- **The queue handles work in flight.** A job that was `executing` in the snapshot has no node behind it after a restore. The lifeline of the queue gives it back after `OBAN_RESCUE_AFTER_SECONDS` (§10.5). Jobs are at-least-once with dedupe keys already. Nothing in the restore knows about jobs.
- **Not here:** point-in-time recovery (WAL archiving and `pg_basebackup`). The backup is as old as the last dump, encryption or copies on another machine (the scripts write a directory, and where it goes is your decision), a schedule, the restore of one table, and a restore into a Postgres major version that differs from the version of the dump.

### 10.26 Files in a bucket

Decided 2026-10-14. A directory that every node can see (§10.17) is the answer for one machine. Most deployments keep files in a bucket, and nearly all of them speak the S3 API.

- **S3-compatible, not "S3".** One adapter for the API (`Dandelion.Storage.S3`) reaches AWS S3, the interoperability endpoint of Google Cloud Storage (HMAC keys), Cloudflare R2, Backblaze B2, Ceph, and the small servers that we use here. A native Google Cloud Storage adapter is a second implementation with its own sign-in (service accounts and OAuth). It gives little that a user of the first adapter cannot already do. It is not here.
- **We tried it against two servers that are not Amazon.** An adapter that has met only one server has met the habits of that server. The two servers are SeaweedFS and Garage (MinIO is in maintenance mode). Both run in Docker for the proof. We tried nothing here against a paid cloud (LIMITS.md).
- **An adapter is four functions** (`put`, `fetch`, `delete`, and `keys`). Each takes the configuration of the adapter first. They are now written down as callbacks. `fetch` answers `{:file, path}` or `{:binary, bytes}`, which is what `send_download` takes. This is the only place where the web layer learned that more than one kind of storage exists.
- **`Req` does the signing.** `aws_sigv4` is in the HTTP client that the example already uses. Signature V4 written by hand, or a dependency of its own (ex_aws), are the heavier answers. `Req` is an optional dependency of the library. Without it, the module does not compile, and nothing else is affected.
- **The adapter returns a failure and does not retry.** It sends one request with a 15 s timeout. A download that cannot reach the bucket gives a 503 with `Retry-After`, and the client asks again. An upload gives the same answer. The bytes go first and the row second (§10.17). A bucket that refuses leaves no row. A crash in between leaves an object that nothing points at (`keys/1` lists it). Retries belong to the caller, who knows whether the request is safe to repeat. It is safe, because of the idempotency keys.
- **Whole files in memory,** because the limit of the example is 5 MB. Multipart upload and streaming are the way past that limit, and they are not here. Presigned URLs are not here either. The bytes go through the node, so the authorization and the `nosniff` and attachment headers of §10.17 apply to a bucket as they apply to a directory.
- **The row says nothing about where.** The key is all that `stored_files` keeps. To move from a directory to a bucket, you copy objects and change the configuration. You do not run a migration. That copy is not here.

## 11. The library

Decided 2026-09-30. There are two hex packages, like `phoenix` and `phx_new` of Phoenix:

| Package | Is | Used as |
|---|---|---|
| `dandelion` | the library: the cloud pieces that are the same in every project | `{:dandelion, "~> 0.2.0"}` in a project's deps |
| `dandelion_new` | the generator | `mix archive.install hex dandelion_new`, then `mix dandelion.new` |

A generated project depends on the library. In its own repo, it keeps what the app shapes: the router, the endpoint, the sockets, Presence (it needs the `otp_app` of the app), the cron schedule, the subscription list, `application.ex`, the repo, and every `lib/app/<domain>/`. The library is thin over Oban, Cachex, Phoenix.PubSub, and libcluster. It is not a new API on top of them.

Why: A fix reaches every project through `mix deps.update dandelion`. The crash loop of libcluster was one such fix. Without the library, each project carries its own copy. The cost is that you read these modules in `deps/` and not in `lib/`. They therefore stay small and documented, and the phrasebook points at them.

| Was (`lib/platform/…`) | Library module | The project passes |
|---|---|---|
| `cluster.ex`, `cluster/postgres.ex` | `Dandelion.Cluster` | `otp_app:`, `repo:`; `config :app, Dandelion.Cluster, database_url:` |
| `cache.ex`, `cache/listener.ex` | `Dandelion.Cache` | none |
| `queue/ordered.ex` | `Dandelion.Queue.Ordered` | none |
| `pubsub.ex` | `Dandelion.PubSub` | the topic → subscribers list (configuration) |
| `queue.ex` | `Dandelion.Queue.config/1` | Oban overrides, cron schedule |
| the ordered-queue index migration | `Dandelion.Migration.up/0` | called from the migration of the project |

### 11.1 Layout and working in the checkout

```
dandelion/          mix.exs, lib/   the library (hex: dandelion)
  installer/        the generator (hex: dandelion_new)
  example/          depends on the library by path ("..")
```

`example/mix.exs` has a dev-only `dandelion/0`. In a checkout, it uses the library from `..` (or `DANDELION_PATH`). Elsewhere, it uses hex. The generator writes the plain hex line and drops the function. The Docker build cannot see `..`, so `deploy/vendor-dandelion.sh` first copies the library into `example/vendor/dandelion` (gitignored). A named build context can do it, but it needs buildx. Until the library was on hex, the integration tests did the same for generated projects.

### 11.2 Steps

1. ✅ Library skeleton and `Dandelion.Cluster` (2026-09-30). The hex package name went back to `dandelion_new` for the generator. The 3-node proof passes with the library.
2. ✅ `Dandelion.Cache` (2026-09-30). The child spec is `{Dandelion.Cache, pubsub: Platform.Broadcast}`. The PubSub name is an option, and the library keeps it in a `:persistent_term` for `delete/1`. The cachex dependency of the example is gone, because it comes with the library. The proof passes. *We changed it the same day, because recording the evidence found a problem.* `fetch/2` first used `Cachex.fetch`, whose loader runs in another process. A caller that was already inside a transaction then made that process wait for a second connection. This was a failure of 1 s in tests and a risk of a pool deadlock in production. The loader also cannot see the uncommitted writes of the caller. `fetch/2` now loads in the process of the caller. Concurrent misses therefore each load, and there is no stampede protection. The docs say so, and `Cachex.fetch/3` is the way out.
3. ✅ `Dandelion.Queue.Ordered` and `Dandelion.Migration` (2026-09-30). The ordered queue asks the repo of Oban (`Oban.Repo` with `Oban.config(Oban)`). It needs no repo option and works with the default Oban instance. The index migration is `Dandelion.Migration.up/0`. The migration of the project calls it, like `Oban.Migration`. The library now has a test repo (Postgres on :55432, `priv/test_repo`). It tests the queue with its own worker. The ordered-queue tests of the example moved there.
4. ✅ `Dandelion.PubSub` and `Dandelion.Queue.config/1` (2026-09-30). `Dandelion.PubSub.publish(subscriptions, topic, payload)` takes the map of topics to workers from the app. The list therefore stays in the project (`Platform.PubSub`, a module of 15 lines), and the library holds only the mechanism. A topic that is not in the map raises an error. `Dandelion.Queue.config(otp_app:, repo:, crontab:)` holds the queue defaults (`default` and `ordered`), the lifeline, and the pruner. It merges `config :app, Oban`. `Platform.Queue.config/0` is one call to it. Both have library tests.
5. ✅ Docs, then publish. Both are done.
   - Docs (2026-09-30): The root README is now the hex page of the library. It says what the six modules are and replace, gives one wiring example and the rules, and links to the rest on GitHub. We also added the CHANGELOG and ex_doc (`mix docs`, modules grouped, no warnings), and we checked `mix hex.build`.
   - Published: `dandelion` 0.1.0 and `dandelion_new` 0.1.0 (docs on hexdocs).
   - The integration tests can build generated projects against the published library (`DANDELION_FROM_HEX=1`). `evidence/record.sh tests` does this.

### 11.3 Evidence

Decided 2026-09-30. Every claim has a recording in `evidence/`. The logs are the primary evidence, and the GIFs are for people who prefer to watch. `evidence/record.sh` regenerates them from the code in the checkout. There were eight claims and three negative controls (ordering off, cache broadcast off, and job rescue off). The same proof must fail for them. `LIMITS.md` says what we did not prove. The page shows which node each browser connects to, so a recording can show two browsers on two nodes. See `evidence/README.md`.

### 11.4 The partition proof

2026-10-01. `example/deploy/partition-proof.sh` splits the 3-node cluster into `node1 | node2 + node3`. It gives a different wrong cookie to each side and then disconnects. It heals when it restores the cookie. Both halves still reach Postgres. The proof checks the table of §10.3:

- A live broadcast does not cross the split.
- A cut-off cache goes stale and is emptied on the heal. The proof checks an entry that it cached just before the heal, so the cause cannot be a TTL expiry.
- Jobs, events, and ordered payments still run exactly one time.
- One cron leader exists throughout.
- Presence is split during the split and merged after it.

The evidence is in `evidence/09-network-partition/`, with a negative control (the clear on `:nodeup` removed) in `evidence/controls/`. Not covered: a half that Postgres cannot reach, and an asymmetric or flapping split.

### 11.5 `mix dandelion.gen.domain`

2026-10-02. The generator makes a project, and this task adds to one. `mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer paid:boolean` writes these files in the layout of the project:

- The model (schema and `create_changeset`).
- The repo.
- The service (create, get, and list with the same page checks as orders).
- The handler and JSON.
- A migration.
- A test for each layer.
- A fixtures module.
- Three routes in `lib/app/billing/routes.ex`. A new domain also gets one line in `lib/app/router.ex`.

Decisions:

- **It gives the shape and not the rules.** It generates create, show, and list. You write the business rules (a cancel, a state change, or an event) by hand, the way `shop` does. It does not generate update and delete, because the rules live there.
- **Fields.** `string` (255), `text` (10 000), `integer` (bigint, ±10¹²), and `boolean` (default false). All fields are required except booleans. At least one field is not a boolean.
- **It lives in the library.** The project must therefore depend on `dandelion` at the release that has it (0.2.0). It uses only the names that every dandelion project shares (`Platform.*` and `App.*`), so it needs no app name.
- **It refuses to overwrite,** and changes nothing when it refuses. It formats what it writes with the formatter of the project.
- We checked it in three ways. Unit tests of the task cover names, plurals, types, routes, and the refusal. We ran the generated code inside the example: it compiles clean and is formatted, 66 tests pass, and credo passes. An integration test adds two resources to a generated project, with and without the example, and runs compile, format, tests, and credo.

### 11.6 Tracing

2026-10-02. OpenTelemetry has the same shape as the metrics. The libraries already emit `:telemetry` events, and tracing is another reader of them.

- **Example.** `opentelemetry_bandit` (the request), `opentelemetry_phoenix` (the route), `opentelemetry_ecto` (each query), and `opentelemetry_oban` (each job, as a child of what queued it). Four lines in `Platform.Application` set them up. If `OTEL_EXPORTER_OTLP_ENDPOINT` is set, spans go out over OTLP/HTTP. Without it, the exporter is `:none`, so dev and tests do not try to connect. Each node tags its spans with `service.instance.id` (`rel/env.sh.eex`), so a trace says which node did what. The compose file starts Jaeger (`jaegertracing/jaeger`, in memory, UI on :16686).
- **Library.** An app cannot do one thing for itself: carry a trace into a job that library code queued. `Dandelion.Trace.propagate/1` (internal) puts the current `traceparent` into the `meta` of the job in `Dandelion.PubSub.publish/3` and `Dandelion.Queue.Ordered.insert/2`. `opentelemetry_oban` reads it when the job starts. `opentelemetry_api` is an optional dependency. Without OpenTelemetry, nothing changes. We also fixed a problem: `Ordered.insert/2` replaced the `meta` of a job with its key. It now merges.
- **Not in the library.** The SDK, the exporters, and the instrumentations stay the choice of the project, like Phoenix and Ecto themselves.
- **The service keeps every span.** This is fine to try things. Production must sample (`OTEL_TRACES_SAMPLER=parentbased_traceidratio`). The README of the example says so.
- **Proof.** A request sent with our own `traceparent` is one trace in Jaeger under that id. The trace of a caller goes through the load balancer and a node. The trace of an order has the request on one node, its database queries, and the jobs of the subscribers on another node, all in the same trace.
- **It ships in dandelion 0.2.0** with `mix dandelion.gen.domain`.

### 11.7 Harder failures

2026-10-02. These two items cover more of the things that `LIMITS.md` said we did not cover.

- **A node that is cut off from Postgres alone.** The compose file gives Postgres its own network (`db`). The nodes are on it and on `default`, where they find each other. `docker network disconnect` cuts one node off, and it needs no privileges. The proof cuts the leader. The leader stays in the cluster and steps down. Another node becomes the only leader (37 to 53 s in the runs, and never two at once). The cut node cannot run jobs, and its cache serves until the entries expire. On reconnect, it recovers by itself.
- **Postgres killed under load** (SIGKILL, three concurrent order-makers through nginx). Every acknowledged order survives. Every order has exactly one completed job for each subscriber. There were two subscribers when we wrote this, and there are three with the webhook fan-out (§10.15). Publishing inside the transaction buys this property. A negative control (events saved after the transaction, with a gap) fails it.
- **A flapping split** (the last part of the partition proof). Five splits and heals in a row, with orders, payments, and refunds in the meantime. Everything converges.
- **We found a problem when we built it, and we fixed it.** With two networks, `hostname -i` lists the addresses of a container in no fixed order. A node can get the name of its `db` address. It then became unreachable by that name when the `db` network was cut. `rel/env.sh.eex` now takes `NODE_HOST` (a name that resolves only on the cluster network) when `NODE_IP` is not set. The compose file sets it for each node. Real deployments with several networks for each host need the same (`NODE_IP` or `NODE_HOST`).
- **Postgres killed, stopped cleanly, and frozen under load** (`docker pause`: connections open, nothing answers). The freeze found two problems, and we fixed them. `/health` took 32 s to answer the first time. It now gives up after 2 s and answers 503 within a few seconds. A hung or unreachable database gave a 500. A `Plug.Exception` implementation for `DBConnection.ConnectionError` now makes it a 503.
- **Still not covered.** An asymmetric split (A reaches B, but B cannot reach A). The Erlang connection is symmetric, and you cannot drop one direction without privileges. An outage of minutes. A database that is only slow.
