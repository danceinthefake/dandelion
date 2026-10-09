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
| [13](13-database-failures/) | The leader cut off from Postgres steps down, another leads, jobs run once; Postgres killed under load loses no acknowledged order and no order's events | `Dandelion.PubSub`, `Cache` | log + GIF + control |
| [14](14-reliability/) | Logins are rate-limited per address (429 + retry-after) while the rest works; a node told to stop under load says "draining", finishes its requests, exits 0 and loses no order; a stalled request body and a silent client are cut off | `Dandelion.RateLimit`, `Dandelion.Drain` | log + 2 controls |
| [15](15-rolling-deploy/) | A rolling deploy (node1, node2, node3 stopped and started in turn) under load, with slow clients mid-request: nothing is cut off by a stopping node, no order lost or made twice, one leader after | `Dandelion.Drain` | log + 2 controls |
| [16](16-idempotency/) | The same order request 20 times at once is one order; a retry later, or after the nodes were killed mid-request, is that order again; the same key with another request is 409 | (the app: not in the library) | log + control |
| [17](17-webhooks/) | An admin registers a URL; each order is sent to it once, signed (recomputed outside the app); with the receiver down the circuit opens and deliveries wait; when it returns every event arrives under its own id | `Dandelion.Webhook`, `Dandelion.Resilience` | log + 2 controls |
| [18](18-flags/) | A flag changed through one node is seen by all three at once; a node that never heard the change serves the old value for at most the cache's minute, then reads Postgres | `Dandelion.Flags`, `Dandelion.Cache` | log + control |
| [19](19-uploads/) | A file uploaded through the load balancer is downloaded byte for byte from all three nodes; it is the customer's own; what it is comes from its bytes; ten at once all arrive; nodes killed mid-upload leave no half file and no row | `Dandelion.Storage.Local` | log + 2 controls |
| [20](20-audit/) | Changes made through the load balancer are in one log with who, from/to and the request id; refused changes leave nothing; no secret in it; the table refuses UPDATE, DELETE and TRUNCATE from every node | `Dandelion.Audit` | log + 2 controls |
| [21](21-email/) | Each order's confirmation reaches the mail server exactly once; with it stopped, orders are accepted at once, the circuit opens and the mail waits; when it returns all arrive, once each | (the app: Swoosh + `Dandelion.Resilience`) | log + 2 controls |
| [22](22-search/) | Full-text search over 20 000 products: prefix words, ranking, accents, a typo; nothing a user types breaks it; a rename or delete is searchable at once from all three nodes; the index is used | `Dandelion.Search` | log + 2 controls |
| [23](23-dashboard/) | A Grafana dashboard for the service: every query of it runs against live metrics, and the panels for rate limits, paused orders, a dead mail server (a circuit opens, mail waits) and a draining node have data — with a screenshot | (the app's `/metrics`) | log + screenshot + 2 controls |
| [24](24-upgrade/) | A deploy that changes the database: a second version of the app is built, its migration runs while the first serves, the nodes are replaced one by one under load — no request fails, both versions serve together, every order is read back from any node | (the deploy) | log + control |
| [25](25-accounts/) | A forgotten password: the same answer for any address, a one-time link, the old sessions ended; five wrong passwords lock an address (also one nobody has) on every node and a reset unlocks it; a dead mail server only delays the email; no link is kept anywhere readable | (the app: `Dandelion.Resilience` for the mail) | log + 3 controls |
| [26](26-console/) | The Vue console, driven in a real browser: create an account and confirm it from the emailed link, reset a forgotten password, a locked address; search as you type with a typo and highlights, admin products, the switch that pauses orders, the audit log, webhooks, a 2 MB upload and download; HTML an admin types is shown as text; no page wider than a phone | (the app's console) | log + GIF + screenshots + 2 controls |
| [12](12-auth/) | One login is accepted by all 3 nodes (signed token, no session); a customer sees only their own orders (404 for others'); prices are admin-only; a tampered token and an anonymous WebSocket are refused | (the app: not in the library) | log + GIF |
| [11](11-tracing/) | One request is one trace in Jaeger, kept under the caller's trace id, and an order's jobs on another node are spans of the same trace | `Dandelion.PubSub`, `Queue.Ordered` (they carry the context) | log + GIF |
| [10](10-metrics/) | `/metrics` is Prometheus text on every node, and the cluster size it reports follows the nodes (3 → 2 → 3 around a kill) | (the app; `Dandelion.Cache` emits the cache events) | log + GIF |
| [09](09-network-partition/) | A network split: jobs and payments still run once, one cron leader; broadcasts lost, a cache goes stale and is emptied on the heal, presence merges | `Dandelion.Cache`, `Queue`, `Queue.Ordered`, `PubSub` | log + GIF + control |
| [08](08-generated-projects/) | Generated projects compile, test and run as a cluster (with everything, without the frontend, without the example) | the generator | test output |

**Negative controls** ([`controls/`](controls/)): twenty-eight logs where one thing is
broken on purpose and the same proof **fails** where it should — ordering off
(04), cache broadcast off (05), job rescue off (03), cache not emptied on rejoin
(09), an order's events saved outside its transaction (13), the rate limit out (14), a node that
does not say it is draining (14), the idempotency key ignored (16), a node that stops at once and cuts the requests it serves (15), webhooks signed with the wrong secret (17), a circuit that never opens (17), a flag change that doesn't clear the cache (18), upload types taken on trust (19), nodes that don't share the directory (19), a change that isn't recorded (20), an audit table that can be rewritten (20), a message sent again when its job reruns (21), a failed send forgotten instead of retried (21), user text reaching the query language (22), a missing index (22), a misspelled metric on a panel (23), a circuit change nothing counts (23), a migration that renames a column the running version uses (24), a link that can be used twice (25), an address that is never locked (25), sessions that survive a password change (25), a name put on the page as HTML (26), an orders page that is not hidden (26). A check that can't
fail proves nothing; these show these can.

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
./record.sh partition   # 09                        (~6 min)
./record.sh failures    # 13                        (~6 min)
./record.sh controls    # the five controls         (~25 min)
./record.sh tests       # 06, 08                    (~10 min; Postgres on :55432)
```

Needs Docker, Node, ffmpeg and python3 (the proof reads Jaeger's JSON with it). The GIFs are small (a few MB at most)
and committed; the logs are the primary evidence, the GIFs are for people who
would rather watch.
