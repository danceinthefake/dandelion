# 07 — A database outage crashes nothing

**Claim.** When Postgres goes away, no node restarts, the cluster does not
split, and `/health` says 503 so the load balancer knows; when Postgres is
back, `/health` returns to 200 without anyone touching the nodes.

**Library code:** `Dandelion.Cluster.Postgres` (both of its connections
reconnect by themselves; `libcluster_postgres` crash-looped here and took the
app down).

[`run.log`](run.log) shows, with times: Postgres stopped for 15 seconds; the
sum of Docker restart counters unchanged; still three nodes; `/health` 503;
then Postgres started and `/health` 200 again.

**Not shown:** a long outage, or one that drops connections one by one
(see [LIMITS](../LIMITS.md)).

**Re-run:** `evidence/record.sh proof`
