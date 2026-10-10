# 28 — Files in a bucket

**Claim.** The uploaded files can live in an S3-compatible bucket instead of a shared directory, and the
service behaves the same: the bytes arrive intact from every node, deleting really deletes, and a bucket that
is down is a polite 503, not a lost file or a half-made one. Tried against two servers that are not Amazon's —
**SeaweedFS** and **Garage** — each started by the proof, the nodes restarted to use them. The log is
[`run.log`](run.log).

For each server:

1. **1.5 MB uploaded** through the load balancer: the bucket holds it (the adapter lists the key) and the
   uploads volume has no file at all.
2. **Six downloads**, answered by all three nodes, have the checksum it was uploaded with.
3. **Another customer gets 404**; a program renamed `.png` is refused (400) because of what its bytes are.
4. **Deleted:** the row and the object are gone, and every node answers 404.
5. **Bucket stopped:** a download and an upload both answer **503 with `Retry-After`** (not 500), and the upload
   that failed left no row. **Bucket back:** the file is intact.
6. **A node replaced from scratch** serves the file too: nothing was on its disk.

**Negative controls** ([`s3nodelete.log`](../controls/s3nodelete.log), [`s3unsigned.log`](../controls/s3unsigned.log)):
a delete that never reaches the bucket leaves the object there (step 4 stops the proof); requests sent without
a signature are refused by the server (step 1 stops it).

**Code:** `lib/dandelion/storage/s3.ex` (the adapter, Signature V4 through `Req`), `example/lib/app/files/`,
`example/deploy/s3-proof.sh`, `example/deploy/s3/` (the two servers' settings). Six unit tests of the adapter
(`test/dandelion/storage_s3_test.exs`) run against a bucket kept in a process, with no server. DESIGN.md §10.26.

**Not shown:** Amazon S3, Google Cloud Storage or any paid service (no cloud budget: their interoperability
endpoints are untested here), virtual-hosted-style URLs, multipart upload, files over 5 MB, a bucket that is slow
rather than down (see [LIMITS.md](../LIMITS.md)).

**Re-run:** `evidence/record.sh s3` (about 4 minutes; pulls two images); controls: `ONLY=s3nodelete evidence/record.sh controls`.
