#!/usr/bin/env bash
# Negative controls: break one thing on purpose, run the same cluster proof,
# and record that it FAILS where it should. A proof that can't fail proves
# nothing. The library is broken in example/vendor/dandelion (the copy the
# Docker image is built from), never in lib/.
#
#   ./controls/run.sh            (record.sh controls)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
root=$(dirname "$here")
example=$root/example
vendor=$example/vendor/dandelion
out=$here/controls
compose="docker compose -f $example/deploy/compose.cluster.yaml"

stamped() { while IFS= read -r line; do printf '%s %s\n' "$(date -u +%T)" "$line"; done; }

# control NAME "what is broken" PRESENT ABSENT [ENV=VALUE]
#   PRESENT: a line the log must contain (the proof got this far)
#   ABSENT:  a line it must NOT contain (the step that depends on the feature)
control() {
  local name=$1 what=$2 present=$3 absent=$4 env=${5:-}
  echo "== control: $name — $what"
  "$example/deploy/vendor-dandelion.sh" >/dev/null
  "patch_$name"
  $compose down -v >/dev/null 2>&1 || true
  env $env $compose up -d --build >/dev/null 2>&1
  set +e
  "$example/deploy/cluster-proof.sh" 2>&1 | stamped > "$out/$name.log"
  local status=${PIPESTATUS[0]}
  set -e
  $compose down -v >/dev/null 2>&1 || true
  local verdict=ok
  [ "$status" != 0 ] || verdict="WRONG: the proof passed with $what"
  grep -q -- "$present" "$out/$name.log" || verdict="WRONG: the log lacks '$present'"
  ! grep -q -- "$absent" "$out/$name.log" || verdict="WRONG: the log has '$absent'"
  {
    echo "# control: $name"
    echo "# broken on purpose: $what"
    echo "# expected: the proof FAILS after '$present' and never reaches '$absent'"
    echo "# commit: $(git -C "$root" rev-parse --short HEAD), recorded $(date -u +%Y-%m-%dT%H:%MZ)"
    echo "# verdict: $verdict"
    echo
    cat "$out/$name.log"
  } > "$out/$name.log.tmp" && mv "$out/$name.log.tmp" "$out/$name.log"
  [ "$verdict" = ok ] || { echo "$verdict" >&2; return 1; }
  echo "   $name: fails where it should"
}

# The order check never waits.
patch_ordering() {
  python3 - "$vendor/lib/dandelion/queue/ordered.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "if Oban.Repo.exists?(Oban.config(Oban), earlier), do: {:snooze, 1}, else: :ok"
assert a in s; open(p, "w").write(s.replace(a, "_ = earlier\n    :ok"))
PY
}

# A delete clears this node only; it is not sent to the others.
patch_cache() {
  python3 - "$vendor/lib/dandelion/cache.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "Phoenix.PubSub.broadcast_from(pubsub, self(), Listener.topic(), {:cache_delete, key})"
assert a in s; open(p, "w").write(s.replace(a, "_ = pubsub\n    :ok"))
PY
}

# A job left by a dead node is given back after a day, not 10 seconds.
patch_lifeline() { :; }

control ordering "the ordered queue never waits (Dandelion.Queue.Ordered.turn/1 always says go)" \
  "ordered queue:" "10 orders: payment then refund"
control cache "a cache delete is not sent to the other nodes (Dandelion.Cache.delete/1)" \
  "read on all 3 nodes" "every node reads 1600"
control lifeline "a dead node's job is given back after a day, not 10 seconds (OBAN_RESCUE_AFTER_SECONDS=86400)" \
  "(other order) paid while" "the dead node's job was rescued" "OBAN_RESCUE_AFTER_SECONDS=86400"

"$example/deploy/vendor-dandelion.sh" >/dev/null   # leave the copy unbroken
echo "all three controls fail where they should"
