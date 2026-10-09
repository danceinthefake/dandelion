# 24 — A deploy that changes the database

**Claim.** A new version of the app that needs a new column can be rolled out to the three nodes
**under load without a failed request**, if the change is made in the right order (expand, then
roll) — and the proof can tell when it is not:

1. **A second version is built for real**: the example plus
   [`deploy/versions/order-channel.patch`](../../example/deploy/versions/order-channel.patch) (a
   column `orders.channel` with a default, and code that reads and writes it) becomes its own image.
2. **The schema changes while version 1 serves**: the migration runs from the new image, the
   column exists, and **all three nodes still run version 1** and do not notice.
3. **The nodes are replaced one at a time** (the cluster whole again before the next). While one is
   new and two are old, **both versions serve the same traffic over the same table**: of 30 orders
   asking for a channel, 10 were answered by version 2 (with the channel) and 20 by version 1
   (ignoring it); all 201.
4. **Throughout, under load** (fast and slow clients, retries with idempotency keys, every order read
   back with a GET through any node): **no request failed** — about a thousand orders; Docker restarted
   nothing; the database has exactly those orders, each with the column's default; every order has
   all its events done once; and at the end all three nodes use the column.

**Code:** `deploy/versions/order-channel.patch`, `deploy/upgrade-proof.sh`, and the compose file's
`APP_SOURCE` / `APP_VERSION` (build and tag another version). DESIGN.md §10.22 says what "expand, then
roll" means and what it does not cover.

**Negative control** ([`controls/breaking.log`](../controls/breaking.log)): with a migration that
*renames* `customer_email` — a column version 1 still uses — the very first order made in the mixed
state fails (both versions are broken: the second one only knows the old name too) and the proof stops.

**Found by running it:** nginx resolves a name once, at start; a replaced container has a new address,
and traffic kept going to the old one (answered by the others, so nothing failed, but the new node
served nothing). The proof tells nginx to reload after each replacement; a real balancer finds nodes by
itself. The first mixed check ("0 answered by version 2") caught it.

**Not shown:** a migration that locks a big table; rolling back; what jobs carry between versions; a
change of Erlang/Elixir version; see [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh upgrade` (about 3 minutes, builds a second image); control:
`ONLY=breaking evidence/record.sh controls`.
