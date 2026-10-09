# Changelog

## Unreleased

- The example sends real email: the order confirmation goes out by SMTP (Swoosh,
  `SMTP_HOST` and friends in `config/runtime.exs`; without a server the message is
  logged, as before). A message is written to `outgoing_emails` under a key before it is
  sent, so a rerun of the job sends nothing twice; a dead mail server opens a circuit
  (`Dandelion.Resilience`) and the messages wait; a refused address ends the job. Admins
  see what was sent at `/api/emails`. New dependencies in the example: `swoosh`,
  `gen_smtp`. New migration `create_outgoing_emails`, a `mail` queue.
- `Dandelion.Search`: full-text search over a table, in Postgres. `Dandelion.Search.Migration`
  adds a `search` column that Postgres keeps up to date itself (a generated `tsvector`, weighted
  by column), a GIN index and a trigram index, and turns on `unaccent` and `pg_trgm`.
  `search/4` takes the words a user typed — every word a prefix, all required, accents and case
  ignored, nothing the user types can reach the query language — and returns ranked rows with a
  total, optional `[[highlighted]]` snippets, and, with `fuzzy:`, a fallback to similar words when
  nothing matched. `tsquery/1` is the input sanitiser on its own.
- The example searches its products (`GET /api/search/products?q=`, public), and admins can
  add, rename and remove products (`POST /api/products`, `PUT /api/products/:sku/details`,
  `DELETE /api/products/:sku`; all audited). New migration `add_product_search` (a
  `description` column and the index).
- `Dandelion.Audit`: `record/4` adds an entry (actor, action, subject, details, and the
  request id) inside the transaction of the change it describes; `list/1` reads back, newest
  first, filtered and paged; `prune/1` is retention. The table (`Dandelion.Audit.Migration`)
  refuses UPDATE, DELETE and TRUNCATE with a trigger. `Dandelion.Flags.put/3` and
  `delete/2` take `in_transaction:` to record with the change.
- The example records its admin and security actions (flags, webhooks, prices, order
  cancels and payments, file deletes, registrations, logins and failed logins) and serves
  them at `/api/audit` (admins). Every project starts `Dandelion.Audit` and gets the table
  (migration `add_audit`).
- `Dandelion.Storage.Local`: uploaded files in a directory — `put/2` (atomic: copied
  to a temporary file, then renamed; returns a random key, the size and the SHA-256),
  `path/2`, `delete/2`, `keys/1`. A key is 128 bits of hex and nothing the client sent,
  and a malformed one is never turned into a path. The directory must be shared by
  all nodes (a mount) in a cluster.
- The example takes uploads (`/api/files`): a customer uploads PNG, JPEG, PDF or text
  (what a file is comes from its bytes, not from the name or the content type the client
  gave), up to 5 MB, and downloads, lists or deletes their own files; an admin sees all.
  Downloads are attachments with `nosniff`. New migration `create_stored_files`, a
  multipart limit in the endpoint, `UPLOADS_DIR` / `UPLOAD_MAX_BYTES`, and a volume in
  the cluster compose file.
- `Dandelion.Flags`: settings and feature flags in a Postgres table
  (`Dandelion.Flags.Migration`), read through `Dandelion.Cache` and cleared on every
  node when one changes: `get/2`, `enabled?/2`, `put/2`, `delete/1`, `all/0`. A node
  that missed the message serves the old value for at most the cache's TTL. If
  Postgres can't be read, the default you gave is returned. New dependency: `jason`.
- The example has an admin API for flags (`/api/flags`) and a flag that pauses new
  orders (`orders.enabled`; 503 with `retry-after` while it is `false`). New
  migration `add_flags` (every project gets it: `Platform.Application` starts
  `Dandelion.Flags`).
