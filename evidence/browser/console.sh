#!/usr/bin/env bash
# The console proof as one command, for record.sh and the controls: makes sure the cluster is whole and
# seeded, then drives the console in a browser (browser/console.mjs). Needs PLAYWRIGHT, ffmpeg.
#   browser/console.sh [OUT_DIR]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
example=$(dirname "$here")/example
compose="docker compose -f $example/deploy/compose.cluster.yaml"

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$($compose exec -T $n bin/acme rpc 'IO.write(length(Node.list()))' 2>/dev/null || true)" = 2 ] && break
    sleep 1
  done
done
"$example/deploy/seed.sh" >/dev/null
for _ in $(seq 1 30); do curl -sf http://localhost:18025/api/v1/info >/dev/null && break; sleep 1; done
node "$here/browser/console.mjs" "${1:-$(mktemp -d)}"
