# 15 — A rolling deploy under load

Claim: You can stop and start the nodes one at a time, as in a deploy, while clients make orders. Clients notice nothing more than a retry.

- Each node stops itself (`docker stop`). It drains, finishes its requests, exits with code 0, and is never killed. Then it joins again. The cluster is whole again before the next node is touched.
- A stopping node cuts off no request. Some clients are slow to send their body: two of the four workers take about 1.5 s for each order. These clients are in the middle of a request when a node gets the stop signal. They still get their answer.
- A client that gets 503 (see below) asks again with the same `Idempotency-Key`. The service accepts every order. It loses none and makes none twice. Each order has all its events (one job for each subscriber).
- Docker restarts nothing. Exactly one cron leader exists afterwards.

Code: `Dandelion.Drain` and the shutdown order (claim 14), and idempotency keys (claim 16). Proof: [`deploy/rolling-proof.sh`](../../example/deploy/rolling-proof.sh).

Negative control ([`controls/rollingcut.log`](../controls/rollingcut.log)): With `DRAIN_DELAY_MS=0` and `SHUTDOWN_TIMEOUT_MS=0`, a node stops at once. The requests of the slow clients are cut (502), and the proof fails.

The [`run.log`](run.log) shows the three stops with their times. It shows the number of orders (hundreds), how many needed a retry, and how many of those refusals came from a database stall. Read that line. On the machine that recorded this proof, stopping a container made one Postgres `COMMIT` wait on the disk for several seconds. Every commit that sends a `NOTIFY` waits behind it. A few requests therefore got 503 and the client retried them. The proof separates these cases from the one thing that a deploy can cause: a cut connection or a bad gateway. That count must be zero. The proof does not hide the 503 answers. DESIGN.md §10.14 and [LIMITS.md](../LIMITS.md) say what we know and do not know about this.

Found by running it: nginx buffered the request bodies. A slow client therefore never occupied a node, and the control could not fail. `proxy_request_buffering off` fixed this. The first version of the status check in the proof also mixed up a stalled database and a stopped node.

Not shown:
- A new version that replaces the old version. The same image restarts. ([Claim 24](../24-upgrade/) covers the new version.)
- WebSocket clients across the deploy. They reconnect. Claim 02 shows the feed and not a deploy.
- Nodes that stop two at a time.

To run it again, run `evidence/record.sh rolling`. This takes about 2 minutes. To run the control, run `ONLY=rollingcut evidence/record.sh controls`.
