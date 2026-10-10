# 24 — A deploy that changes the database

Claim: You can roll out a new version of the app that needs a new column to the three nodes under load without a failed request. You must make the change in the right order: expand, then roll. The proof can tell when the order is wrong.

1. The proof builds a second version for real. The example plus [`deploy/versions/order-channel.patch`](../../example/deploy/versions/order-channel.patch) becomes its own image. The patch adds a column `orders.channel` with a default and code that reads and writes it.
2. The schema changes while version 1 serves. The migration runs from the new image, and the column exists. All three nodes still run version 1 and do not notice the change.
3. The nodes are replaced one at a time. The cluster is whole again before the next replacement. While one node is new and two nodes are old, both versions serve the same traffic over the same table. 30 orders ask for a channel. Version 2 answered 10 of them, with the channel. Version 1 answered 20, and it ignored the channel. All of them got 201.
4. Throughout, under load, no request failed. The load has fast and slow clients, retries with idempotency keys, and a GET through any node that reads back every order. About a thousand orders were made. Docker restarted nothing. The database has exactly those orders, and each has the default of the column. Every order has all its events done one time. At the end, all three nodes use the column.

Code: `deploy/versions/order-channel.patch`, `deploy/upgrade-proof.sh`, and `APP_SOURCE` and `APP_VERSION` in the compose file (they build and tag another version). DESIGN.md §10.22 says what "expand, then roll" means and what it does not cover.

Negative control ([`controls/breaking.log`](../controls/breaking.log)): A migration renames `customer_email`, a column that version 1 still uses. The first order in the mixed state fails and the proof stops. Both versions are broken, because the second version also knows only the old name.

Found by running it: nginx resolves a name one time, at start. A replaced container has a new address. Traffic kept going to the old address. The other nodes answered, so nothing failed, but the new node served nothing. The proof now tells nginx to reload after each replacement. A real balancer finds nodes by itself. The first mixed check ("0 answered by version 2") caught the problem.

Not shown:
- A migration that locks a big table.
- A rollback.
- What jobs carry between versions.
- A change of the Erlang or Elixir version.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh upgrade`. This takes about 3 minutes and builds a second image. To run the control, run `ONLY=breaking evidence/record.sh controls`.
