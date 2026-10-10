# 20 — Who did what

Claim: The service records the changes of an admin and the actions that touch money or sign-in in one log. Nobody can rewrite the log.

1. One log from three nodes. Seven admin changes go through the load balancer, and three different nodes answer them. The changes are a flag that is set twice and unset, a webhook that is registered and deleted, and a price that is changed twice. A customer registers, fails a login, logs in, orders, and cancels. All of this is in one log under the right actor: `user:1` is the admin, `user:3` is the customer, and `anonymous` is the failed login.
2. What changed. The price entry says from 100 to 123. An entry has the request id of the request that made it. This is the same `x-request-id` that the response had. You can therefore match the entry to the logs and the trace.
3. Nothing extra. A refused change adds no entry. Examples are 422 for a negative price, 404 for an unknown product, and 400 for a bad flag key. The secret of the webhook and the passwords are in no entry.
4. No rewriting. From every node, the database refuses an `UPDATE`, a `DELETE`, and a `TRUNCATE` of the table (`dandelion_audit is append-only`). The entries are still there.

Code: `Dandelion.Audit` and its migration in the library (the table, the trigger, and `record/4` inside the transaction of the caller). In the example: `App.Audit.*` (the admin read API) and the `record` calls in the other domains. See DESIGN.md §10.18.

Negative controls ([`noaudit.log`](../controls/noaudit.log), [`mutable.log`](../controls/mutable.log)): If the service does not record a flag change, the proof fails at "the admin's flag, webhook and price changes are there". If a trigger lets everything through, the database accepts an UPDATE, and the proof fails at "the log cannot be rewritten".

The tests of the library show atomicity: an entry exists exactly when its change exists. We do not kill a node for this. An entry that a transaction makes disappears when the transaction rolls back. A failing `in_transaction:` hook undoes a flag change. See [LIMITS.md](../LIMITS.md) for what the log is not. It is not tamper-proof against a person who owns the database, and it does not record reads.

To run it again, run `evidence/record.sh audit`. This takes less than a minute. To run the controls, run `ONLY=noaudit evidence/record.sh controls` and `ONLY=mutable …`.
