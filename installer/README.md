# dandelion_new

`mix dandelion.new` creates an Elixir service with the layout of a Go service: router, handlers, services, repos, and models. The service has Postgres, tests, background jobs, a cluster of nodes that find each other, a Vue frontend, and a release Dockerfile.

```sh
mix archive.install hex dandelion_new
mix dandelion.new my_app            # --no-example: leave out the orders example
                                    # --no-frontend: leave out the Vue app (no Node)
```

The generated project depends on the [`dandelion`](https://hex.pm/packages/dandelion) library. The library has clustering, the cache, queues, and durable pub/sub. The project keeps the rest in its own repo for you to read and change: the router, the endpoint, the sockets, cron, and `lib/app/<domain>/`. The example prices orders from its `products` table.

- Project, example service, and design: https://github.com/danceinthefake/dandelion
- Go to Elixir phrasebook: https://github.com/danceinthefake/dandelion/tree/main/phrasebook

## License

MIT. See [LICENSE](https://github.com/danceinthefake/dandelion/blob/main/LICENSE).
