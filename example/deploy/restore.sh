#!/bin/sh
# Rebuilds the cluster from a backup made by backup.sh, on a machine that has lost its state
# (a fresh Postgres and an empty uploads volume): it checks the backup is whole, replaces the
# database, puts the files back, and starts everything. Usage: ./restore.sh DIR
#
# It REPLACES whatever database `acme` holds (nodes are stopped first).
set -eu
cd "$(dirname "$0")"
dir=${1:?usage: restore.sh DIR}
compose() { docker compose -f compose.cluster.yaml "$@"; }

(cd "$dir" && sha256sum -c SHA256SUMS >/dev/null) || { echo "the backup in $dir is damaged or incomplete" >&2; exit 1; }

compose stop node1 node2 node3 >/dev/null 2>&1 || true
compose up -d --wait postgres >/dev/null 2>&1
compose exec -T postgres psql -U postgres -d postgres -q \
  -c 'DROP DATABASE IF EXISTS acme WITH (FORCE)' -c 'CREATE DATABASE acme' >/dev/null
compose exec -T postgres pg_restore -U postgres -d acme --exit-on-error < "$dir/db.dump"

# (a one-off container on the uploads volume: no node has to run to receive the files)
compose run --rm --no-deps -T --entrypoint sh node1 -c 'rm -rf /data/uploads/* /data/uploads/.[!.]* 2>/dev/null; tar -C /data/uploads -xf -' < "$dir/uploads.tar" >/dev/null 2>&1

compose up -d >/dev/null 2>&1
echo "restored: database and files from $dir; the nodes are starting"
