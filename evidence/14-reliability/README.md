# 14 — A client that guesses, a node that is told to stop

Claim: The web layer stays up when clients misbehave or a node stops.

1. Rate limiting. A client that guesses passwords gets 429 with a `retry-after`. `/health` and the rest of the API keep working.
2. Graceful shutdown. A node that stops under load (`docker stop`) first says "draining" on `/health` (503) while it still serves. Then it finishes its requests and exits with code 0. No request is cut off. No order through the load balancer is lost or made twice, because clients retry with an `Idempotency-Key`. Every order has all its events (one job for each subscriber of `order.created`).
3. Request timeouts. A client that promises a body and never sends it gets 408 after 10 s. A client that connects and says nothing gets 408 and is disconnected after about two minutes (two read timeouts). Neither client holds a node. Each node bounds its connections (4096).

Code: `Dandelion.RateLimit` and `Dandelion.Drain` in the library. In the example: `Platform.Web.RateLimit`, the health handler, `Platform.Application.prep_stop/1`, and the Bandit configuration in `config/runtime.exs`. DESIGN.md §10.13 explains each number.

The [`run.log`](run.log) shows these events, with times:

| Step | Because |
|---|---|
| Of 20 wrong passwords, 9 are tested (401) and 11 are refused (429). The reason is 3 nodes × 3 a minute. | The limit works for each node. The docs say so, and nothing asks Postgres. |
| The refusal has `retry-after`. `/health` and the catalog answer 200 in the meantime. | Logins have their own count, and the service never limits `/health`. |
| node2 gets the stop signal and answers `/health` 503 while it still serves. It is gone after about 5 s with exit code 0. | `Dandelion.Drain`, and then the endpoint drains. |
| The stopping node cut off no request. Every order made through nginx during the stop was accepted. A database stall can refuse a few orders, and the client retries them (see claim 15). | The node accepted requests until the end of the delay and finished what it had. |
| The database has exactly the orders that the service accepted. Each has one completed job for each subscriber. | The order and its events are one transaction (claim 06), and idempotency keys (claim 16). |
| A promised body that never arrives gets `408` after 10 s. A silent client gets `408` and is closed after about 2 min. | `Plug.Parsers` `read_timeout` and Thousand Island `read_timeout`. |

Negative controls ([`ratelimit.log`](../controls/ratelimit.log), [`drain.log`](../controls/drain.log)): If the rate-limit plug is out of the endpoint, all 20 guesses pass and the proof fails. If nothing calls `Dandelion.Drain.start/1`, node2 never answers "draining" and the proof fails.

Found by running it: The first version of the check for the silent client expected the connection to close within 75 s. Bandit waits one read timeout for a request and one more before it answers. The time is therefore two read timeouts. The docs say "about two".

Not shown:
- That a client reaches the connection limit. The proof reads the limit back and does not fill it.
- A load balancer that reads `/health`. nginx here does not. The proof shows that nothing is lost. It does not show how fast a balancer moves away.
- A client behind a shared address.
- A spoofed `x-forwarded-for`.
- A handler that runs for a long time. There is no deadline around a whole handler (see DESIGN.md §10.13).

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh reliability`. This takes about 4 minutes. To run the controls, run `ONLY=ratelimit evidence/record.sh controls` and `ONLY=drain …`.
