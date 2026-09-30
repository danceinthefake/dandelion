# dandelion

**Simplicity with resilience and joy.**

A whole cloud in one app — web server, workers, queue, pub/sub, cache,
cron, a live frontend — as one Elixir release, laid out the way a Go
service is. Run one copy on one VM; run 3 or 10 and they join into one
system. Every seed carries the whole plant. Only the load balancer, Postgres
and file storage stay outside. ([DESIGN.md §10](DESIGN.md); a proof script
checks the cluster claims on three local nodes.)

- [`lib/`](lib) — the `dandelion` library (hex `dandelion`, being extracted:
  clustering first): the cloud pieces that are the same in every project.
  See [DESIGN.md §11](DESIGN.md).
- [`example/`](example) — `acme`: `lib/platform/` (what every app runs on:
  cluster, queue, cron, durable and live pub/sub, cache, presence) and
  `lib/app/shop/` (one domain, laid out as handlers → services → repos →
  models), a Vue + blessing-ui frontend, tests and a release Docker image.
  [`deploy/`](example/deploy) runs it as 3 nodes and proves it; `deploy/vms.md`
  is the guide for real VMs. This is what `mix dandelion.new` generates.
- [`phrasebook/`](phrasebook) — for each Go habit, the Elixir way, pointing
  at the exact file in `example/`: 12 pages on the service, 5 on the rest of
  the cloud (where is my Redis, queues and topics, cron, live updates, many
  nodes).
- [`installer/`](installer) — the `mix dandelion.new` generator (hex package
  `dandelion_new`). Until it's published:
  `cd installer && mix archive.build && mix archive.install dandelion_new-0.1.0.ez`,
  then `mix dandelion.new my_app` anywhere (`--no-frontend`, `--no-example`).
- [`DESIGN.md`](DESIGN.md) — why it's built this way.

Name: *dandelion* — **simplicity with resilience and joy.** The plainest
flower there is; it grows through cracks in concrete and comes back every
time you pull it; its seeds scatter on the wind — one flower becoming many,
the way a service starts single and grows into a cluster.

## License

MIT — see [LICENSE](LICENSE).
