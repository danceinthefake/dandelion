# 15 — A rolling deploy under load

**Claim.** The nodes can be stopped and started one at a time — a deploy — while
orders are being made, and no client notices more than a retry:

- each node **stops itself** (`docker stop`: drains, finishes its requests, exit
  code 0, never killed) and **rejoins**: the cluster is whole again before the next
  one is touched;
- **no request is cut off by a stopping node** — clients that are slow to send their
  body (two of the four workers take about 1.5 s per order) are mid-request when a
  node is told to stop, and still get their answer;
- clients that are told 503 (see below) ask again with the same `Idempotency-Key`:
  **every order is accepted, none lost, none made twice**, each has both its events;
- Docker restarted nothing; exactly one cron leader afterwards.

**Code:** `Dandelion.Drain` and the shutdown order (claim 14), idempotency keys
(claim 16). **Proof:** [`deploy/rolling-proof.sh`](../../example/deploy/rolling-proof.sh).

**Negative control** ([`controls/rollingcut.log`](../controls/rollingcut.log)): with
`DRAIN_DELAY_MS=0` and `SHUTDOWN_TIMEOUT_MS=0` — a node that stops at once — the
slow clients' requests are cut (502) and the proof fails.

**What the log shows** ([`run.log`](run.log)): the three stops with their times, the
number of orders (hundreds), how many needed a retry, and how many of those refusals
were the database stalling. **Read that line:** on the machine this was recorded on,
stopping a container made one Postgres `COMMIT` wait on the disk for several
seconds, and every commit that sends a `NOTIFY` waits behind it, so a few requests
were answered 503 and retried. The proof tells those apart from the one thing a
deploy can cause (a connection cut or a bad gateway, which must be zero) and does
not hide them. DESIGN.md §10.14 and [LIMITS.md](../LIMITS.md) say what is and isn't
known about it.

**Found by running it:** nginx buffered request bodies, so a slow client never
occupied a node and the control could not fail; `proxy_request_buffering off` fixed
that, and the first version of the proof's check of the requests' statuses mixed up
a stalled database with a stopped node.

**Not shown:** a new version replacing the old (the same image restarts); WebSocket
clients across the deploy (they reconnect; claim 02 shows the feed, not a deploy);
nodes stopped two at a time.

**Re-run:** `evidence/record.sh rolling` (about 2 minutes); control:
`ONLY=rollingcut evidence/record.sh controls`.
