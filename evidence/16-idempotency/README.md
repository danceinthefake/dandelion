# 16 — Asking again does not order twice

**Claim.** `POST /api/orders` with an `Idempotency-Key` header makes **one** order
however many times it is sent:

1. **20 identical requests at once**, through the load balancer and so on all three
   nodes: one is answered 201, 19 are answered 200 (`idempotent-replayed: true`)
   with the same order id; the database has **one** order; its two events ran
   **once** each.
2. **A retry later**, on whichever node, is that order again (200).
3. **The same key with a different request** is **409**, and makes nothing.
4. **A request cut off** — a slow client, the nodes killed while its body was still
   arriving — asks again with the same key and ends up with exactly one order; and
   asking once more returns it.

**Code:** `OrderService.create/3` (the key is saved with the order in one
transaction: `orders.idempotency_key`, `request_hash`, a unique index on
`(user_id, idempotency_key)`), `OrderHandler.create/2`. Not in the library: it is the
app's rule. DESIGN.md §10.14.

**Negative control** ([`controls/idempotency.log`](../controls/idempotency.log)):
with the header ignored, the 20 requests make 20 orders and the proof fails.

**Not shown:** the one case that is hard to stage — the node dying in the instant
after the commit and before the answer. The design covers it (the order and its key
are one transaction, so the retry finds the order), and cases 1 and 2 are the same
situation from the client's side (an answer the client did not use), but no test
kills a node in that exact instant. Keys never expire (they live with the order).

**Re-run:** `evidence/record.sh idempotency` (under a minute); control:
`ONLY=idempotency evidence/record.sh controls`.
