# 19 — Files on a directory the nodes share

**Claim.** A file uploaded through the load balancer lives on a directory every node
can see, and the app treats it as the user's own, safely:

1. **Upload and download.** A 200 KB file is uploaded through nginx; the stored checksum
   is the one `sha256sum` computes here. **12 downloads, answered by all 3 nodes, are each
   byte for byte the file** — the node that took the upload is not the one that serves it.
   A download is an `attachment` with `nosniff`.
2. **Whose it is.** Another customer gets **404**, no login gets **401**.
3. **What it is comes from its bytes.** A script named `picture.png`, typed `image/png`, is
   kept as **`text/plain`**; an executable with the same name is **refused (400)**. 5.5 MB
   and 7.5 MB are **413** (the first by the service, the second by the endpoint's limit),
   and refused uploads leave nothing in the directory.
4. **Ten at once** arrive as ten files with ten ids and ten keys, contents intact.
5. **Deleting** answers 404 from every node and removes the bytes.
6. **All three nodes killed while a file is still arriving** (a slow client): no half file
   in the directory and no row in the table; the same upload works afterwards.

**Code:** `Dandelion.Storage.Local` in the library (atomic write, random keys, no path from
a name); `App.Files.*` in the example. DESIGN.md §10.17.

**Negative controls** ([`uploadtype.log`](../controls/uploadtype.log),
[`unshared.log`](../controls/unshared.log)): with the type taken on trust, the script is
stored and served as a PNG and the proof fails; with each node on its own directory, a
download from another node is not the file and the proof fails.

**Found by running it:** the proof first expected a script to be refused — but a script
*is* valid text, and it is kept as text, which is the right answer; and a kill 2 seconds
into a 5-second upload sometimes found the upload already done, so the proof now fails if
the slow upload finished before the kill.

**Not shown:** a real shared file system (NFS, EFS) — this is one Docker volume; files with
no row (not collected); virus scanning; range requests; quotas. See
[LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh uploads` (under a minute); controls:
`ONLY=uploadtype evidence/record.sh controls`, `ONLY=unshared …`.
