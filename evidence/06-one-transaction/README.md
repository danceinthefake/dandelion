# 06 — An event and its data are saved together, or not at all

**Claim.** `Dandelion.PubSub.publish/3` called inside a transaction saves the
event jobs with the data: commit both, or roll both back. This is what an
external broker can't give without an outbox table and a relay.

**Library code:** `Dandelion.PubSub`, on Oban.

This claim is a property of one database transaction, so the evidence is a
test, not a recording: [`run.log`](run.log) has the test output, in the
library (events are rolled back with the caller's transaction) and in the
example (an invalid order publishes nothing; a rolled-back order leaves no
job).

**Not shown:** a crash between "saved" and "published" — it can't happen,
because both are the same commit.

**Re-run:** `evidence/record.sh tests`
