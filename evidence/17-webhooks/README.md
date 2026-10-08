# 17 — Telling another service what happened, reliably

**Claim.** An admin registers a URL; every new order is sent to it as a signed
webhook, and the sending survives the receiver going away:

1. **Each order is delivered once, signed.** 5 orders, 5 requests at the receiver, each
   with `webhook-id`, `webhook-timestamp` and `webhook-signature`; the proof
   **recomputes the signature outside the app** (`openssl`, the secret shown when the
   endpoint was created, the id, the timestamp and the raw body) and it matches. The
   secret is not in the list afterwards; registering needs an admin.
2. **The receiver goes away** (its container is stopped) while 6 more orders are made:
   **the circuit for it opens** on a node (callers stop waiting on it), and **6 deliveries
   are waiting to be retried** — not lost, not given up.
3. **It comes back**: all 6 arrive, each under its own `webhook-id`, signed — a retry is
   the same event, not a new one.

**Code:** `Dandelion.Webhook` (sign, verify) and `Dandelion.Resilience` in the library;
`App.Webhooks.*` in the example. DESIGN.md §10.15.

**Negative controls** ([`webhooksig.log`](../controls/webhooksig.log),
[`nobreaker.log`](../controls/nobreaker.log)): signed with the wrong secret, the recomputed
signature doesn't match and the proof fails; with a circuit that never opens, no node opens
one and the proof fails.

**What the log shows** ([`run.log`](run.log)): the node that opened the circuit, the number
of deliveries waiting, and how long after the receiver returned everything had arrived
(about a minute: the wait before a retry doubles; the proof sets the first one to 1 s).

**Not shown:** a receiver that is slow rather than gone; a 410; a long outage and a large
backlog; the production URL rules (https only, no private addresses) end to end; the
circuit being per node means each node opens its own. See [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh webhooks` (about 2 minutes); controls:
`ONLY=webhooksig evidence/record.sh controls`, `ONLY=nobreaker …`.
