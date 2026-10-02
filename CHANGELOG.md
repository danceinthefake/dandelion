# Changelog

## Unreleased

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

## 0.1.1

- `Dandelion.Cache.fetch/2` emits `[:dandelion, :cache, :fetch]` (`result: :hit | :miss`)
  for a hit/miss counter.

## 0.1.0

The first release: `Dandelion.Cluster`, `Dandelion.Cache`, `Dandelion.Queue`,
`Dandelion.Queue.Ordered`, `Dandelion.PubSub` and `Dandelion.Migration`,
extracted from the example service.
