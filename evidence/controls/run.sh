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
  # (a path is a script of its own, e.g. the browser proof; a name is one of example/deploy)
  case "$script" in /*) cmd=$script ;; *) cmd=$example/deploy/$script ;; esac
  env $script_env "$cmd" 2>&1 | stamped > "$out/$name.log"
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
# Other files of the example broken for a control: the original is kept in
# $out/.orig/N, with its path in N.path, and put back afterwards.
mkdir -p "$out/.orig"
break_file() { # FILE: remembers the original, then python (stdin) edits the file
  local n; n=$(ls "$out/.orig" | wc -l)
  cp "$1" "$out/.orig/$n"; echo "$1" > "$out/.orig/$n.path"
  python3 - "$1"
}
restore_example() {
  [ -f "$orig" ] && mv "$orig" "$order_service" || true
  for p in "$out"/.orig/*.path; do
    [ -f "$p" ] || continue
    mv "${p%.path}" "$(cat "$p")" && rm "$p"
  done
}
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

# Nothing counts requests: the rate limit plug is no longer in the endpoint.
patch_ratelimit() {
  break_file "$example/lib/platform/web/endpoint.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "  plug Platform.Web.RateLimit\n"
assert a in s; open(p, "w").write(s.replace(a, ""))
PY
}

# A node told to stop does not say so: no waiting, /health stays 200 until it is gone.
patch_drain() {
  break_file "$example/lib/platform/application.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "    Dandelion.Drain.start(Application.fetch_env!(:acme, :drain_delay))\n"
assert a in s; open(p, "w").write(s.replace(a, ""))
PY
}

# The Idempotency-Key header is ignored: every request makes an order.
patch_idempotency() {
  break_file "$example/lib/app/shop/handlers/order_handler.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "      [key] when byte_size(key) in 1..255 -> {:ok, key}\n"
assert a in s; open(p, "w").write(s.replace(a, "      [key] when byte_size(key) in 1..255 -> {:ok, nil}\n"))
PY
}

# A message already sent is sent again when its job runs again.
patch_mailnodedupe() {
  break_file "$example/lib/app/notifications/services/email_service.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '"sent" -> :ok\n'
assert a in s; open(p, "w").write(s.replace(a, '"sent" -> deliver(email)\n'))
PY
}

# A send that failed for a reason that passes is forgotten, not retried.
patch_mailnoretry() {
  break_file "$example/lib/app/shop/workers/send_order_confirmation.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "{:error, {:temporary, why}} -> {:error, why}"
assert a in s; open(p, "w").write(s.replace(a, "{:error, {:temporary, _why}} -> :ok"))
PY
}

# A link can be used again: it is not marked used.
patch_tokenreuse() {
  break_file "$example/lib/app/accounts/services/token_service.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "t.kind == ^kind and is_nil(t.used_at) and\n            t.expires_at > ^now,"
assert a in s; open(p, "w").write(s.replace(a, "t.kind == ^kind and\n            t.expires_at > ^now,"))
PY
}

# An address is never locked: it takes a million wrong passwords.
patch_nolockout() {
  break_file "$example/config/config.exs" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "login_max_failures: 5,"
assert a in s; open(p, "w").write(s.replace(a, "login_max_failures: 1_000_000,"))
PY
}

# A password change does not end the sessions made under the old password.
patch_norevoke() {
  break_file "$example/lib/app/accounts/handlers/token.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "true <- fingerprint == fingerprint(user.password_hash) do"
assert a in s; open(p, "w").write(s.replace(a, "true <- is_binary(fingerprint) do"))
PY
}

# The database is backed up table by table, a second apart (not one snapshot): the queued events are
# taken first, the orders later, so orders made in between come back without their events.
patch_smeared() {
  break_file "$example/deploy/backup.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "compose exec -T postgres pg_dump -U postgres --format=custom acme > \"$dir/db.dump\"\n"
assert a in s
new = '''{
  d="compose exec -T postgres pg_dump -U postgres"
  $d --schema-only acme
  $d --data-only --disable-triggers -t oban_jobs acme
  sleep 1
  $d --data-only --disable-triggers -T oban_jobs acme
} > "$dir/db.dump"
'''
open(p, "w").write(s.replace(a, new))
PY
  break_file "$example/deploy/restore.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "pg_restore -U postgres -d acme --exit-on-error"
assert a in s
open(p, "w").write(s.replace(a, "psql -U postgres -d acme -q -v ON_ERROR_STOP=1 -o /dev/null"))
PY
}

# The uploaded files are left out of the backup.
patch_nofiles() {
  break_file "$example/deploy/backup.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "tar -C /data/uploads -cf - ."
assert a in s
open(p, "w").write(s.replace(a, "tar -C /data/uploads -cf - --exclude=./* ."))
PY
}

# A product's name is put on the page as HTML (v-html), so what an admin typed becomes markup.
patch_xss() {
  break_file "$example/assets/src/pages/ProductsPage.vue" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '      <template #cell-snippet="{ row }"><Snippet :text="row.snippet" /></template>\n'
assert a in s
open(p, "w").write(s.replace(a, a + '      <template #cell-name="{ row }"><span v-html="row.name"></span></template>\n'))
PY
}

# The orders page is not hidden when another page is open.
patch_leakyorders() {
  break_file "$example/assets/src/App.vue" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '<OrdersPage v-if="admin" v-show="ordersRoute"'
assert a in s; open(p, "w").write(s.replace(a, '<OrdersPage v-if="admin"'))
PY
}

# A panel's metric name has a typo: it runs, and shows nothing.
patch_badpanel() {
  break_file "$example/deploy/grafana/dashboards/dandelion.json" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "dandelion_resilience_calls_total"
assert a in s; open(p, "w").write(s.replace(a, "dandelion_resilience_calls_totl"))
PY
}

# A circuit that opens is not counted: the metric is never emitted.
patch_nocircuitmetric() {
  break_file "$example/lib/platform/web/telemetry.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "event_name: [:dandelion, :resilience, :circuit],"
assert a in s; open(p, "w").write(s.replace(a, "event_name: [:dandelion, :resilience, :circuit_not_emitted],"))
PY
}

# What the user types reaches the query language: words are only split on spaces.
patch_unsafequery() {
  python3 - "$vendor/lib/dandelion/search.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'if terms == [], do: nil, else: terms |> Enum.map(&"#{&1}:*") |> Enum.join(" & ")'
assert a in s
s = s.replace(a, 'if String.trim(input) == "", do: nil, else: input |> String.split() |> Enum.map(&"#{&1}:*") |> Enum.join(" & ")')
open(p, "w").write(s)
PY
}

# The full-text index is never made.
patch_noindex() {
  python3 - "$vendor/lib/dandelion/search/migration.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'execute("CREATE INDEX #{table}_#{column}_index ON #{table} USING gin (#{column})")'
assert a in s; open(p, "w").write(s.replace(a, ":ok"))
PY
}

# Changing a flag is not recorded.
patch_noaudit() {
  break_file "$example/lib/app/settings/services/flag_service.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'AuditService.record(actor, "flag.set", "flag:#{key}", %{value: value})'
assert a in s; open(p, "w").write(s.replace(a, ":ok"))
PY
}

# The audit table accepts UPDATE, DELETE and TRUNCATE: the trigger lets everything through.
patch_mutable() {
  python3 - "$vendor/lib/dandelion/audit/migration.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "RAISE EXCEPTION 'dandelion_audit is append-only (% refused)', TG_OP;"
assert a in s; open(p, "w").write(s.replace(a, "RETURN COALESCE(NEW, OLD);"))
PY
}

# The type of an upload is taken on trust: anything is an image.
patch_uploadtype() {
  break_file "$example/lib/app/files/services/content_type.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "  def detect(path) do\n"
assert a in s; open(p, "w").write(s.replace(a, "  def detect(_path), do: {:ok, \"image/png\"}\n\n  @doc false\n  def detect_for_real(path) do\n"))
PY
}

# The nodes do not share the uploads directory: each has its own.
patch_unshared() {
  break_file "$example/deploy/compose.cluster.yaml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '  volumes: ["uploads:/data/uploads"]\n'
assert a in s; open(p, "w").write(s.replace(a, ""))
PY
}

# Changing a flag does not clear the other nodes' cached copy.
patch_noinvalidate() {
  python3 - "$vendor/lib/dandelion/flags.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "      Cache.delete({:flag, key})\n      {:ok, value}"
assert a in s; open(p, "w").write(s.replace(a, "      {:ok, value}"))
PY
}

# Deliveries are signed with the wrong secret.
patch_webhooksig() {
  break_file "$example/lib/app/webhooks/services/delivery.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "Dandelion.Webhook.headers(endpoint.secret, id, body)"
assert a in s; open(p, "w").write(s.replace(a, 'Dandelion.Webhook.headers("wrong-" <> endpoint.secret, id, body)'))
PY
}

# The circuit never opens: a dead receiver is called again and again.
patch_nobreaker() {
  break_file "$example/lib/app/webhooks/workers/deliver.ex" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "failure_threshold: 5,"
assert a in s; open(p, "w").write(s.replace(a, "failure_threshold: 100_000,"))
PY
}

# The migration of the second version renames a column the first still uses (BREAKING=1 in the proof).
patch_breaking() { :; }

# A node that is told to stop stops at once, cutting the requests it is serving.
patch_rollingcut() { :; }

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
  "acknowledged orders is in the database afterwards" "an order never lacks its events" "" failure-proof.sh "ONLY=load"

selected ratelimit && control ratelimit "nothing counts requests: the rate limit plug is out of the endpoint" \
  "rate limiting (3 logins" "the limit is per node, 3 nodes x 3" "" reliability-proof.sh

selected drain && control drain "a node told to stop does not say so: Dandelion.Drain.start/1 is no longer called (Platform.Application.prep_stop/1)" \
  "the limit is per node, 3 nodes x 3" "answered /health with 503 while it was still serving" "" reliability-proof.sh

selected idempotency && control idempotency "the Idempotency-Key header is ignored: a repeated request makes another order (OrderHandler)" \
  "the same request twenty times at once:" "its two events ran once each" "" idempotency-proof.sh

selected rollingcut && control rollingcut "a node told to stop neither waits before stopping nor lets requests in flight finish (DRAIN_DELAY_MS=0, SHUTDOWN_TIMEOUT_MS=0)" \
  "a rolling deploy under load:" "no request was cut off by a node stopping" "DRAIN_DELAY_MS=0 SHUTDOWN_TIMEOUT_MS=0" rolling-proof.sh

selected tokenreuse && control tokenreuse "a one-time link can be used again (TokenService.consume/2 does not mark it used)" \
  "confirming an address:" "registering sent one email with a link" "" accounts-proof.sh

selected nolockout && control nolockout "an address is never locked (login_max_failures: 1_000_000)" \
  "guessing:" "five wrong passwords through the load balancer locked the address" "" accounts-proof.sh

selected norevoke && control norevoke "a password change does not end the old sessions (Token.verify/1 ignores the fingerprint)" \
  "a forgotten password:" "the new password works, the old does not, and the session" "" accounts-proof.sh

selected smeared && control smeared "the database is backed up table by table, not as one snapshot" \
  "orders came back" "a snapshot, not a smear" "" backup-proof.sh

selected nofiles && control nofiles "the uploaded files are left out of the backup" \
  "the audit log has the product and the flag" "the file downloads with the checksum" "" backup-proof.sh

selected xss && control xss "a product's name is put on the page as HTML (v-html)" \
  "staff:" "ok  a name with HTML in it shows as the characters typed" "" "$here/browser/console.sh"

selected leakyorders && control leakyorders "the orders page is not hidden while another page is open" \
  "staff:" "ok  the orders page is hidden while another page is open" "" "$here/browser/console.sh"

selected badpanel && control badpanel "a panel's metric name has a typo (the dashboard JSON): the query runs and shows nothing" \
  "the queries:" "and the 16 panels that show what we made happen all have data" "" dashboard-proof.sh

selected nocircuitmetric && control nocircuitmetric "a circuit that opens is not counted (the metric is never emitted)" \
  "making things happen:" "the mail server stopped:" "" dashboard-proof.sh

selected breaking && control breaking "the migration renames a column the running version still uses (BREAKING=1)" \
  "the schema changes under load:" "no request failed during the upgrade" "" upgrade-proof.sh "BREAKING=1"

selected unsafequery && control unsafequery "what the user types reaches the query language (Dandelion.Search.tsquery/1 splits on spaces only)" \
  "finding things:" "14 nasty queries" "" search-proof.sh

selected noindex && control noindex "the full-text index is never created (Dandelion.Search.Migration.add_index/3)" \
  "the index:" "the plan uses the GIN index" "" search-proof.sh

selected mailnodedupe && control mailnodedupe "a message already sent is sent again when its job runs again (EmailService)" \
  "the job runs again:" "sent nothing: still one each" "" email-proof.sh

selected mailnoretry && control mailnoretry "a send that fails for a reason that passes is forgotten, not retried (SendOrderConfirmation)" \
  "the mail server goes away:" "all 6 arrived, each exactly once" "" email-proof.sh

selected noaudit && control noaudit "a flag change is not recorded in the audit log (FlagService)" \
  "making changes through the load balancer:" "the admin's flag, webhook and price changes are there" "" audit-proof.sh

selected mutable && control mutable "the audit table accepts UPDATE, DELETE and TRUNCATE (the trigger lets everything through)" \
  "the log cannot be rewritten:" "from every node, an UPDATE, a DELETE and a TRUNCATE are refused" "" audit-proof.sh

selected uploadtype && control uploadtype "the type of an upload is taken on trust: every file is an image (ContentType.detect/1)" \
  "what is accepted:" "is kept as what it is, text/plain" "" uploads-proof.sh

selected unshared && control unshared "each node has its own uploads directory instead of a shared one" \
  "upload and download:" "12 downloads, answered by all 3 nodes" "" uploads-proof.sh

selected noinvalidate && control noinvalidate "a flag change does not clear the cached copy (Dandelion.Flags.put/2 no longer calls Cache.delete)" \
  "pausing orders on a running cluster:" "the flag was set through one node" "" flags-proof.sh

selected webhooksig && control webhooksig "webhooks are signed with the wrong secret (Delivery.deliver/3)" \
  "orders while the receiver is up:" "each signature recomputes from the secret and the raw body" "" webhook-proof.sh

selected nobreaker && control nobreaker "the circuit never opens (failure_threshold: 100_000 in Deliver)" \
  "the receiver goes away:" "the circuit for it opened on" "" webhook-proof.sh

"$example/deploy/vendor-dandelion.sh" >/dev/null   # leave the copy unbroken
echo "the controls run fail where they should"
