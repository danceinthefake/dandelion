# 18 — A setting changed while the app runs, seen by every node

Claim: `Dandelion.Flags` changes a setting on a running cluster, and every node sees the change. One exception exists, and it has a bound.

1. Pausing orders. The proof accepts 9 orders that spread over all 3 nodes. An admin sets `orders.enabled` to `false` through one node. The next 12 orders, which all 3 nodes answer, are all refused (503, `retry-after: 30`). Reading orders is not paused. The admin sets the flag back to `true`, and every node accepts 9 orders.
2. A node that cannot hear the others does not hear the change. The proof splits this node off at the Erlang layer. It still reaches Postgres. The node serves the value that it has. After one minute at most (the cache time), it reads the table and sees the new value. The recorded runs took 51 s and 57 s. Memory makes the node fast, and Postgres decides.

Code: `Dandelion.Flags` in the library keeps a table, reads it through `Dandelion.Cache`, and clears the cache on every node with `put/2`. In the example, `App.Settings.*` and the `orders.enabled` check in `OrderService.create/3` use it. See DESIGN.md §10.16.

Negative control ([`controls/noinvalidate.log`](../controls/noinvalidate.log)): If `put/2` does not clear the cached copy, the service still accepts all 12 orders after the pause, and the proof fails.

Found by running it: When the proof set the flag through the load balancer, the request could go to the node under test. That node then cleared its own cache, and it looked as if the message had arrived. The proof now sets the flag directly on node1.

Not shown:
- A flag read while Postgres is unreachable. A unit test covers this: the function returns the default.
- Values other than booleans in the cluster.
- Targeting.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh flags`. This takes about 2 minutes. To run the control, run `ONLY=noinvalidate evidence/record.sh controls`.
