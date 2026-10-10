# 27 — Backup, and rebuilding from nothing

Claim: You can back up a cluster that is busy with orders while it works. You can destroy the cluster completely (the containers, Postgres, and the uploads volume) and rebuild it from the backup alone. What comes back is whole, true to what the cluster made, and working. The log is [`run.log`](run.log).

1. A backup of a cluster that never stopped. Four clients make orders without a pause. `backup.sh` dumps the database in one `pg_dump` snapshot and then copies the files. More than a thousand orders were made during the backup.
2. The machine is lost. The proof runs `docker compose down -v` and makes sure that the uploads volume is gone.
3. `restore.sh` alone rebuilds the cluster. Three nodes are a cluster again in about ten seconds.
4. A snapshot and not a smear. Every restored order has all its queued events and its items, although the backup was taken in the middle of the flow. Nothing is invented. Every restored order is, byte for byte, an order that the cluster made. The cluster holds more orders. The backup does not have the orders made after the snapshot. This is the purpose of a snapshot.
5. What people had. The password of the customer signs in. A word of the description finds the product, because the search index is a generated column and came back with the table. The flag has its value. The audit log has the entries and still refuses `UPDATE`. The 1.5 MB file downloads from all three nodes with the checksum that it had at upload.
6. Work in flight. The events that were queued or running at the time of the snapshot all complete after the restore, one time for each subscriber and each order. The idempotency key of an order made before the backup still returns that order (200, replayed). The id of a new order is after the restored ids.

Negative controls ([`smeared.log`](../controls/smeared.log), [`nofiles.log`](../controls/nofiles.log)): A database that is backed up table by table, a second apart, returns orders with no events, and step 4 stops the proof. A backup without the files returns file rows with nothing to download, and step 5 stops the proof.

Code: `example/deploy/backup.sh`, `restore.sh`, and `backup-proof.sh`. See DESIGN.md §10.25.

Not shown: point-in-time recovery, a large database, copies on another machine or encrypted copies, and a schedule (see [LIMITS.md](../LIMITS.md)).

To run it again, run `evidence/record.sh backup`. This takes about 2 minutes. To run the control, run `ONLY=smeared evidence/record.sh controls`.
