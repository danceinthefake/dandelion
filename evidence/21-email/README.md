# 21 — Mail that is sent once, and waits when it can't be

**Claim.** Each new order emails its customer by SMTP, and a mail server that goes away
neither loses the mail nor slows the orders:

1. **Once.** 6 orders; the mail server (mailpit) holds **exactly one** confirmation for each,
   naming the order number and the total.
2. **The mail server goes away** (its container is stopped): **6 more orders are accepted
   immediately** (an order never waits for mail); **the circuit for the server opens** on a
   node, so workers stop waiting on it; **6 messages are waiting, written down** in
   `outgoing_emails` as `queued`.
3. **It comes back**: all 6 arrive, **exactly once each**; the first 6 are still one each;
   every row is `sent`.
4. **The job runs again** (jobs are at least once) for two orders already mailed: **nothing is
   sent**, still one each.

**Code:** `App.Notifications.Services.EmailService` (the row, the send through
`Dandelion.Resilience`, the three outcomes), `App.Shop.Workers.SendOrderConfirmation` (retry,
snooze, cancel), `Platform.Mailer` (Swoosh) in the example. DESIGN.md §10.19.

**Negative controls** ([`mailnodedupe.log`](../controls/mailnodedupe.log),
[`mailnoretry.log`](../controls/mailnoretry.log)): sending again when a message is already `sent`
makes the rerun mail the customer twice and the proof fails; forgetting a send that failed for a
passing reason loses the mail written while the server was down and the proof fails.

**Found by running it:** the first run found no mail at all. Swoosh's SMTP adapter raises on a
`nil` username even with `auth: :never`; every send failed, and the system did what it should —
the messages stayed `queued`, attempts were counted, the error was recorded on the row — until
the config was fixed (`last_error` and `attempts` in `/api/emails` are how it was seen).

**Not shown:** a real provider (TLS, login, rate limits, greylisting); a 5xx refusal from a real
server (unit-tested with a fake adapter: the row becomes `failed` and the job is cancelled);
bounces. See [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh email` (about a minute); controls:
`ONLY=mailnodedupe evidence/record.sh controls`, `ONLY=mailnoretry …`.
