# 19 — Files on a directory the nodes share

Claim: A file that you upload through the load balancer lives on a directory that every node can see. The app treats the file as the property of the user, and it does so safely.

1. Upload and download. The proof uploads a 200 KB file through nginx. The stored checksum is the same as the checksum that `sha256sum` computes here. All 3 nodes answer 12 downloads, and each download is byte for byte the file. The node that took the upload is not the node that serves it. A download is an `attachment` with `nosniff`.
2. Whose file it is. Another customer gets 404. A request without a login gets 401.
3. The bytes decide what a file is. A script with the name `picture.png` and the type `image/png` is kept as `text/plain`. An executable with the same name is refused (400). Files of 5.5 MB, 6.1 MB, and 7.5 MB get 413. The service, the limit of the endpoint, and the load balancer each refuse at their own size. Refused uploads leave nothing in the directory.
4. Ten uploads at once arrive as ten files with ten ids and ten keys. The contents are intact.
5. A delete answers 404 from every node and removes the bytes.
6. All three nodes are killed while a file still arrives (a slow client). The directory has no half file, and the table has no row. The same upload works afterwards.

Code: `Dandelion.Storage.Local` in the library (an atomic write, random keys, and no path from a name). In the example: `App.Files.*`. See DESIGN.md §10.17.

Negative controls ([`uploadtype.log`](../controls/uploadtype.log), [`unshared.log`](../controls/unshared.log)): If the service takes the type on trust, it stores and serves the script as a PNG, and the proof fails. If each node has its own directory, a download from another node is not the file, and the proof fails.

Found by running it: The proof first expected the service to refuse a script. But a script is valid text, and the service keeps it as text. This is the right answer. A kill 2 seconds into an upload of 5 seconds sometimes found the upload already done. The proof now fails if the slow upload finishes before the kill.

Not shown:
- A real shared file system (NFS, EFS). The proof uses one Docker volume.
- Files with no row. The service does not collect them.
- Virus scanning.
- Range requests.
- Quotas.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh uploads`. This takes less than a minute. To run the controls, run `ONLY=uploadtype evidence/record.sh controls` and `ONLY=unshared …`.
