#!/bin/sh
# Two ways the database goes wrong, on the 3-node cluster (compose.cluster.yaml
# must be up; needs curl):
#
#   1. ONE node is cut off from Postgres (docker network disconnect) but stays in
#      the cluster. It can't run jobs or lead; another node takes over; its cache
#      keeps serving until the entries expire; on reconnect it is whole again.
#   2. Postgres goes away while orders are being made through the load balancer:
#      killed (a crash), stopped cleanly, and frozen (connections open, no
#      answers). Every order that was answered 201 is still there, every order has
#      both its events (never one without the other), each handled exactly once,
#      no node restarted, and one leader is back. While it hangs, requests get a
#      quick 503, not a hung request or a 500.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

# until_is CMD EXPECTED SECONDS: until CMD prints EXPECTED
until_is() {
  for _ in $(seq 1 "$3"); do
    [ "$($1 2>/dev/null)" = "$2" ] && return 0
    sleep 1
  done
  return 1
}

# Undo what this script does to the cluster — also when it stops half way (a failed
# check) or an earlier run did: every node on the database network, Postgres up.
net=$(docker inspect "$(compose ps -q postgres)" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
restore() {
  compose start postgres >/dev/null 2>&1 || true
  for n in node1 node2 node3; do
    docker network connect "$net" "$(compose ps -q $n)" >/dev/null 2>&1 || true
  done
  [ -z "${stop:-}" ] || touch "$stop"
}
restore
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
tag="fail-$(date +%s)"

# The leader is the node to cut off: the interesting one, the node whose job it is
# to run the cron. (Found below, once `leaders` exists.)
CUT=
N1=

# ex NODE: runs the Elixir code on stdin on NODE (__TAG__, __N1__ filled in)
ex() {
  code=$(sed -e "s/__TAG__/$tag/g" -e "s/__N1__/$N1/g")
  rpc "$1" "$code"
}
db_up() { # NODE -> up | down
  rpc "$1" 'case Platform.Database.Repo.query("SELECT 1") do {:ok, _} -> IO.write(:up); _ -> IO.write(:down) end' 2>/dev/null || echo down
}
leaders() { # the nodes that think they lead, e.g. "node2 "
  for n in node1 node2 node3; do
    [ "$(rpc $n 'IO.write(Oban.Peer.leader?())' 2>/dev/null)" = true ] && printf '%s ' "$n"
  done
  return 0
}
price_on() { rpc "$1" '{:ok, p} = App.Shop.Services.ProductService.get("TEA-01"); IO.write(p.price_cents)' 2>&1 | head -c 200; }
restarts() { docker inspect --format '{{.RestartCount}}' $(compose ps -q node1 node2 node3) | awk '{ s += $1 } END { print s }'; }
make_orders() { # NODE COUNT: orders made through that node (no HTTP), tagged
  for i in $(seq 1 "$2"); do
    ex "$1" <<ELIXIR >/dev/null
{:ok, _} = App.Shop.Services.OrderService.create(%{"customer_email" => "__TAG__-$1-$i@example.com", "items" => [%{"sku" => "A", "quantity" => 1}]})
IO.write(:ok)
ELIXIR
  done
}
# orders of this run that don't have exactly two completed order.created jobs
unfinished() {
  ex "$O1" <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("""
  SELECT count(*) FROM orders o WHERE o.customer_email LIKE '__TAG__-%' AND
    (SELECT count(*) FROM oban_jobs j WHERE j.args->>'topic' = 'order.created'
       AND j.args->'payload'->>'order_id' = o.id::text AND j.state = 'completed') <> 2
""")
IO.write(n)
ELIXIR
}

# (ONLY=load skips the first half: the control that breaks the second one uses it.)
CUT=node1
O1=node2
O2=node3
if [ "${ONLY:-}" != load ]; then
for _ in $(seq 1 60); do
  CUT=$(leaders | awk '{print $1}')
  [ -n "$CUT" ] && break
  sleep 1
done
[ -n "$CUT" ] || fail "no node leads"
N1=$(rpc "$CUT" 'IO.write(node())')
others=$(for n in node1 node2 node3; do [ "$n" != "$CUT" ] && echo "$n"; done; true)
O1=$(echo "$others" | sed -n 1p)
O2=$(echo "$others" | sed -n 2p)

echo "the leader cut off from Postgres:"
cut_id=$(compose ps -q "$CUT")
[ "$(db_up "$CUT")" = up ] || fail "$CUT can't reach Postgres before the cut"
before=$(leaders)
# warm the cut node's cache with the price, as late as possible: it lives for 60 s
[ "$(price_on "$CUT")" = 1500 ] || fail "$CUT doesn't read the product price"
warmed_at=$(date +%s)
docker network disconnect "$net" "$cut_id"
cut_at=$(date +%s)
until_is "db_up "$CUT"" down 30 || fail "$CUT still reaches Postgres after the cut"
ok "$CUT, the leader, is cut off from Postgres (and only $CUT)"
price=$(price_on "$CUT")
[ "$price" = 1500 ] || fail "$CUT can't serve a cached price while cut off, $(( $(date +%s) - warmed_at )) s after warming it: $price"
ok "$CUT still serves the cached product price, with no database (until the entry expires)"
[ "$(rpc "$CUT" 'IO.write(length(Node.list()))')" = 2 ] || fail "$CUT left the cluster"
for n in $O1 $O2; do
  [ "$(rpc $n 'IO.write(length(Node.list()))')" = 2 ] || fail "$n lost a node"
done
ok "the cluster is still whole: all three nodes see each other (they talk over the other network)"

make_orders "$O1" 3
make_orders "$O2" 3
until_is unfinished 0 90 || fail "the cut-off cluster didn't finish its orders' jobs: $(unfinished) unfinished"
on_cut=$(ex "$O1" <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM oban_jobs WHERE args->'payload'->>'customer_email' LIKE '__TAG__-%' AND '__N1__' = ANY(attempted_by)")
IO.write(n)
ELIXIR
)
[ "$on_cut" = 0 ] || fail "$on_cut job(s) ran on the node that has no database"
ok "6 orders made on the other nodes: all 12 subscriber jobs completed once, none on $CUT"

# a leader: one, and not the node without a database. Sampled while we wait.
most=0
for _ in $(seq 1 45); do
  l=$(leaders)
  count=$(echo $l | wc -w)
  [ "$count" -gt "$most" ] && most=$count
  [ "$count" = 1 ] && [ "$l" != "$CUT " ] && break
  sleep 2
done
[ "$most" -le 1 ] || fail "two nodes thought they led at once"
[ "$(echo $(leaders) | wc -w)" = 1 ] && [ "$(leaders)" != "$CUT " ] || fail "no other node took over as leader: '$(leaders)'"
ok "$CUT stepped down and $(leaders)took over as the only leader, $(( $(date +%s) - cut_at )) s after the cut (never two at once)"

# the cache is not the database: past its time to live, the cut node has nothing to serve
while [ $(( $(date +%s) - warmed_at )) -lt 70 ]; do sleep 2; done
case "$(price_on "$CUT")" in
  *"connection not available"*) ok "70 s on, the cached entry has expired and $CUT has no price to give: a cache doesn't replace the database" ;;
  *) fail "$CUT still answered after its cache entry expired: $(price_on "$CUT")" ;;
