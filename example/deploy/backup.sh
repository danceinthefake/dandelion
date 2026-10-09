#!/bin/sh
# Backs up the cluster's two kinds of state into DIR (compose.cluster.yaml must be up):
#
#   db.dump      the database, in ONE pg_dump: a single snapshot, so what was committed together
#                (an order and the events queued with it) is in the dump together, or not at all;
#   uploads.tar  the uploaded files, taken AFTER the dump: every file row in the dump has its
#                bytes here (a file stored in between is only an unlisted extra, which is harmless).
#
# The cluster keeps serving while this runs. Usage: ./backup.sh DIR
set -eu
cd "$(dirname "$0")"
dir=${1:?usage: backup.sh DIR}
mkdir -p "$dir"
compose() { docker compose -f compose.cluster.yaml "$@"; }

compose exec -T postgres pg_dump -U postgres --format=custom acme > "$dir/db.dump"
compose exec -T node1 tar -C /data/uploads -cf - . > "$dir/uploads.tar"
(cd "$dir" && sha256sum db.dump uploads.tar > SHA256SUMS)
echo "backed up: $(du -h "$dir/db.dump" | cut -f1) database, $(du -h "$dir/uploads.tar" | cut -f1) files, in $dir"
