# 16 — Asking again does not order twice

Claim: `POST /api/orders` with an `Idempotency-Key` header makes one order, however many times the client sends it.

1. 20 identical requests at once, through the load balancer and so on all three nodes. One request gets 201. The other 19 get 200 (`idempotent-replayed: true`) with the same order id. The database has one order. Its events (one job for each subscriber) ran one time each.
2. A retry later, on any node, returns that order again (200).
3. The same key with a different request gets 409 and makes nothing.
4. A request that is cut off asks again with the same key. A slow client or killed nodes can cause the cut while the body still arrives. The result is exactly one order. Another request with the key returns it.

Code: `OrderService.create/3` saves the key with the order in one transaction. The fields are `orders.idempotency_key` and `request_hash`, with a unique index on `(user_id, idempotency_key)`. `OrderHandler.create/2` is the handler. This is not in the library, because it is the rule of the app. See DESIGN.md §10.14.

Negative control ([`controls/idempotency.log`](../controls/idempotency.log)): If the service ignores the header, the 20 requests make 20 orders and the proof fails.

Not shown: the one case that is hard to stage. The node dies in the instant after the commit and before the answer. The design covers it, because the order and its key are one transaction and the retry finds the order. Cases 1 and 2 are the same situation from the side of the client: an answer that the client did not use. But no test kills a node in that exact instant. Keys never expire, because they live with the order.

To run it again, run `evidence/record.sh idempotency`. This takes less than a minute. To run the control, run `ONLY=idempotency evidence/record.sh controls`.
