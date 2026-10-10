# 21 — Mail that is sent once, and waits when it cannot be sent

Claim: Each new order sends an email to its customer by SMTP. A mail server that goes away neither loses the mail nor slows the orders.

1. Once. The proof makes 6 orders. The mail server (mailpit) holds exactly one confirmation for each order. It names the order number and the total.
2. The mail server goes away (the proof stops its container). The service accepts 6 more orders immediately, because an order never waits for mail. The circuit for the server opens on a node, so workers stop waiting on it. 6 messages wait. The service wrote them to `outgoing_emails` as `queued`.
3. The mail server comes back. All 6 messages arrive, exactly one time each. The first 6 messages are still one each. Every row is `sent`.
4. The job runs again for two orders that the service already mailed, because jobs are at least once. The service sends nothing. There is still one message for each order.

Code: `App.Notifications.Services.EmailService` (the row, the send through `Dandelion.Resilience`, and the three outcomes), `App.Shop.Workers.SendOrderConfirmation` (retry, snooze, and cancel), and `Platform.Mailer` (Swoosh) in the example. See DESIGN.md §10.19.

Negative controls ([`mailnodedupe.log`](../controls/mailnodedupe.log), [`mailnoretry.log`](../controls/mailnoretry.log)): If the service sends again when a message is already `sent`, the rerun mails the customer twice, and the proof fails. If the service forgets a send that failed for a passing reason, it loses the mail written while the server was down, and the proof fails.

Found by running it: The first run found no mail at all. The SMTP adapter of Swoosh raises an error on a `nil` username, also with `auth: :never`. Every send failed. The system did what it must do. The messages stayed `queued`, the service counted the attempts, and the error was in the row. After we fixed the configuration, the mail arrived. We saw the problem in `last_error` and `attempts` in `/api/emails`.

Not shown:
- A real provider (TLS, login, rate limits, greylisting).
- A 5xx refusal from a real server. A unit test with a fake adapter covers it: the row becomes `failed` and the job is cancelled.
- Bounces.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh email`. This takes about a minute. To run the controls, run `ONLY=mailnodedupe evidence/record.sh controls` and `ONLY=mailnoretry …`.
