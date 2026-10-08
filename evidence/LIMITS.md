# What this evidence does not prove

Said plainly, so nobody has to find out the hard way.

- **One machine, not real VMs.** The "cluster" is three containers on one
  Docker network. It exercises the real code paths (Erlang distribution over
  TCP, Postgres, a load balancer) but not real network latency, firewalls or
  clock drift. [`example/deploy/vms.md`](../example/deploy/vms.md) is a guide
  for real VMs and has **not** been run on real VMs.
- **The killed node's job row is written by hand** ([03](03-killed-node-job/)).
  No job is slow enough to catch mid-flight, so the proof plants the state a
  crash leaves behind and then kills a node. It shows the cluster gives such a
  job back and runs it; it does not show the exact instant of a crash.
- **Database failures.** [13](13-database-failures/) cuts off the leader (with
  `docker network disconnect`) and, under load, kills, cleanly stops and freezes
  Postgres. Not tested: an outage of minutes (the longest is about 25 s), a cut
  that drops connections one at a time, a database that is merely slow (frozen is
  its extreme), or a failover to a replica (there is no replica).
- **One kind of partition.** [09](09-network-partition/) splits the cluster into
  `node1 | node2 + node3`, both halves keeping their Postgres connection, made
  by giving each side a wrong Erlang cookie for the other. Not tested: a half
  that is *also* cut off from Postgres, an asymmetric split (A reaches B but B
  can't reach A), a split that flaps on and off, or one long enough to outlast
  the cache TTL. The split is simulated at the Erlang layer, not by dropping
  packets, so it doesn't exercise TCP timeouts (`net_ticktime`).
- **Database outages are short:** 15 s in [07](07-database-outage/), up to 25 s in
  [13](13-database-failures/) — not minutes.
- **Tracing is checked against Jaeger only**, with every span kept. Spans are
  standard OTLP, so other backends should work, but none was tried. Sampling
  isn't exercised, and propagation through the ordered queue is unit-tested, not
  run in the cluster proof.
- **The login is a starting point, not a hardened one.** Guessing is slowed by a
  per-address rate limit (14), but there is no account lockout, no password reset or email confirmation, no two-factor, and a token
  can't be revoked before it expires (a day). Passwords use PBKDF2-SHA256 at
  OWASP's 2023 count; nothing here measures whether that is enough for your
  threat model.
- **Reliability of the web layer** ([14](14-reliability/)). The rate limit is
  per node and per address: a cluster of three allows about three times the limit,
  and clients behind one address (a company NAT) share a count. The address is only
  trusted from `x-forwarded-for` when you say so; that was not tested against a
  spoofing client. The connection limit is read back, not filled (nothing opens
  4096 connections here). There is no deadline around a whole handler, only on
  reading the body, an idle connection and each query. The drain was exercised with
  nginx, which does not read `/health`: it shows that nothing is lost, not that a
  health-checking balancer moves away within the delay. A stop longer than
  `stop_grace_period` is still a kill, and so is `SIGKILL` (that case is claim 03/13).
- **Rolling deploy and retries** ([15](15-rolling-deploy/), [16](16-idempotency/)).
  The deploy restarts the same image, not a new version, so a change of schema or
  of the message format between versions is not exercised. Slow clients are
  simulated with `curl --limit-rate` and nginx streaming the body. Several runs
  saw a few requests answered 503 (some also 500 before the mapping was fixed)
  while a node stopped: a Postgres `COMMIT` waited on the disk, and every commit
  that notifies waited behind it. That is a property of Postgres's NOTIFY (and of
  this machine's nearly full disk, which is not proven to be the cause); it
  means a slow disk stalls all writers, and that clients must retry — which the
  proof does, with idempotency keys. Idempotency keys are kept for the life of the
  order, only on `POST /api/orders`, and a key is per customer.
- **Webhooks** ([17](17-webhooks/)). The receiver is nginx on the same Docker network,
  over http, with private addresses allowed (the production defaults refuse both —
  unit-tested, not run in the cluster). A name that points somewhere public when we
  check it and inside our network when we connect (DNS rebinding) is not stopped.
  Secrets are stored in the clear. The circuit is per node: three nodes each learn
  for themselves that a receiver is down, so three times the failed calls before
  all are quiet. Not tested: a receiver that answers slowly rather than not at all,
  one that answers 410, a very large backlog after a long outage.
- **Flags** ([18](18-flags/)). One value for everyone (no targeting or rollouts), no
  history of changes. The "cut off" node is split at the Erlang layer with cookies
  (as in 09), not by dropping packets. The bound on staleness is the cache's TTL, one
  minute (measured 51 to 57 s); a flag read that can't reach Postgres returns the
  default, which is only right if you chose the default for that.
- **Uploads** ([19](19-uploads/)). The directory is a Docker volume on one host: it
  shows that nodes see one directory, not how NFS or a cloud file system behaves under
  load, with locks, or when it is briefly unavailable. A file nothing points at (a
  crash between the file and the row) is not collected automatically. No virus scan, no
  quotas, nothing larger than 5 MB, no resumable upload. Downloads read the file from
  disk each time (no cache, no range requests).
- **Nothing about performance.** No throughput, latency or load numbers. The
  claims are about behaviour, not speed.
- **Live broadcasts and presence are best-effort.** They are fire-and-forget by
  design (like Redis pub/sub); a browser that was offline misses pushes and
  reloads the list on rejoin. What must not be lost goes through Postgres.
- **"At least once", not "exactly once".** Subscribers and jobs can run twice
  (a dead node's job is run again); they must be safe to repeat. The proof
  checks that a healthy run executes each once.
- **Order means arrival at Postgres,** not when the senders' clocks say an event
  happened. If you need the latter, send a sequence number.
- **One application.** The claims are checked on the example service and on
  projects generated from it, not on arbitrary code.
- **The generator is tested from this checkout, the library from hex.** The
  integration tests run the generator's code in this repository and build the
  generated projects against the **published** `dandelion` package. The
  published `dandelion_new` archive itself is not exercised by them (install it
  and run `mix dandelion.new` for that).

If you find a way to break a claim that isn't listed here, that is a bug: open
an issue.
