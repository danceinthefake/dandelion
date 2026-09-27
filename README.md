# dandelion

**Simplicity with resilience and joy.**

A whole cloud in one app — web server, workers, queue, pub/sub, cache,
cron — as one Elixir release, laid out the way a Go service is. Run one copy
on one VM; run 3 or 10 and they join into one system. Every seed carries
the whole plant. (The cluster pieces are being built: see
[DESIGN.md §10](DESIGN.md).)

- [`example/`](example) — `acme`, a JSON API: `lib/platform/` (what every
  app runs on) and `lib/app/shop/` (one domain, laid out as handlers →
  services → repos → models), with tests, a background job and a release
  Docker image. This is what `mix dandelion.new` generates.
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

## License

MIT — see [LICENSE](LICENSE).
