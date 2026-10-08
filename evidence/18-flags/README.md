# 18 — A setting changed while the app runs, seen by every node

**Claim.** `Dandelion.Flags` changes a setting on a running cluster, and every node
sees it — with one honest exception, bounded:

1. **Pausing orders.** 9 orders, spread over all 3 nodes, are accepted. An admin sets
   `orders.enabled` to `false` **through one node**; the next 12 orders, answered by
   all 3 nodes, are all refused (**503, `retry-after: 30`**). Reading orders is not
   paused. Set back to `true`, 9 orders are accepted on every node.
2. **A node that cannot hear the others** (split off at the Erlang layer; it still
   reaches Postgres) **does not hear the change**: it serves the value it has — and
   after at most the cache's minute it **reads the table** and sees the new one
   (51 s and 57 s in the recorded runs). Memory makes it fast; Postgres decides.

**Code:** `Dandelion.Flags` in the library (a table, read through `Dandelion.Cache`,
cleared on every node by `put/2`); `App.Settings.*` and the `orders.enabled` check in
`OrderService.create/3` in the example. DESIGN.md §10.16.

**Negative control** ([`controls/noinvalidate.log`](../controls/noinvalidate.log)): if
`put/2` does not clear the cached copy, all 12 orders are still accepted after the
pause and the proof fails.

**Found by running it:** setting the flag through the load balancer could hand the
request to the very node being tested, which then cleared its own cache and made it
look as if the message had arrived. The proof sets it directly on node1.

**Not shown:** a flag read while Postgres is unreachable (unit-tested: the default is
returned), values other than booleans in the cluster, targeting. See
[LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh flags` (about 2 minutes); control:
`ONLY=noinvalidate evidence/record.sh controls`.
