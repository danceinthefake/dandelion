# Changelog

## Unreleased

- `Dandelion.RateLimit`: per-node request limits in memory (`hit/3`, fixed windows).
- `Dandelion.Drain`: `start/1` marks a node as leaving and waits, `draining?/0` for
  the health check; call it from `prep_stop/1`.
- Generated projects gain request and read timeouts, a connection limit, graceful
  shutdown (a draining `/health`, then the endpoint drains before jobs and the
  database stop), and rate limiting on `/api` (`Platform.Web.RateLimit`). Settings:
  `RATE_LIMIT_API`, `RATE_LIMIT_AUTH`, `TRUST_FORWARDED_FOR`, `MAX_CONNECTIONS`,
  `READ_TIMEOUT_MS`, `SHUTDOWN_TIMEOUT_MS`, `DRAIN_DELAY_MS`, `DB_QUERY_TIMEOUT_MS`.
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
