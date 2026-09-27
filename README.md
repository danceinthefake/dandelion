# dandelion

**Simplicity with resilience and joy.**

A starting point for Go developers writing their first Elixir service —
start with a single service, grow it into a cluster.

- [`example/`](example) — `shop`, a small JSON API laid out the way a Go
  service is (router → handlers → services → repos → models), with tests,
  a background job and a release Docker image. This is what `mix dandelion.new`
  will generate.
- [`phrasebook/`](phrasebook) — for each Go habit, the Elixir way, pointing
  at the exact file in `example/`.
- [`installer/`](installer) — the `mix dandelion.new` generator (hex package
  `dandelion_new`). Until it's published:
  `cd installer && mix archive.build && mix archive.install dandelion_new-0.1.0.ez`,
  then `mix dandelion.new my_app` anywhere.
- [`DESIGN.md`](DESIGN.md) — why it's built this way.

Name: *dandelion* — **simplicity with resilience and joy.** The plainest
flower there is; it grows through cracks in concrete and comes back every
time you pull it; its seeds scatter on the wind — one flower becoming many,
the way a service starts single and grows into a cluster.
