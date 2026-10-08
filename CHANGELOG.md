# Changelog

## Unreleased

- `Dandelion.Flags`: settings and feature flags in a Postgres table
  (`Dandelion.Flags.Migration`), read through `Dandelion.Cache` and cleared on every
  node when one changes: `get/2`, `enabled?/2`, `put/2`, `delete/1`, `all/0`. A node
  that missed the message serves the old value for at most the cache's TTL. If
  Postgres can't be read, the default you gave is returned. New dependency: `jason`.
- The example has an admin API for flags (`/api/flags`) and a flag that pauses new
  orders (`orders.enabled`; 503 with `retry-after` while it is `false`). New
  migration `add_flags` (every project gets it: `Platform.Application` starts
  `Dandelion.Flags`).
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
