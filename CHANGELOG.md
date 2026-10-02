# Changelog

## Unreleased

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