esac

docker network connect "$net" "$cut_id"
until_is "db_up "$CUT"" up 60 || fail "$CUT didn't get its database back"
ok "$CUT reconnected: it reaches Postgres again"
[ "$(echo $(leaders) | wc -w)" = 1 ] || fail "after the heal, leaders: '$(leaders)'"
ok "still exactly one leader ($(leaders))"
[ "$(price_on "$CUT")" = 1500 ] || fail "$CUT can't read the price after the heal"
a=$(rpc "$CUT" 'IO.write(Platform.Database.Repo.aggregate(App.Shop.Models.Order, :count))')
b=$(rpc "$O1" 'IO.write(Platform.Database.Repo.aggregate(App.Shop.Models.Order, :count))')
[ "$a" = "$b" ] || fail "$CUT sees $a orders, $O1 sees $b"
ok "$CUT sees the same $a orders as $O1, and works again"
took_jobs=
for i in $(seq 1 12); do
  make_orders "$O1" 1
  until_is unfinished 0 30 || fail "jobs unfinished after the heal"
  took=$(ex "$O1" <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM oban_jobs WHERE args->'payload'->>'customer_email' LIKE '__TAG__-%' AND '__N1__' = ANY(attempted_by)")
IO.write(n)
ELIXIR
)
  [ "$took" -gt 0 ] && { took_jobs=$took; break; }
done
[ -n "$took_jobs" ] || fail "$CUT took no job in 12 orders after the heal"
ok "$CUT takes jobs again ($took_jobs so far)"
fi

# Postgres goes away under load, three ways; the same promises each time.
admin_token=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin_token" ] || fail "can't log in as the seeded admin"
leader_count() { echo $(leaders) | wc -w | tr -d ' '; }

