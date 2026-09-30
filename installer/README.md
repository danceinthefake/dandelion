# dandelion_new

`mix dandelion.new` — creates an Elixir service laid out the way a Go service is
(router → handlers → services → repos → models), with Postgres, tests, background
jobs, a cluster of nodes that find each other, a Vue frontend and a release
Dockerfile.

```sh
mix archive.install hex dandelion_new
mix dandelion.new my_app            # --no-example: leave out the orders example
                                    # --no-frontend: leave out the Vue app (no Node)
```

The generated project depends on the [`dandelion`](https://hex.pm/packages/dandelion)
library (clustering, cache, queues, durable pub/sub) and keeps the rest — router,
endpoint, sockets, cron, `lib/app/<domain>/` — in its own repo, for you to read
and change. Orders in the example are priced from its `products` table.

- Project, example service and design: https://github.com/danceinthefake/dandelion
- Go → Elixir phrasebook: https://github.com/danceinthefake/dandelion/tree/main/phrasebook

## License

MIT — see [LICENSE](LICENSE).
