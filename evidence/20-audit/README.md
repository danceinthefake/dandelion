# 20 — Who did what

**Claim.** The changes an admin makes, and the actions that touch money or sign-in, are
recorded in one log, and the log cannot be rewritten:

1. **One log, from three nodes.** Seven admin changes (a flag set twice and unset, a webhook
   registered and deleted, a price changed twice) go through the load balancer and are answered
   by **three different nodes**; a customer registers, fails a login, logs in, orders and cancels.
   All of it is in one log, under the right actor (`user:1` the admin, `user:3` the customer,
   `anonymous` for the failed login).
2. **What changed.** The price entry says **from 100 to 123**. An entry carries the **request id**
   of the request that made it — the same `x-request-id` the response had, so it can be matched
   to the logs and the trace.
3. **Nothing extra.** A refused change (422 negative price, 404 unknown product, 400 bad flag key)
   adds **no entry**. The webhook's secret and the passwords are in **no entry**.
4. **No rewriting.** From **every node**, an `UPDATE`, a `DELETE` and a `TRUNCATE` of the table are
   refused by the database (`dandelion_audit is append-only`), and the entries are still there.

**Code:** `Dandelion.Audit` and its migration in the library (the table, the trigger, `record/4`
inside the caller's transaction); `App.Audit.*` (the admin read API) and the `record` calls in the
other domains in the example. DESIGN.md §10.18.

**Negative controls** ([`noaudit.log`](../controls/noaudit.log), [`mutable.log`](../controls/mutable.log)):
with a flag change not recorded, the proof fails at "the admin's flag, webhook and price changes are
there"; with a trigger that lets everything through, an UPDATE is accepted and the proof fails at "the
log cannot be rewritten".

**Atomicity** (an entry exists exactly when its change does) is shown by the library's tests rather
than by killing a node: an entry made in a transaction that rolls back is gone with it, and a failing
`in_transaction:` hook undoes a flag change. See [LIMITS.md](../LIMITS.md) for what the log is not
(not tamper-proof against someone who owns the database; reads are not recorded).

**Re-run:** `evidence/record.sh audit` (under a minute); controls:
`ONLY=noaudit evidence/record.sh controls`, `ONLY=mutable …`.