# outage MODE: kill (SIGKILL, a crash) | stop (a clean shutdown) | freeze (the
# process is paused: connections stay open and nothing answers)
outage() {
  mode=$1
  case "$mode" in
    kill)   down() { compose kill -s KILL postgres >/dev/null 2>&1; }; up() { compose start postgres >/dev/null 2>&1; }
            what="killed (SIGKILL)"; gap=8 ;;
    stop)   down() { compose stop postgres >/dev/null 2>&1; }; up() { compose start postgres >/dev/null 2>&1; }
            what="stopped cleanly"; gap=8 ;;
    freeze) down() { compose pause postgres >/dev/null 2>&1; }; up() { compose unpause postgres >/dev/null 2>&1; }
            what="frozen (connections open, no answers)"; gap=25 ;;
  esac
  echo "Postgres $what under load:"
  tag="load-$mode-$(date +%s)"
  log=$(mktemp)
  stop=$(mktemp -u)
  # three workers, each making one order after another
  load() {
    w=$1
    n=0
    while [ ! -e "$stop" ]; do
      n=$((n + 1))
      body=$(curl -s -m 5 -w ' %{http_code}' -X POST http://localhost:8080/api/orders \
        -H 'content-type: application/json' -H "authorization: Bearer $admin_token" \
        -d "{\"customer_email\":\"$tag-$w-$n@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}") || body=" 000"
      id=$(echo "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
      echo "${body##* } ${id:--}" >> "$log"
      sleep 0.2
    done
  }
  before_restarts=$(restarts)
  load 1 &
  load1=$!
  load 2 &
  load2=$!
  load 3 &
  load3=$!
  sleep 6
  down
  down_at=$(date +%s)
  if [ "$mode" = freeze ]; then
    # What a client and a load balancer see while the database hangs: quick 503s,
    # not requests that hang. (A SKU nobody asked for: no cache entry to answer
    # from.) The first probes may take a moment to give up on their connections.
    sleep 6
    health=$(curl -s -m 20 -o /dev/null -w '%{http_code} %{time_total}' http://localhost:8080/health)
    health=$(curl -s -m 20 -o /dev/null -w '%{http_code} %{time_total}' http://localhost:8080/health)
    api=$(curl -s -m 20 -o /dev/null -w '%{http_code} %{time_total}' "http://localhost:8080/api/products/NEVER-ASKED-$tag")
    [ "${health%% *}" = 503 ] || fail "GET /health while Postgres is frozen: ${health%% *}, want 503"
    [ "${api%% *}" = 503 ] || fail "GET /api/products/… while Postgres is frozen: ${api%% *}, want 503 (a hung database isn't a bug in the request)"
    for t in "${health#* }" "${api#* }"; do
      [ "$(echo "$t" | awk '{ print ($1 < 5) }')" = 1 ] || fail "a request took ${t}s while Postgres was frozen: it should give up in seconds"
    done
    ok "while the database hangs: /health is 503 in ${health#* }s, the API answers 503 in ${api#* }s — quickly, not a hung request and not a 500"
  fi
  sleep "$gap"
  up
  for _ in $(seq 1 60); do
    [ "$(compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1 && echo up)" = up ] && break
    sleep 1
  done
  sleep 14
  touch "$stop"
  wait "$load1" "$load2" "$load3" || true
  rm -f "$stop"
  good=$(grep -c '^201 ' "$log" || true)
  bad=$(grep -vc '^201 ' "$log" || true)
  [ "$good" -ge 10 ] || fail "only $good orders were answered 201"
  [ "$bad" -ge 1 ] || fail "no request failed: Postgres was never really gone"
  ok "orders made through nginx while Postgres was $what and started again: $good answered 201, $bad failed during the outage"

  ids=$(sed -n 's/^201 \([0-9]*\)$/\1/p' "$log" | paste -sd, -)
  found=$(rpc "$O1" "import Ecto.Query; ids = [$ids]; IO.write(Platform.Database.Repo.aggregate(from(o in App.Shop.Models.Order, where: o.id in ^ids), :count))")
  [ "$found" = "$good" ] || fail "$good orders were acknowledged, $found are in the database"
  ok "every one of the $good acknowledged orders is in the database afterwards"

  until_is unfinished 0 120 || fail "$(unfinished) order(s) don't have exactly two completed subscriber jobs"
  discarded=$(ex "$O1" <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM oban_jobs WHERE args->'payload'->>'customer_email' LIKE '__TAG__-%' AND state = 'discarded'")
IO.write(n)
ELIXIR
)
  [ "$discarded" = 0 ] || fail "$discarded job(s) were discarded"
  total=$(ex "$O1" <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM orders WHERE customer_email LIKE '__TAG__-%'")
IO.write(n)
ELIXIR
)
  ok "all $total orders in the database (some of the $bad failures may have committed first) have exactly two completed subscriber jobs: an order never lacks its events, none ran twice"

  [ "$(restarts)" = "$before_restarts" ] || fail "a node restarted"
  for n in node1 node2 node3; do
    [ "$(rpc $n 'IO.write(length(Node.list()))')" = 2 ] || fail "$n lost a node"
  done
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)" = 200 ] || fail "/health isn't 200 afterwards"
  until_is leader_count 1 90 || fail "$(leader_count) cron leaders afterwards, want exactly 1"
  ok "no node restarted, still 3 nodes, /health 200, and exactly one cron leader again"
  rm -f "$log"
}

outage kill
outage stop
outage freeze

echo "all good"
