# dandelion

**Simplicity with resilience and joy.**

A whole cloud in one app. It has a web server, workers, a queue, pub/sub, a cache, cron, and a live frontend. It is one Elixir release, and its layout is like the layout of a Go service. Run one copy on one VM. If you run 3 or 10 copies, they join into one system. Only the load balancer, Postgres, and file storage stay outside.

This package is the library half. It has the cloud parts that are the same in every dandelion project. The generator (`dandelion_new`) is the other half. It writes a project that uses these parts.

```sh
mix archive.install hex dandelion_new
mix dandelion.new my_app          # a service that depends on this library
```

New here? Read [From zero to a three-node cluster](https://github.com/danceinthefake/dandelion/blob/main/TUTORIAL.md). It takes ten minutes and has one step at a time.

## Proof

We record each claim and do not only write it down. The [`evidence/`](https://github.com/danceinthefake/dandelion/tree/main/evidence) directory has a log, a GIF, and a page for each claim. The list of [what we did not prove](https://github.com/danceinthefake/dandelion/blob/main/evidence/LIMITS.md) is also there.

An order made on one node appears in a browser on another node. The proof uses two browsers, two different nodes, and real Chromium:

![two browsers on two different nodes, and an order made in one shows in the other](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/02-live-feed/live-feed.gif)

Another node runs again a job that a killed node left. Payment events keep their order while three nodes race for them. Negative controls switch the feature off. The same checks then fail:

![the cluster proof](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/04-ordered-queue/ordered-queue.gif)

## The library

The library is a thin layer over [Oban](https://hex.pm/packages/oban), [Cachex](https://hex.pm/packages/cachex), `Phoenix.PubSub`, and [libcluster](https://hex.pm/packages/libcluster). It does not add a new API on top of them. You need Postgres and a `Phoenix.PubSub`.

```elixir
def deps do
  [{:dandelion, "~> 0.2.0"}]
end
```

| Module | What it is | Replaces |
|---|---|---|
| `Dandelion.Cluster` | nodes find each other through Postgres (`NOTIFY`) | Consul, Kubernetes DNS |
| `Dandelion.Cache` | a memory cache on each node, cleared on every node | Redis as a cache |
| `Dandelion.Queue` | the Oban setup: queues, lifeline, pruner, and crontab | Cloud Tasks, Cloud Scheduler |
| `Dandelion.Queue.Ordered` | order for each key, across nodes | SQS FIFO, Kafka partition keys |
| `Dandelion.PubSub` | a topic gives one Oban job for each subscriber, in your transaction | Google Pub/Sub, Kafka topics |
| `Dandelion.Storage.Local` | uploaded files in a directory, written atomically, found by a random key | an S3 or Cloud Storage bucket (a shared directory here) |
| `Dandelion.Search` | full-text search in Postgres with prefix words, ranking, snippets, and a typo fallback. Any input is safe | Elasticsearch or Algolia for a catalog-sized corpus |
| `Dandelion.Audit` | who did what, added in the transaction of the change. The table is append-only | CloudTrail or a hand-written audit table |
| `Dandelion.Flags` | configuration and feature flags that you change while the app runs. They are the same on every node | LaunchDarkly, Unleash, Consul KV |
| `Dandelion.Resilience` | a call to another service with a timeout, retries, and a circuit breaker | `gobreaker` + a retry loop + `context.WithTimeout` |
| `Dandelion.Webhook` | sign what you send to a URL and make sure that what you receive is valid (Standard Webhooks headers) | Stripe-Signature or X-Hub-Signature code |
| `Dandelion.RateLimit` | request limits for each node, in memory (fixed windows) | a Redis `INCR` with an expiry |
| `Dandelion.Drain` | tell the load balancer that a node leaves, then stop | a Kubernetes `preStop` hook + readiness probe |
| `Dandelion.Migration` | the database index that the ordered queue needs | None |

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

The command `mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer` adds a resource to a project. It makes the model, repo, service, handler, migration, tests, and routes. A second feature then starts from the same shape as the first feature.

The docs of each module say what the module promises and what it does not promise. One rule is behind all of them: Postgres decides, and memory only makes things faster. Anything that must survive a crash or happen exactly once goes through the database. The cache and the live broadcasts can be lost or be stale for a short time.

Nodes trust each other fully. A person who has the Erlang cookie can run code on every node. Keep the nodes on a private network.

## The rest of the project

On [GitHub](https://github.com/danceinthefake/dandelion):

- [`example/`](https://github.com/danceinthefake/dandelion/tree/main/example) is a service that uses all the parts. `lib/platform/` has what every app runs on. `lib/app/shop/` has one domain in the layout handlers, services, repos, models. The service also has a Vue and blessing-ui frontend and a release Docker image. The [`deploy/`](https://github.com/danceinthefake/dandelion/tree/main/example/deploy) directory runs the service as 3 nodes and proves the claims. An order made on one node shows on another node. The other nodes run again the jobs of a killed node. Payment events keep their order while three nodes race for them.
- [`phrasebook/`](https://github.com/danceinthefake/dandelion/tree/main/phrasebook) shows the Elixir way for each Go habit. It has 12 pages on the service and 5 pages on the rest of the cloud.
- [`DESIGN.md`](https://github.com/danceinthefake/dandelion/blob/main/DESIGN.md) explains why we built it this way.

The name is dandelion because the dandelion is the plainest flower. It grows through cracks in concrete. It comes back each time you pull it. Its seeds scatter on the wind, and one flower becomes many. A service starts as one copy and grows into a cluster in the same way.

## License

MIT. See [LICENSE](https://github.com/danceinthefake/dandelion/blob/main/LICENSE).