- A Grafana dashboard for the service (`deploy/grafana/dashboards/dandelion.json`) with
  Prometheus and Grafana in the cluster compose file (http://localhost:13000, no login to
  look): requests, latency and errors, what is refused (429, 503), calls to other services and
  their circuits, jobs waiting and failing, database and cache, the VM. New metrics for it:
  `dandelion_resilience_calls_total`, `dandelion_resilience_circuit_changes_total`,
  `platform_oban_queue_jobs` (by queue and state), `platform_node_draining`. `/metrics` is not
  redirected to https in production (Prometheus scrapes the nodes directly).
- `Dandelion.Resilience`: `call/3` runs a function with a timeout, retries with
  backoff and jitter, and a per-name circuit breaker (opens after N failures in a
  row, lets one call through after a while). Per node. Telemetry for calls and
  circuit changes.
- `Dandelion.Webhook`: `headers/4` signs a request body (HMAC-SHA256 of
  `id.timestamp.body`, the Standard Webhooks headers), `verify/4` checks one, with a
  timestamp tolerance and several signatures for a secret being rotated.
- The example sends webhooks: admins register URLs (`/api/webhooks`), every
  `order.created` is delivered to each, signed, retried with a growing wait, with a
  circuit per receiver, in its own `webhooks` queue. New dependency in the example:
  `req`. New migration `create_webhook_endpoints`.
- `Dandelion.RateLimit`: per-node request limits in memory (`hit/3`, fixed windows).
- `Dandelion.Drain`: `start/1` marks a node as leaving and waits, `draining?/0` for
  the health check; call it from `prep_stop/1`.
- Generated projects gain request and read timeouts, a connection limit, graceful
  shutdown (a draining `/health`, then the endpoint drains before jobs and the
  database stop), and rate limiting on `/api` (`Platform.Web.RateLimit`). Settings:
  `RATE_LIMIT_API`, `RATE_LIMIT_AUTH`, `TRUST_FORWARDED_FOR`, `MAX_CONNECTIONS`,
  `READ_TIMEOUT_MS`, `SHUTDOWN_TIMEOUT_MS`, `DRAIN_DELAY_MS`, `DB_QUERY_TIMEOUT_MS`.
  - The example's `POST /api/orders` takes an `Idempotency-Key` (a retry returns the
  same order, 200; another request with the same key is 409); a statement the
  database cancelled at the query timeout is a 503, not a 500; nginx streams request
  bodies. New migration `add_idempotency_to_orders`.
  These need the new library modules, so the next release raises the requirement
  (`dandelion ~> 0.2.1`).

## 0.2.0

- Jobs queued by `Dandelion.PubSub.publish/3` and `Dandelion.Queue.Ordered.insert/2`
  carry the current OpenTelemetry trace context (W3C `traceparent`, in the job's
  `meta`), so with `opentelemetry_oban` a job's span is part of the trace of the
  code that queued it, on whichever node runs it. Nothing changes without
  OpenTelemetry. (`opentelemetry_api` is an optional dependency.)
- `Dandelion.Queue.Ordered.insert/2` keeps the job's existing `meta` (it used to
  replace it with the key).
- `mix dandelion.gen.domain DOMAIN RESOURCE field:type …` adds a resource to a
  project's domain in the project's own layout: model, repo, service, handler,
  JSON, migration, tests and the routes.
  The routes go through the project's `:authenticated` pipeline when it has one.

The example and the generator (`dandelion_new` 0.2.0) also gain, in generated
projects: logins with signed tokens and per-user orders, `/metrics`, OpenTelemetry
tracing (Jaeger in the compose file), a network-partition proof, and orders priced
from a products table. Generated projects require `dandelion ~> 0.2.0`.

## 0.1.1

- `Dandelion.Cache.fetch/2` emits `[:dandelion, :cache, :fetch]` (`result: :hit | :miss`)
  for a hit/miss counter.

## 0.1.0

The first release: `Dandelion.Cluster`, `Dandelion.Cache`, `Dandelion.Queue`,
`Dandelion.Queue.Ordered`, `Dandelion.PubSub` and `Dandelion.Migration`,
extracted from the example service.
