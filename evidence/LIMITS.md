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
- **No true network partition.** What is tested: a node killed with `SIGKILL`,
  a node disconnected and reconnected, Postgres stopped for 15 seconds. A
  partition where both halves keep running and can't see each other is argued
  in DESIGN §10.3 but not reproduced.
- **A short database outage only** (15 seconds), not a long one, and not one
  that drops connections one at a time.
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
