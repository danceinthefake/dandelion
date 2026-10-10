# 06 — An event and its data are saved together, or not at all

Claim: If you call `Dandelion.PubSub.publish/3` inside a transaction, it saves the event jobs with the data. Both commit, or both roll back. An external broker cannot give you this without an outbox table and a relay.

Library code: `Dandelion.PubSub`, on Oban.

This claim is a property of one database transaction. The evidence is therefore a test and not a recording. The [`run.log`](run.log) has the test output. In the library, the events roll back with the transaction of the caller. In the example, an invalid order publishes nothing, and a rolled-back order leaves no job.

Not shown: a crash between "saved" and "published". It cannot happen, because both are the same commit.

To run it again, run `evidence/record.sh tests`.
