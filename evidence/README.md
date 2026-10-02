# Evidence

What dandelion claims, and the recording that shows it. Every claim has a
folder with a plain-text `run.log` (what happened, with times), usually a GIF,
and a short page saying what the evidence proves and what it doesn't. Nothing
here is a mock-up: each file is produced by `record.sh` from the code in this
repository, and the commit it came from is at the top of each log.

| # | Claim | Library | Evidence |
|---|---|---|---|
| [01](01-cluster/) | Three copies find each other through Postgres alone; a killed node drops out and rejoins | `Dandelion.Cluster` | log + GIF |
| [02](02-live-feed/) | An order made on one node shows live in a browser on another; presence counts both | (the cluster carries it) | **two-browser GIF** |
| [03](03-killed-node-job/) | A job left by a killed node is run again by another node | `Dandelion.Queue` | log + GIF + control |
| [04](04-ordered-queue/) | Events of one order keep their order while three nodes race; subscribers run once | `Dandelion.Queue.Ordered`, `Dandelion.PubSub` | log + GIF + **control** |
| [05](05-cache/) | A delete on one node clears the cache on all three; a rejoining node starts empty | `Dandelion.Cache` | log + GIF + control |
| [06](06-one-transaction/) | An event and its data are saved together, or not at all | `Dandelion.PubSub` | test output |
| [07](07-database-outage/) | A database outage crashes nothing and splits nothing | `Dandelion.Cluster` | log |
| [12](12-auth/) | One login is accepted by all 3 nodes (signed token, no session); a customer sees only their own orders (404 for others'); prices are admin-only; a tampered token and an anonymous WebSocket are refused | (the app: not in the library) | log + GIF |
| [11](11-tracing/) | One request is one trace in Jaeger, kept under the caller's trace id, and an order's jobs on another node are spans of the same trace | `Dandelion.PubSub`, `Queue.Ordered` (they carry the context) | log + GIF |
| [10](10-metrics/) | `/metrics` is Prometheus text on every node, and the cluster size it reports follows the nodes (3 → 2 → 3 around a kill) | (the app; `Dandelion.Cache` emits the cache events) | log + GIF |
| [09](09-network-partition/) | A network split: jobs and payments still run once, one cron leader; broadcasts lost, a cache goes stale and is emptied on the heal, presence merges | `Dandelion.Cache`, `Queue`, `Queue.Ordered`, `PubSub` | log + GIF + control |
| [08](08-generated-projects/) | Generated projects compile, test and run as a cluster (with everything, without the frontend, without the example) | the generator | test output |

**Negative controls** ([`controls/`](controls/)): four logs where one thing is
broken on purpose and the same proof **fails** where it should — ordering off
(04), cache broadcast off (05), job rescue off (03), cache not emptied on rejoin
(09). A check that can't fail
proves nothing; these show these can.

**Read [LIMITS.md](LIMITS.md)** — what is *not* proven.

## How it was run

Three copies of the example service plus nginx and Postgres, as Docker
containers on one machine (`example/deploy/compose.cluster.yaml`); the checks
are [`example/deploy/cluster-proof.sh`](../example/deploy/cluster-proof.sh),
which you can read and run yourself. The browser evidence drives a real
Chromium with Playwright.

## Re-run

```sh
cd evidence
npm install && npx playwright install chromium     # once (or set PLAYWRIGHT=…/index.mjs)
./record.sh proof       # 01, 03, 04, 05, 07, 10, 11, 12 (~10 min)
./record.sh live        # 02                        (~2 min)
./record.sh partition   # 09                        (~4 min)
./record.sh controls    # the four controls         (~20 min)
./record.sh tests       # 06, 08                    (~10 min; Postgres on :55432)
```

Needs Docker, Node, ffmpeg and python3 (the proof reads Jaeger's JSON with it). The GIFs are small (a few MB at most)
and committed; the logs are the primary evidence, the GIFs are for people who
would rather watch.
