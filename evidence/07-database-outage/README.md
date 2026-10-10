# 07 — A database outage crashes nothing

Claim: If Postgres goes away, no node restarts and the cluster does not split. `/health` answers 503, so the load balancer knows. When Postgres is back, `/health` returns to 200. Nobody touches the nodes.

Library code: `Dandelion.Cluster.Postgres`. Both of its connections reconnect by themselves. The `libcluster_postgres` package crashed in a loop here and took the app down.

The [`run.log`](run.log) shows these events, with times. Postgres stops for 15 seconds. The sum of the Docker restart counters does not change. Three nodes remain. `/health` answers 503. Then Postgres starts, and `/health` answers 200 again.

Not shown: a long outage, and an outage that drops connections one by one (see [LIMITS](../LIMITS.md)).

To run it again, run `evidence/record.sh proof`.
