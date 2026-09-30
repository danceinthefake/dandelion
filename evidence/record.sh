#!/usr/bin/env bash
# Regenerates the evidence (logs, GIFs) from the code in this checkout.
#
#   ./record.sh [all | proof | live | controls | tests]
#
#   proof     the 3-node cluster proof → 01, 03, 04, 05, 07 (run.log + GIFs)
#   live      two browsers on two nodes → 02 (live-feed.gif)
#   controls  the proof with one thing broken on purpose → controls/
#   tests     library and example tests, integration tests → 06, 08
#
# Needs: Docker, Node (+ `npm install` and `npx playwright install chromium`
# here, or PLAYWRIGHT=/path/to/playwright/index.mjs), ffmpeg, python3, and the
# Postgres from example/compose.yaml on :55432 for `tests`. See README.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
example=$root/example
work=$here/_work
mkdir -p "$work"

stamp() {
  {
    echo "commit: $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet HEAD -- . ':!evidence' || echo ' (+ uncommitted changes)')"
    echo "recorded: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo "machine: $(uname -sr), $(docker version --format 'docker {{.Server.Version}}')"
    echo "runtime: $(cd "$root" && mise exec -- elixir --short-version 2>/dev/null || elixir --short-version), OTP $(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null)"
  } > "$work/STAMP.txt"
}

# prefix every line with the time it arrived
stamped() { while IFS= read -r line; do printf '%s %s\n' "$(date -u +%T)" "$line"; done; }

cluster_up() {
  "$example/deploy/vendor-dandelion.sh" >/dev/null
  docker compose -f "$example/deploy/compose.cluster.yaml" down -v >/dev/null 2>&1 || true
  docker compose -f "$example/deploy/compose.cluster.yaml" up -d --build >/dev/null 2>&1
}
cluster_down() { docker compose -f "$example/deploy/compose.cluster.yaml" down -v >/dev/null 2>&1 || true; }

gif() { node "$here/render/term2gif.mjs" "$1/run.log" "$1/$2" "$3"; }

proof() {
  stamp
  cluster_up
  # the proof exits non-zero on the first failure; keep the log either way
  set +e
  "$example/deploy/cluster-proof.sh" 2>&1 | stamped > "$work/proof.log"
  status=${PIPESTATUS[0]}
  set -e
  cluster_down
  [ "$status" = 0 ] || { echo "the proof failed, see $work/proof.log" >&2; exit 1; }
  grep -q "all good" "$work/proof.log"
  python3 "$here/lib/split_proof.py" "$work/proof.log" "$here" "$work/STAMP.txt"
  gif "$here/01-cluster" cluster.gif "01 — the nodes find each other, and survive a kill"
  gif "$here/03-killed-node-job" killed-node-job.gif "03 — a job left by a killed node is run again by another node"
  gif "$here/04-ordered-queue" ordered-queue.gif "04 — payment events keep their order while three nodes race for them"
  gif "$here/05-cache" cache.gif "05 — a price changed on one node is read fresh on all three"
}

live() {
  stamp
  cluster_up
  # wait until the three nodes have found each other
  for _ in $(seq 1 40); do
    n=$(docker compose -f "$example/deploy/compose.cluster.yaml" exec -T node1 bin/acme rpc 'IO.write(length(Node.list()))' 2>/dev/null || true)
    [ "$n" = 2 ] && break
    sleep 2
  done
  node "$here/browser/live-feed.mjs" "$here/02-live-feed"
  { sed 's/^/# /' "$work/STAMP.txt"; echo; cat "$here/02-live-feed/browser.log"; } > "$here/02-live-feed/run.log"
  rm "$here/02-live-feed/browser.log"
  cluster_down
}

controls() { "$here/controls/run.sh"; }

tests() {
  stamp
  local header
  header=$(sed 's/^/# /' "$work/STAMP.txt")
  {
    echo "$header"; echo "# library: test/dandelion/pubsub_test.exs"
    (cd "$root" && mix test test/dandelion/pubsub_test.exs --trace 2>&1 | python3 "$here/lib/clean_trace.py")
    echo; echo "# example: test/platform/pubsub_test.exs (order + event in one transaction)"
    (cd "$example" && mix test test/platform/pubsub_test.exs --trace 2>&1 | python3 "$here/lib/clean_trace.py")
  } > "$here/06-one-transaction/run.log"
  {
    echo "$header"; echo "# library"; (cd "$root" && mix test 2>&1 | tail -4)
    echo; echo "# example"; (cd "$example" && mix test 2>&1 | tail -4)
    echo; echo "# generator"; (cd "$root/installer" && mix test 2>&1 | tail -4)
    echo; echo "# generated projects (integration; Docker, network, ~10 min)"
    (cd "$root/installer" && mix test test/integration_test.exs --include integration --trace 2>&1 | grep -vE "warning:|Compiling|Generated|==>|\* (Getting|Resolving)" | python3 "$here/lib/clean_trace.py")
  } > "$here/08-generated-projects/run.log"
}

case "${1:-all}" in
  proof) proof ;;
  live) live ;;
  controls) controls ;;
  tests) tests ;;
  all) proof; live; controls; tests ;;
  *) echo "usage: $0 [all|proof|live|controls|tests]" >&2; exit 2 ;;
esac
