# 17 — Telling another service what happened, reliably

Claim: An admin registers a URL. The service sends every new order to the URL as a signed webhook. The sending survives when the receiver goes away.

1. The service delivers each order one time, signed. The proof makes 5 orders, and the receiver gets 5 requests. Each request has `webhook-id`, `webhook-timestamp`, and `webhook-signature`. The proof recomputes the signature outside the app with `openssl`, the secret that the service showed when it created the endpoint, the id, the timestamp, and the raw body. The signature matches. The list does not show the secret afterwards. Only an admin can register an endpoint.
2. The receiver goes away (the proof stops its container) while the proof makes 6 more orders. The circuit for the receiver opens on a node, so callers stop waiting on it. 6 deliveries wait for a retry. The service does not lose them and does not give up.
3. The receiver comes back. All 6 deliveries arrive, each under its own `webhook-id` and signed. A retry is the same event and not a new event.

Code: `Dandelion.Webhook` (sign and verify) and `Dandelion.Resilience` in the library, and `App.Webhooks.*` in the example. See DESIGN.md §10.15.

Negative controls ([`webhooksig.log`](../controls/webhooksig.log), [`nobreaker.log`](../controls/nobreaker.log)): If the service signs with the wrong secret, the recomputed signature does not match and the proof fails. If the circuit never opens, no node opens one and the proof fails.

The [`run.log`](run.log) shows the node that opened the circuit, the number of deliveries that wait, and the time from the return of the receiver until everything arrived. That time is about a minute, because the wait before a retry doubles. The proof sets the first wait to 1 s.

Not shown:
- A receiver that is slow and not gone.
- A 410 answer.
- A long outage and a large backlog.
- The production URL rules (https only, no private addresses) end to end.
- The circuit works for each node, so each node opens its own circuit.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh webhooks`. This takes about 2 minutes. To run the controls, run `ONLY=webhooksig evidence/record.sh controls` and `ONLY=nobreaker …`.
