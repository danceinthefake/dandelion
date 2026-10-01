# Changelog

## 0.1.1

- `Dandelion.Cache.fetch/2` emits `[:dandelion, :cache, :fetch]` (`result: :hit | :miss`)
  for a hit/miss counter.

## 0.1.0

The first release: `Dandelion.Cluster`, `Dandelion.Cache`, `Dandelion.Queue`,
`Dandelion.Queue.Ordered`, `Dandelion.PubSub` and `Dandelion.Migration`,
extracted from the example service.
