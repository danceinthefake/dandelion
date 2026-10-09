# 25 — Keeping an account yours

**Claim.** An account can be recovered and protected, with email doing the work and nothing about a
person's account given away:

1. **Confirming an address.** Registering sends one email with a link; using it confirms the address
   (`/api/me` says so); using it again is a 400.
2. **A forgotten password.** Asking gives **the same answer** for an address with an account and one
   without, and only the first is sent an email; asking again within the minute sends no second one. The
   link sets a new password **once**; a password that is too short is refused **without using the link up**;
   a made-up link and an **expired** one are refused. And **the session made under the old password is a
   401 on all three nodes** afterwards.
3. **Guessing.** Five wrong passwords through the load balancer **lock the address**: the right password is
   then a 429 (with `retry-after: 900`) from every node — the count is in Postgres. **An address nobody
   has is locked the same way**, so a lock does not say an account exists. A password reset unlocks.
4. **The mail server goes away.** Asking for a reset still answers 202 at once; the email arrives, exactly
   once, when the mail server is back, and its link works.
5. **Where the links are not.** A link is not in the table of links (only its hash), not in any job's
   arguments, not in the body of a sent email (blanked), not in the audit log — each checked for each link
   the proof used. What happened *is* in the audit log: reset asked (with whether the address was known), reset
   made, address confirmed, address locked.
6. **An order and an unconfirmed address.** With `require_confirmed_email` on, an unconfirmed address's order
   is a 403; confirmed, a 201 (and off, nobody is turned away).

**Code:** `App.Accounts.Services.{TokenService, LoginThrottle, AccountService}`,
`App.Accounts.Workers.SendAccountEmail`, the handlers, and the login token's password fingerprint
(`App.Accounts.Handlers.Token`); `EmailService.send_once_lazy/5`. DESIGN.md §10.23.

**Negative controls** ([`tokenreuse.log`](../controls/tokenreuse.log), [`nolockout.log`](../controls/nolockout.log),
[`norevoke.log`](../controls/norevoke.log)): a link that is not marked used works twice; with no lockout the right
password gets through after the guesses; with no fingerprint check the old session survives a reset — each stops
the proof at its line.

**Found by running it:** the first attempt to look for a link in the audit log used `grep` with a code that began
with `-` and silently checked nothing (`grep -F --` now); and the order-confirmation emails to the same address made
the "exactly one email" count of the gate step wrong, so mail is counted by subject.

**Not shown:** two-factor; a real mail provider's spam filters or link scanners (some "click" every link in an email,
which would use a one-time link up); a stolen token before a password change; the cost of the lockout as a way to
annoy someone. See [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh accounts` (about 1 minute); controls: `ONLY=tokenreuse evidence/record.sh controls`,
`ONLY=nolockout …`, `ONLY=norevoke …`.
