# 28 — Files in a bucket

Claim: The uploaded files can live in an S3-compatible bucket and not in a shared directory, and the service behaves in the same way. The bytes arrive intact from every node. A delete really deletes. A bucket that is down gives a polite 503, and the service does not lose a file or make a half file. We tried two servers that are not Amazon: SeaweedFS and Garage. The proof starts each one and restarts the nodes to use it. The log is [`run.log`](run.log).

For each server:

1. The proof uploads 1.5 MB through the load balancer. The bucket holds it (the adapter lists the key), and the uploads volume has no file at all.
2. Six downloads, which all three nodes answer, have the checksum that the file had at upload.
3. Another customer gets 404. A program that is renamed `.png` is refused (400) because of what its bytes are.
4. A delete removes the row and the object, and every node answers 404.
5. The bucket is stopped. A download and an upload both answer 503 with `Retry-After` (not 500). The upload that failed left no row. After the bucket is back, the file is intact.
6. A node that is replaced from scratch serves the file too. Nothing was on its disk.

Negative controls ([`s3nodelete.log`](../controls/s3nodelete.log), [`s3unsigned.log`](../controls/s3unsigned.log)): A delete that never reaches the bucket leaves the object there, and step 4 stops the proof. Requests without a signature get a refusal from the server, and step 1 stops the proof.

Code: `lib/dandelion/storage/s3.ex` (the adapter, with Signature V4 through `Req`), `example/lib/app/files/`, `example/deploy/s3-proof.sh`, and `example/deploy/s3/` (the configuration of the two servers). Six unit tests of the adapter (`test/dandelion/storage_s3_test.exs`) run against a bucket that a process keeps, with no server. See DESIGN.md §10.26.

Not shown:
- Amazon S3, Google Cloud Storage, or any paid service. We have no cloud budget, so their interoperability endpoints are untested here.
- Virtual-hosted-style URLs.
- Multipart upload.
- Files over 5 MB.
- A bucket that is slow and not down.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh s3`. This takes about 4 minutes and pulls two images. To run the control, run `ONLY=s3nodelete evidence/record.sh controls`.
