# 27 — Backup, and rebuilding from nothing

**Claim.** A cluster that is busy making orders can be backed up while it works, destroyed completely
(containers, Postgres, the uploads volume), and rebuilt from the backup alone; what comes back is whole,
true to what the cluster had made, and working. The log is [`run.log`](run.log).

1. **A backup of a cluster that never stopped.** Four clients make orders without pause; `backup.sh`
   dumps the database in one `pg_dump` snapshot, then copies the files. Over a thousand orders were made
   during it.
2. **The machine is lost:** `docker compose down -v`; the uploads volume is checked to be gone.
3. **Rebuilt by `restore.sh` alone:** three nodes are a cluster again in about ten seconds.
4. **A snapshot, not a smear:** every restored order has all of its queued events and its items, though the
   backup was taken mid-flow. **Nothing invented:** every restored order is, byte for byte, one the cluster
   had made (it holds more: the orders made after the snapshot are not in the backup, which is the point of a
   snapshot).
5. **What people had:** the customer's password signs in; the product is found by a word of its description
   (the search index is a generated column, so it came back with the table); the flag has its value; the audit
   log has the entries and still refuses `UPDATE`; the 1.5 MB file downloads with the checksum it was uploaded
   with, from all three nodes.
6. **Work in flight:** the events that were queued or running when the snapshot was taken all complete after
   the restore, each subscriber once per order; the idempotency key of an order made before the backup still
   returns that order (200, replayed); a new order's id is after the restored ones.

**Negative controls** ([`smeared.log`](../controls/smeared.log), [`nofiles.log`](../controls/nofiles.log)):
the database backed up table by table, a second apart, returns orders with no events (step 4 stops the proof);
a backup without the files returns file rows with nothing to download (step 5 stops it).

**Code:** `example/deploy/backup.sh`, `restore.sh`, `backup-proof.sh`. DESIGN.md §10.25.

**Not shown:** point-in-time recovery, a large database, off-machine or encrypted copies, a schedule
(see [LIMITS.md](../LIMITS.md)).

**Re-run:** `evidence/record.sh backup` (about 2 minutes); controls: `ONLY=smeared evidence/record.sh controls`.
