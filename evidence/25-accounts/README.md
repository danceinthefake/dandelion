# 25 — Keeping an account yours

Claim: A person can recover and protect an account. Email does the work, and the service gives away nothing about the account of a person.

1. Confirming an address. Registration sends one email with a link. If the person uses the link, the address is confirmed (`/api/me` says so). If the person uses the link again, the answer is 400.
2. A forgotten password. A request gives the same answer for an address with an account and for an address without an account. Only the first address gets an email. A second request within the minute sends no second email. The link sets a new password one time. A password that is too short is refused, and the link is not used up. A made-up link and an expired link are refused. The session that the old password made gets 401 on all three nodes afterwards.
3. Guessing. Five wrong passwords through the load balancer lock the address. The right password then gets 429 (with `retry-after: 900`) from every node, because Postgres keeps the count. An address that nobody has is locked in the same way, so a lock does not say that an account exists. A password reset unlocks the address.
4. The mail server goes away. A request for a reset still answers 202 at once. The email arrives exactly one time when the mail server is back, and its link works.
5. Where the links are not. A link is not in the table of links (only its hash is). It is not in the arguments of any job. It is not in the body of a sent email, because the service blanks it. It is not in the audit log. The proof checks this for each link that it used. The audit log does have what happened: reset asked (with the fact whether the address was known), reset made, address confirmed, and address locked.
6. An order and an unconfirmed address. If `require_confirmed_email` is on, the order of an unconfirmed address gets 403. After the person confirms the address, the order gets 201. If the option is off, the service turns nobody away.

Code: `App.Accounts.Services.{TokenService, LoginThrottle, AccountService}`, `App.Accounts.Workers.SendAccountEmail`, the handlers, and the password fingerprint of the login token (`App.Accounts.Handlers.Token`). Also `EmailService.send_once_lazy/5`. See DESIGN.md §10.23.

Negative controls ([`tokenreuse.log`](../controls/tokenreuse.log), [`nolockout.log`](../controls/nolockout.log), [`norevoke.log`](../controls/norevoke.log)): A link that the service does not mark as used works twice. With no lockout, the right password gets through after the guesses. With no fingerprint check, the old session survives a reset. Each one stops the proof at its line.

Found by running it: The first attempt to look for a link in the audit log used `grep` with a code that began with `-`. It silently checked nothing. The proof now uses `grep -F --`. The order-confirmation emails to the same address made the "exactly one email" count of the gate step wrong. The proof now counts mail by subject.

Not shown:
- Two-factor login.
- The spam filters or link scanners of a real mail provider. Some of them "click" every link in an email, which would use a one-time link up.
- A stolen token before a password change.
- The cost of the lockout as a way to annoy a person.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh accounts`. This takes about 1 minute. To run the controls, run `ONLY=tokenreuse evidence/record.sh controls`, `ONLY=nolockout …`, and `ONLY=norevoke …`.
