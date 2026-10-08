# 14 — A client that guesses, a node that is told to stop

**Claim.** The web layer stays standing when clients misbehave or a node is
stopped:

1. **Rate limiting.** A client that guesses passwords is answered **429** with a
   `retry-after`, while `/health` and the rest of the API keep working.
2. **Graceful shutdown.** A node stopped under load (`docker stop`) first says
   **"draining"** on `/health` (503) while it still serves, then finishes its
   requests and exits **0** — no request is cut off, no order made through the load
   balancer is lost or made twice (clients retry with an `Idempotency-Key`), and
   every order has all its events (one job per subscriber of `order.created`).
3. **Request timeouts.** A client that promises a body and never sends it is
   answered 408 after 10 s; one that connects and says nothing is answered 408 and
   disconnected after about two minutes (two read timeouts); neither holds a node.
   Connections are bounded (4096 per node).

**Code:** `Dandelion.RateLimit` and `Dandelion.Drain` in the library;
`Platform.Web.RateLimit`, the health handler, `Platform.Application.prep_stop/1` and
the Bandit settings in `config/runtime.exs` in the example. DESIGN.md §10.13 says
why each number is what it is.

**What the log shows** ([`run.log`](run.log), with times):

| Step | Because |
|---|---|
| of 20 wrong passwords, **9 are checked (401) and 11 refused (429)**: 3 nodes × 3 a minute | the limit is per node (said in the docs; nothing asks Postgres) |
| the refusal says `retry-after`; `/health` and the catalogue answer 200 meanwhile | logins have their own count, and `/health` is never limited |
| node2, told to stop, answers `/health` **503** while still serving; it is gone after ~5 s with exit code 0 | `Dandelion.Drain`, then the endpoint drains |
| no request was cut off by the stopping node, and every order made through nginx during it was accepted (a few may have been refused by a database stall and retried: see claim 15) | the node kept accepting until the end of the delay, and finished what it had |
| the database has exactly the orders that were accepted, each with one completed job per subscriber | the order and its events are one transaction (claim 06); idempotency keys (claim 16) |
| a promised body that never arrives: `408` after 10 s; a silent client: `408` and closed after ~2 min | `Plug.Parsers` `read_timeout`; Thousand Island `read_timeout` |

**Negative controls** ([`ratelimit.log`](../controls/ratelimit.log),
[`drain.log`](../controls/drain.log)): with the rate-limit plug out of the endpoint,
all 20 guesses are let through and the proof fails; with `Dandelion.Drain.start/1` no
longer called, node2 never answers "draining" and the proof fails.

**Found by running it:** the first version of the silent-client check expected the
connection closed within 75 s; Bandit waits one read timeout for a request and one
more before answering, so it takes two. The docs say "about two".

**Not shown:** the connection limit being reached (it is read back, not filled);
a load balancer that reads `/health` (nginx here does not, so this shows nothing is
lost, not how quickly a balancer moves away); a client behind a shared address; a
spoofed `x-forwarded-for`; a handler that runs for a long time (there is no deadline
around a whole handler, see DESIGN.md §10.13). See [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh reliability` (about 4 minutes); controls:
`ONLY=ratelimit evidence/record.sh controls`, `ONLY=drain …`.
