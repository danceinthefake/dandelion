# Evidence

This directory has the claims of dandelion and the recordings that show them. Each claim has a folder. The folder has a plain-text `run.log` that shows what happened, with times. It usually has a GIF. It also has a short page that says what the evidence proves and what it does not prove. Nothing here is a mock-up. The script `record.sh` produces each file from the code in this repository. The first lines of each log name the commit that it came from.

| # | Claim | Library | Evidence |
|---|---|---|---|
| [01](01-cluster/) | Three copies find each other through Postgres alone. A killed node drops out and joins again. | `Dandelion.Cluster` | log + GIF |
| [02](02-live-feed/) | An order made on one node shows live in a browser on another node. Presence counts both browsers. | (the cluster carries it) | two-browser GIF |
| [03](03-killed-node-job/) | Another node runs again a job that a killed node left. | `Dandelion.Queue` | log + GIF + control |
| [04](04-ordered-queue/) | The events of one order keep their order while three nodes race. Each subscriber runs one time. | `Dandelion.Queue.Ordered`, `Dandelion.PubSub` | log + GIF + control |
| [05](05-cache/) | A delete on one node clears the cache on all three nodes. A node that joins again starts empty. | `Dandelion.Cache` | log + GIF + control |
| [06](06-one-transaction/) | An event and its data are saved together or not at all. | `Dandelion.PubSub` | test output |
| [07](07-database-outage/) | A database outage crashes nothing and splits nothing. | `Dandelion.Cluster` | log |
| [13](13-database-failures/) | The leader that Postgres cannot reach steps down. Another node leads, and jobs run one time. If Postgres is killed under load, the cluster loses no acknowledged order and no events of an order. | `Dandelion.PubSub`, `Cache` | log + GIF + control |
| [14](14-reliability/) | The service limits logins for each address (429 and retry-after) while the rest works. A node that gets the stop signal under load says "draining", finishes its requests, exits with code 0, and loses no order. The service cuts off a stalled request body and a silent client. | `Dandelion.RateLimit`, `Dandelion.Drain` | log + 2 controls |
| [15](15-rolling-deploy/) | A rolling deploy (node1, node2, and node3 stop and start in turn) under load, with slow clients in the middle of a request. A stopping node cuts off nothing. No order is lost or made twice. One leader remains after the deploy. | `Dandelion.Drain` | log + 2 controls |
| [16](16-idempotency/) | The same order request 20 times at once makes one order. A later retry returns that order again. This is true also after the nodes were killed in the middle of the request. The same key with another request gives 409. | (the app, not the library) | log + control |
| [17](17-webhooks/) | An admin registers a URL. The service sends each order to the URL one time, signed. A check outside the app recomputes the signature. If the receiver is down, the circuit opens and the deliveries wait. When the receiver returns, every event arrives under its own id. | `Dandelion.Webhook`, `Dandelion.Resilience` | log + 2 controls |
| [18](18-flags/) | A flag that you change through one node is visible on all three nodes at once. A node that never heard of the change serves the old value for one minute at most (the cache time). Then it reads Postgres. | `Dandelion.Flags`, `Dandelion.Cache` | log + control |
| [19](19-uploads/) | A file that you upload through the load balancer downloads byte for byte from all three nodes. It belongs to the customer. Its bytes decide what it is. Ten uploads at once all arrive. Nodes that stop in the middle of an upload leave no half file and no row. | `Dandelion.Storage.Local` | log + 2 controls |
| [20](20-audit/) | Changes through the load balancer are in one log with the actor, the old and new values, and the request id. Refused changes leave nothing. No secret is in the log. The table refuses UPDATE, DELETE, and TRUNCATE from every node. | `Dandelion.Audit` | log + 2 controls |
| [21](21-email/) | The mail server gets the confirmation email of each order exactly one time. If the mail server is stopped, the service accepts orders at once, the circuit opens, and the mail waits. When the server returns, all mail arrives one time each. | (the app: Swoosh and `Dandelion.Resilience`) | log + 2 controls |
| [22](22-search/) | Full-text search over 20 000 products supports prefix words, ranking, accents, and a typo. Nothing that a user types breaks it. A rename or delete is searchable at once from all three nodes. The query uses the index. | `Dandelion.Search` | log + 2 controls |
| [23](23-dashboard/) | A Grafana dashboard for the service. Each query of the dashboard runs against live metrics. The panels for rate limits, paused orders, a dead mail server (a circuit opens and mail waits), and a draining node have data. The claim has a screenshot. | (`/metrics` of the app) | log + screenshot + 2 controls |
| [24](24-upgrade/) | A deploy that changes the database. The proof builds a second version of the app. Its migration runs while the first version serves. The nodes are replaced one at a time under load. No request fails. Both versions serve together. Any node reads back every order. | (the deploy) | log + control |
| [25](25-accounts/) | A forgotten password gives the same answer for any address. The link works one time, and the old sessions end. Five wrong passwords lock an address on every node, also an address that nobody has. A reset unlocks it. A dead mail server only delays the email. No link is kept anywhere in a readable form. | (the app: `Dandelion.Resilience` for the mail) | log + 3 controls |
| [28](28-s3/) | Uploaded files in an S3-compatible bucket, first SeaweedFS and then Garage. The bytes are in the bucket and not in the uploads volume. All three nodes give the same checksum. A delete removes the object. A stopped bucket gives 503 with `Retry-After` and no row. A replaced node serves the file. | `Dandelion.Storage.S3` | log + 2 controls |
| [27](27-backup/) | The proof backs up a cluster that is busy with orders (one snapshot, then the files). It destroys the cluster (the containers, Postgres, and the uploads volume) and rebuilds it from the backup alone. Each restored order has its events and is byte for byte the order that the cluster made. Passwords, search, flags, the audit log (still append-only), and files are back. The events in flight finish, and none runs twice. An old idempotency key still answers. New orders get ids after the old ids. | `backup.sh`, `restore.sh` | log + 2 controls |
| [26](26-console/) | A real browser drives the Vue console. It creates an account and confirms it from the emailed link. It resets a forgotten password and meets a locked address. It searches as you type, with a typo and highlights. It adds admin products, uses the switch that pauses orders, and reads the audit log and the webhooks. It uploads and downloads a 2 MB file. The page shows HTML that an admin types as text. No page is wider than a phone. | (the console of the app) | log + GIF + screenshots + 2 controls |
| [12](12-auth/) | All 3 nodes accept one login (a signed token, no session). A customer sees only their own orders and gets 404 for the orders of others. Only admins change prices. The service refuses a tampered token and an anonymous WebSocket. | (the app, not the library) | log + GIF |
| [11](11-tracing/) | One request is one trace in Jaeger under the trace id of the caller. The jobs of an order on another node are spans of the same trace. | `Dandelion.PubSub`, `Queue.Ordered` (they carry the context) | log + GIF |
| [10](10-metrics/) | `/metrics` is Prometheus text on every node. The cluster size that it reports follows the nodes (3, then 2, then 3 around a kill). | (the app, and `Dandelion.Cache` emits the cache events) | log + GIF |
| [09](09-network-partition/) | A network split. Jobs and payments still run one time, and one node runs cron. The broadcasts are lost. A cache goes stale. It empties after the network heals. Presence merges. | `Dandelion.Cache`, `Queue`, `Queue.Ordered`, `PubSub` | log + GIF + control |
| [08](08-generated-projects/) | Generated projects compile, test, and run as a cluster. This is true with everything, without the frontend, and without the example. | the generator | test output |

