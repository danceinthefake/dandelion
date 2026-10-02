# dandelion

**Simplicity with resilience and joy.**

A whole cloud in one app — web server, workers, queue, pub/sub, cache, cron,
a live frontend — as one Elixir release, laid out the way a Go service is. Run
one copy on one VM; run 3 or 10 and they join into one system. Only the load
balancer, Postgres and file storage stay outside.

This package is the **library** half: the cloud pieces that are the same in
every dandelion project. The other half, the generator (`dandelion_new`),
writes a project that uses them.

```sh
mix archive.install hex dandelion_new
mix dandelion.new my_app          # a service that already depends on this library
```

New here? [**From zero to a three-node cluster**](https://github.com/danceinthefake/dandelion/blob/main/TUTORIAL.md) — ten minutes, step by step.

## Proof

Every claim is recorded, not just written down — [`evidence/`](https://github.com/danceinthefake/dandelion/tree/main/evidence)
has a log, a GIF and a page for each, and [what is *not* proven](https://github.com/danceinthefake/dandelion/blob/main/evidence/LIMITS.md).

**An order made on one node appears in a browser on another** (two browsers,
two different nodes, real Chromium):

![two browsers on two different nodes; an order made in one shows in the other](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/02-live-feed/live-feed.gif)

**A job left by a killed node is run again by another**, and payment events
keep their order while three nodes race for them — with negative controls that
show the same checks **fail** when the feature is switched off:

![the cluster proof](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/04-ordered-queue/ordered-queue.gif)

## The library

Thin over [Oban](https://hex.pm/packages/oban), [Cachex](https://hex.pm/packages/cachex),
`Phoenix.PubSub` and [libcluster](https://hex.pm/packages/libcluster) — not a
new API on top of them. You need Postgres and a `Phoenix.PubSub`.

```elixir
def deps do
  [{:dandelion, "~> 0.1.1"}]
end
```

| Module | What it is | Replaces |
|---|---|---|
| `Dandelion.Cluster` | nodes find each other through Postgres (`NOTIFY`) | Consul, Kubernetes DNS |
| `Dandelion.Cache` | per-node memory cache, cleared on every node | Redis as a cache |
| `Dandelion.Queue` | the Oban setup: queues, lifeline, pruner, crontab | Cloud Tasks, Cloud Scheduler |
| `Dandelion.Queue.Ordered` | order per key, across nodes | SQS FIFO, Kafka partition keys |
| `Dandelion.PubSub` | a topic → one Oban job per subscriber, in your transaction | Google Pub/Sub, Kafka topics |
| `Dandelion.Migration` | the database index the ordered queue needs | — |

```elixir
# application.ex
children = [
  MyApp.Repo,
  {Dandelion.Cluster, otp_app: :my_app, repo: MyApp.Repo},
  {Phoenix.PubSub, name: MyApp.Broadcast},
  {Dandelion.Cache, pubsub: MyApp.Broadcast},
  {Oban, Dandelion.Queue.config(otp_app: :my_app, repo: MyApp.Repo, crontab: MyApp.Cron.schedule())}
]

# a migration, after Oban's
def up, do: Dandelion.Migration.up()
def down, do: Dandelion.Migration.down()

# in your code
Dandelion.Cache.fetch({:product, sku}, fn -> Repo.get(Product, sku) end)
Dandelion.Cache.delete({:product, sku})                    # after the commit, on every node

Repo.transact(fn ->
  {:ok, order} = insert_order(params)
  Dandelion.PubSub.publish(%{"order.created" => [SendConfirmation]}, "order.created", %{"id" => order.id})
  {:ok, order}                                              # saved together, or not at all
end)

Dandelion.Queue.Ordered.insert(MyWorker.new(args), "order:42")   # then, in perform/1:
# with :ok <- Dandelion.Queue.Ordered.turn(job), do: ...
```

`mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer`
adds a resource to a project in its own layout (model, repo, service, handler,
migration, tests and routes), so a second feature starts from the same shape as
the first.

Each module's docs say what it promises and what it doesn't. The rules behind
them: **Postgres decides; memory only makes things faster.** Anything that must
survive a crash or happen exactly once goes through the database; the cache and
live broadcasts may be lost or briefly stale.

Nodes trust each other fully — anyone holding the Erlang cookie can run code on
every node. Keep them on a private network.

## The rest of the project

On [GitHub](https://github.com/danceinthefake/dandelion):

- [`example/`](https://github.com/danceinthefake/dandelion/tree/main/example) —
  a service using all of it: `lib/platform/` (what every app runs on) and
  `lib/app/shop/` (one domain laid out as handlers → services → repos →
  models), a Vue + blessing-ui frontend, a release Docker image.
  [`deploy/`](https://github.com/danceinthefake/dandelion/tree/main/example/deploy)
  runs it as 3 nodes and **proves** the claims (an order made on one node shows
  up on another; a killed node's jobs are run again by the others; payment
  events keep their order while three nodes race for them).
- [`phrasebook/`](https://github.com/danceinthefake/dandelion/tree/main/phrasebook) —
  for each Go habit, the Elixir way: 12 pages on the service, 5 on the rest of
  the cloud.
- [`DESIGN.md`](https://github.com/danceinthefake/dandelion/blob/main/DESIGN.md) —
  why it's built this way.

Name: *dandelion* — the plainest flower there is; it grows through cracks in
concrete and comes back every time you pull it; its seeds scatter on the wind —
one flower becoming many, the way a service starts single and grows into a
cluster.

## License

MIT — see [LICENSE](https://github.com/danceinthefake/dandelion/blob/main/LICENSE).
