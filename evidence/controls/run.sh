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

# ONLY=name runs just that control (the others' logs stay as they are).
selected() { [ -z "${ONLY:-}" ] || [ "$ONLY" = "$1" ]; }

# control NAME "what is broken" PRESENT ABSENT [ENV=VALUE] [SCRIPT] [SCRIPT_ENV]
#   PRESENT: a line the log must contain (the proof got this far)
#   ABSENT:  a line it must NOT contain (the step that depends on the feature)
control() {
  local name=$1 what=$2 present=$3 absent=$4 env=${5:-} script=${6:-cluster-proof.sh} script_env=${7:-}
  echo "== control: $name — $what"
  "$example/deploy/vendor-dandelion.sh" >/dev/null
  "patch_$name"
  $compose down -v >/dev/null 2>&1 || true
  env $env $compose up -d --build >/dev/null 2>&1
  set +e
  env $script_env "$example/deploy/$script" 2>&1 | stamped > "$out/$name.log"
  local status=${PIPESTATUS[0]}
  set -e
  $compose down -v >/dev/null 2>&1 || true
  restore_example
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

# A file of the example itself is broken for a control: its original is kept here
# and put back after the control (and on exit, however the script ends).
orig="$out/.order_service.ex.orig"
order_service="$example/lib/app/shop/services/order_service.ex"
restore_example() { [ -f "$orig" ] && mv "$orig" "$order_service" || true; }
trap restore_example EXIT

# An order's events are saved AFTER the order's transaction, with a long gap (so a
# crash always falls into it), instead of inside it.
patch_dualwrite() {
  cp "$order_service" "$orig"
  python3 - "$order_service" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
inside = """        with {:ok, order} <- OrderRepo.insert(changeset) do
          PubSub.publish("order.created", %{
            "order_id" => order.id,
            "customer_email" => order.customer_email
          })

          {:ok, order}
        end
      end)

    with {:ok, order} <- result do
      Phoenix.PubSub.broadcast"""
broken = """        OrderRepo.insert(changeset)
      end)

    with {:ok, order} <- result do
      Process.sleep(1500)

      PubSub.publish("order.created", %{
        "order_id" => order.id,
        "customer_email" => order.customer_email
      })

      Phoenix.PubSub.broadcast"""
assert inside in s
open(p, "w").write(s.replace(inside, broken))
PY
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

# A node that rejoins keeps its cache (it should empty it: it may have missed deletes).
patch_rejoin() {
  python3 - "$vendor/lib/dandelion/cache/listener.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "    Cachex.clear(Dandelion.Cache)\n    {:noreply, state}"
assert a in s; open(p, "w").write(s.replace(a, "    {:noreply, state}"))
PY
}

# A job left by a dead node is given back after a day, not 10 seconds.
patch_lifeline() { :; }

selected ordering && control ordering "the ordered queue never waits (Dandelion.Queue.Ordered.turn/1 always says go)" \
  "ordered queue:" "10 orders: payment then refund"
selected cache && control cache "a cache delete is not sent to the other nodes (Dandelion.Cache.delete/1)" \
  "read on all 3 nodes" "every node reads 1600"
selected lifeline && control lifeline "a dead node's job is given back after a day, not 10 seconds (OBAN_RESCUE_AFTER_SECONDS=86400)" \
  "(other order) paid while" "the dead node's job was rescued" "OBAN_RESCUE_AFTER_SECONDS=86400"

selected rejoin && control rejoin "a node that rejoins after a split keeps its cache (Dandelion.Cache.Listener no longer clears on :nodeup)" \
  "split: node1 alone" "node1's cache was emptied when it rejoined" "" partition-proof.sh

selected dualwrite && control dualwrite "an order's events are saved after its transaction, with a 1.5 s gap, not inside it (OrderService.create/2)" \
  "acknowledged orders is in the database after the crash" "an order never lacks its events" "" failure-proof.sh "ONLY=load"

"$example/deploy/vendor-dandelion.sh" >/dev/null   # leave the copy unbroken
echo "the controls run fail where they should"
