# dandelion_new

`mix dandelion.new` — creates an Elixir service laid out the way a Go service is
(router → handlers → services → repos → models), with Postgres, tests, a
background job and a release Dockerfile.

```sh
mix archive.install hex dandelion_new
mix dandelion.new my_app            # --no-example to leave out the orders example
```

- Project, example service and design: https://github.com/danceinthefake/dandelion
- Go → Elixir phrasebook: https://github.com/danceinthefake/dandelion/tree/main/phrasebook