## Negative controls

The directory [`controls/`](controls/) has thirty-two logs. In each log we break one thing on purpose, and the same proof fails where it must fail. A check that cannot fail proves nothing. These logs show that our checks can fail. We broke these things:

- Ordering off (04).
- Cache broadcast off (05).
- Job rescue off (03).
- A cache that a returning node does not empty (09).
- The events of an order saved outside its transaction (13).
- The rate limit removed (14).
- A node that does not say that it drains (14).
- The idempotency key ignored (16).
- A node that stops at once and cuts the requests that it serves (15).
- Webhooks signed with the wrong secret (17).
- A circuit that never opens (17).
- A flag change that does not clear the cache (18).
- Upload types accepted on trust (19).
- Nodes that do not share the directory (19).
- A change that is not recorded (20).
- An audit table that can be rewritten (20).
- A message that goes out again after its job reruns (21).
- A failed send that the service forgets instead of retrying (21).
- User text that reaches the query language (22).
- A missing index (22).
- A misspelled metric on a panel (23).
- A circuit change that nothing counts (23).
- A migration that renames a column that the running version uses (24).
- A link that you can use twice (25).
- An address that is never locked (25).
- Sessions that survive a password change (25).
- A name that the page shows as HTML (26).
- An orders page that is not hidden (26).
- A backup taken table by table (27).
- A backup without the files (27).
- A delete that never reaches the bucket (28).
- Requests that are not signed (28).

Read [LIMITS.md](LIMITS.md). It lists what we did not prove.

## How we ran the proofs

We ran three copies of the example service, nginx, and Postgres as Docker containers on one machine (`example/deploy/compose.cluster.yaml`). The proof script is [`example/deploy/cluster-proof.sh`](../example/deploy/cluster-proof.sh). You can read it and run it yourself. The browser evidence drives a real Chromium with Playwright.

## Run the proofs again

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

You need Docker, Node, ffmpeg, and python3. The proof reads the JSON of Jaeger with python3. The GIFs are small (a few MB at most) and we commit them. The logs are the primary evidence. The GIFs are for people who prefer to watch.
