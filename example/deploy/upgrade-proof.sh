#!/bin/sh
# A deploy that changes the database, on the 3-node cluster (compose.cluster.yaml must be up,
# running the current version; needs curl, patch and tar). Version 2 adds a column to `orders`
# and code that uses it (deploy/versions/order-channel.patch). The way to do that without
# stopping anything — expand, then roll — is what is checked, under load, with slow clients:
#
#   1. the migration runs while all three nodes still run version 1: nothing fails;
#   2. the nodes are replaced one at a time, so for a while version 1 and version 2 serve the
#      same traffic over the same table, and the cluster stays whole: every request is answered
#      (a 503 is retried with the order's idempotency key), every order made can be read back
#      from any node, and orders made by either version have their events done;
#   3. at the end all three are version 2, and the orders made before and during have the
#      column's default.
#
# BREAKING=1 swaps in a migration that renames a column version 1 still uses: the control that
# shows this proof can fail.
set -eu
cd "$(dirname "$0")"
here=$(pwd)

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
command -v patch >/dev/null || fail "needs patch(1)"

work=$(mktemp -d)
stop=$(mktemp -u)
cleanup() {
  touch "$stop"
  kill ${w1:-} ${w2:-} ${w3:-} ${w4:-} 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

cluster_whole() {
  for c in node1 node2 node3; do
    for _ in $(seq 1 90); do
      [ "$(rpc $c 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && continue 2
      sleep 1
    done
    return 1
  done
}
cluster_whole || fail "the cluster is not whole before the deploy"
./seed.sh >/dev/null
SUBS=$(rpc node1 'IO.write(length(Platform.PubSub.subscriptions()["order.created"]))')
tag="up-$(date +%s)"
has_channel() { rpc "$1" 'IO.write(Map.has_key?(%App.Shop.Models.Order{}, :channel))'; }
for n in node1 node2 node3; do [ "$(has_channel $n)" = false ] || fail "$n already runs version 2"; done
restarts() { docker inspect --format '{{.RestartCount}}' $(compose ps -q node1 node2 node3) | awk '{ s += $1 } END { print s }'; }
before_restarts=$(restarts)

echo "building version 2:"
ctx="$work/v2"
mkdir -p "$ctx"
# (the project as it is, minus what is built or fetched; the Docker build starts from this)
tar -cf - -C .. --exclude=./_build --exclude=./deps --exclude=./node_modules --exclude=./.git --exclude=./tmp --exclude=./priv/static . | tar -xf - -C "$ctx"
( cd "$ctx" && patch -s -p2 < "$here/versions/order-channel.patch" ) || fail "the version 2 patch no longer applies: update deploy/versions/order-channel.patch"
migration="$ctx/priv/repo/migrations/20261011000001_add_order_channel.exs"
[ -f "$migration" ] || fail "the patch did not add the migration"
if [ -n "${BREAKING:-}" ]; then
  cat > "$migration" <<'ELIXIR'
defmodule Platform.Database.Repo.Migrations.AddOrderChannel do
  use Ecto.Migration

  # NOT safe: version 1 still reads and writes customer_email
  def change do
    rename table(:orders), :customer_email, to: :email
    alter table(:orders) do
      add :channel, :text, null: false, default: "web"
    end
  end
end
ELIXIR
fi
export APP_SOURCE="$ctx" APP_VERSION=2
compose build node1 >/dev/null 2>&1 || fail "version 2 does not build"
ok "version 2 built (one more column, and code that reads and writes it)"
unset APP_SOURCE APP_VERSION

admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

# worker NAME RATE: orders one after another, each read back with a GET; a slow client takes ~1.5 s
# to send its body (so it is mid-request when a node is replaced). A status that is not 2xx is asked
# again with the same Idempotency-Key, up to 6 times; every attempt that failed goes to $fails.
log="$work/orders"; fails="$work/fails"; : > "$log"; : > "$fails"
pad=$(printf '%1500s' '')
worker() {
  w=$1; rate=$2; n=0
  while [ ! -e "$stop" ]; do
    n=$((n + 1)); attempts=0; code=000; id=-
    while [ "$attempts" -lt 6 ]; do
      attempts=$((attempts + 1))
      body=$(curl -s -m 10 --limit-rate "$rate" -w ' %{http_code}' -X POST http://localhost:8080/api/orders \
        -H 'content-type: application/json' -H "authorization: Bearer $admin" -H "idempotency-key: $tag-$w-$n" \
        -d "{\"customer_email\":\"$tag-$w-$n@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]$pad}") || body=" 000"
      code=${body##* }
      id=$(echo "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
      case "$code" in 200|201) break ;; esac
      echo "$code post" >> "$fails"
      sleep 1
    done
    read_code=-
    if [ "$id" != - ]; then
      read_code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://localhost:8080/api/orders/$id" -H "authorization: Bearer $admin") || read_code=000
      [ "$read_code" = 200 ] || echo "$read_code get" >> "$fails"
    fi
    echo "$code ${id:--} $attempts $read_code" >> "$log"
    sleep 0.1
  done
}
worker fast1 10m & w1=$!
worker fast2 10m & w2=$!
worker slow1 1k & w3=$!
worker slow2 1k & w4=$!
sleep 5

echo "the schema changes under load:"
APP_SOURCE="$ctx" APP_VERSION=2 compose run --rm --build migrate >/dev/null 2>&1 || fail "the migration failed"
col=$(rpc node1 'IO.write(hd(hd(Platform.Database.Repo.query!("SELECT count(*) FROM information_schema.columns WHERE table_name = \x27orders\x27 AND column_name = \x27channel\x27").rows)))')
[ "$col" = 1 ] || fail "the migration ran but orders has no channel column"
for n in node1 node2 node3; do [ "$(has_channel $n)" = false ] || fail "$n changed with the migration"; done
sleep 8
ok "the migration ran while all three nodes still ran version 1 (they did not notice)"

for n in node1 node2 node3; do
  at=$(date +%s)
  echo "  $(date +%T) replacing $n"
  APP_SOURCE="$ctx" APP_VERSION=2 compose up -d --no-deps "$n" >/dev/null 2>&1 || fail "replacing $n failed"
  cluster_whole || fail "after $n was replaced the cluster is not whole"
  [ "$(has_channel $n)" = true ] || fail "$n is not running version 2"
  # nginx looks a name up once, at start: a replaced container has a new address, and the load
  # balancer has to be told (a real one finds nodes by itself, from health checks or discovery)
  compose exec -T nginx nginx -s reload >/dev/null 2>&1 || fail "nginx did not reload"
  sleep 2
  ok "$n runs version 2 and the cluster is whole ($(( $(date +%s) - at )) s)"
  if [ "$n" = node1 ]; then
    # the mixed state, looked at: orders that ask for a channel, answered by whichever node
    : > "$work/mixed"
    for i in $(seq 1 30); do
      curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' -H "authorization: Bearer $admin" \
        -H 'x-channel: mobile' -d "{\"customer_email\":\"$tag-mixed-$i@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" \
        -w ' %{http_code}\n' >> "$work/mixed"
    done
    new=$(grep -c '"channel":"mobile"' "$work/mixed" || true)
    old=$(grep -v '"channel"' "$work/mixed" | grep -c ' 201$' || true)
    [ "$((new + old))" = 30 ] || fail "in the mixed state only $((new + old)) of 30 orders were answered as expected ($new by version 2, $old by version 1): the two versions do not work over the same table"
    [ "$new" -ge 1 ] && [ "$old" -ge 1 ] || fail "the state was not mixed: $new answered by version 2, $old by version 1"
    ok "version 1 and 2 serve together: of 30 orders asking for a channel, $new were answered by version 2 (with it), $old by version 1 (ignoring it); all 201"
  fi
  sleep 5
done

touch "$stop"
wait "$w1" "$w2" "$w3" "$w4" || true

echo "afterwards:"
total=$(wc -l < "$log" | tr -d ' ')
[ "$total" -gt 40 ] || fail "only $total orders were made"
# a 503 can be the database stalling on a slow disk (DESIGN.md 10.14: retried, with the key); a 500, a
# 502 or a connection that was cut is a version that could not cope with the table or a node that stopped badly
bad=$(awk '$1 != 503' "$fails" | sort | uniq -c | tr '\n' ';')
[ -z "$bad" ] || fail "requests failed during the upgrade (count status kind): $bad"
stalls=$(grep -c . "$fails" || true)
ok "no request failed during the upgrade: $total orders made and read back from any node ($stalls refused with 503 and retried)"
unread=$(awk '$4 != 200' "$log" | wc -l | tr -d ' ')
unaccepted=$(awk '$1 != 200 && $1 != 201' "$log" | wc -l | tr -d ' ')
[ "$unaccepted" = 0 ] && [ "$unread" = 0 ] || fail "$unaccepted orders were never accepted, $unread could not be read back"

for n in node1 node2 node3; do [ "$(has_channel $n)" = true ] || fail "$n is not on version 2"; done
[ "$(restarts)" = "$before_restarts" ] || fail "Docker restarted a container"
ok "all three nodes run version 2; Docker restarted nothing"

ids=$(awk '{print $2}' "$log" | paste -sd, -)
made=$(rpc node1 "
  ids = [$ids]
  %{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE id = ANY(\$1)\", [ids])
  %{rows: [[web]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE id = ANY(\$1) AND channel = 'web'\", [ids])
  IO.write(\"#{n} #{web}\")
")
[ "$made" = "$total $total" ] || fail "of $total orders, the database has (orders, with channel web): $made"
ok "the database has exactly those $total orders, each with the column's default (web)"

for _ in $(seq 1 90); do
  open=$(rpc node1 "
    %{rows: [[n]]} = Platform.Database.Repo.query!(\"\"\"
      SELECT count(*) FROM orders o WHERE o.customer_email LIKE '$tag-%' AND
        (SELECT count(*) FROM oban_jobs j WHERE j.args->>'topic' = 'order.created'
           AND j.args->'payload'->>'order_id' = o.id::text AND j.state = 'completed') <> $SUBS
    \"\"\")
    IO.write(n)
  ")
  [ "$open" = 0 ] && break
  sleep 1
done
[ "$open" = 0 ] || fail "$open orders don't have exactly one completed job per subscriber"
ok "every order, whichever version made it, has all its events done once"

after=$(for i in $(seq 1 12); do
  curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' -H "authorization: Bearer $admin" -H 'x-channel: mobile' \
    -d "{\"customer_email\":\"$tag-after-$i@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" -w '\n'
done | grep -c '"channel":"mobile"' || true)
[ "$after" = 12 ] || fail "only $after of 12 orders after the upgrade carry the channel they asked for"
ok "now every node uses the column: 12 of 12 orders carry the channel they asked for"
echo "upgrade proof passed"
