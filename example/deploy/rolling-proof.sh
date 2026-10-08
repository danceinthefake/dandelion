#!/bin/sh
# A rolling deploy on the 3-node cluster (compose.cluster.yaml must be up; needs
# curl): the nodes are stopped and started one after another — node1, node2,
# node3 — while orders are made through the load balancer, some by clients that
# are slow to send, so requests are still in flight when a node is told to stop.
# What must hold the whole way through:
#
#   - every order is accepted: a client that is told 503 or loses its connection asks
#     again with the same Idempotency-Key, so an order is made once, never twice;
#   - each node stops itself (exit 0, not killed) and rejoins: 3 nodes again
#     before the next one is touched;
#   - every acknowledged order is in the database, with exactly one completed job per subscriber
#     events; one cron leader at the end; no container restarted by Docker.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

restore() {
  for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1 || true; done
  [ -z "${stop:-}" ] || touch "$stop"
}
trap restore EXIT

cluster_whole() { # every node sees the other two
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
tag="roll-$(date +%s)"
restarts() { docker inspect --format '{{.RestartCount}}' $(compose ps -q node1 node2 node3) | awk '{ s += $1 } END { print s }'; }
before_restarts=$(restarts)

admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

stop=$(mktemp -u)
log=$(mktemp)
fails=$(mktemp)
# worker W RATE: orders one after another; RATE is a curl --limit-rate (a slow client
# takes ~1.5 s to send its body, so it is mid-request when a node is stopped).
# Each order has an Idempotency-Key; an answer that is not 200/201 is asked again
# with the same key, up to 6 times, 1 s apart — what a careful client does. The log
# has one line per order: the final status, the id, and how many attempts it took.
pad=$(printf '%1500s' '')
worker() {
  w=$1; rate=$2; n=0
  while [ ! -e "$stop" ]; do
    n=$((n + 1))
    attempts=0; code=000; id=-
    while [ "$attempts" -lt 6 ]; do
      attempts=$((attempts + 1))
      body=$(curl -s -m 10 --limit-rate "$rate" -w ' %{http_code}' -X POST http://localhost:8080/api/orders \
        -H 'content-type: application/json' -H "authorization: Bearer $admin" -H "idempotency-key: $tag-$w-$n" \
        -d "{\"customer_email\":\"$tag-$w-$n@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]$pad}") || body=" 000"
      code=${body##* }
      id=$(echo "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
      case "$code" in 200|201) break ;; esac
      echo "$code $(date +%T) $w" >> "$fails"
      sleep 1
    done
    echo "$code ${id:--} $attempts $(date +%T) $w" >> "$log"
    sleep 0.1
  done
}
worker fast1 10m & w1=$!
worker fast2 10m & w2=$!
worker slow1 1k & w3=$!
worker slow2 1k & w4=$!
sleep 5

echo "a rolling deploy under load:"
for n in node1 node2 node3; do
  at=$(date +%s)
  echo "  $(date +%T) stopping $n"
  compose stop -t 40 "$n" >/dev/null 2>&1
  code=$(docker inspect "$(compose ps -aq $n)" --format '{{.State.ExitCode}}')
  [ "$code" = 0 ] || fail "$n exited with $code (killed, not stopped)"
  compose start "$n" >/dev/null 2>&1
  cluster_whole || fail "after $n came back the cluster is not whole"
  ok "$n stopped itself (exit 0), started again, and the cluster is whole: $(( $(date +%s) - at )) s"
  sleep 3
done

touch "$stop"
wait "$w1" "$w2" "$w3" "$w4" || true
total=$(wc -l < "$log")
bad=$(awk '$1 != 201 && $1 != 200' "$log" | cut -c1-80 | tr '\n' ';')
[ "$total" -gt 50 ] || fail "only $total orders were made"
[ -z "$bad" ] || fail "orders were never accepted, even after retrying: $bad"
retried=$(awk '$3 > 1' "$log" | wc -l | tr -d ' ')
extra=$(awk '{ s += $3 - 1 } END { print s + 0 }' "$log")
# A 503 or 500 can be the database stalling (a slow disk makes a COMMIT wait, and
# every commit that sends a NOTIFY waits behind it); a connection cut off or a bad
# gateway can only be the stopping node: those must not happen.
cut=$(awk '$1 != 500 && $1 != 503' "$fails" | sort | uniq -c | tr '\n' ' ')
[ -z "$cut" ] || fail "requests were cut off by a stopping node (status, count): $cut"
db=$(wc -l < "$fails" | tr -d ' ')
ok "no request was cut off by a node stopping ($db refused by a database stall, retried)"
ok "all $total orders were accepted; $retried needed a retry ($extra retries in all)"

[ "$(restarts)" = "$before_restarts" ] || fail "Docker restarted a container"
ok "no container was restarted by Docker"

ids=$(awk '{print $2}' "$log" | paste -sd, -)
made=$(rpc node1 "
  ids = [$ids]
  %{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE id = ANY(\$1)\", [ids])
  %{rows: [[all]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE customer_email LIKE '$tag-%'\")
  IO.write(\"#{n} #{all}\")
")
[ "$made" = "$total $total" ] || fail "$total orders were accepted, but (of those, in total with this run's tag) the database has: $made"
ok "the database has exactly those $total orders: none lost, none made twice by a retry"

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
ok "every order has all its events (one per subscriber), handled once"

leaders=0
for _ in $(seq 1 60); do
  leaders=0
  for n in node1 node2 node3; do
    [ "$(rpc $n 'IO.write(Oban.Peer.leader?())' 2>/dev/null)" = true ] && leaders=$((leaders + 1))
  done
  [ "$leaders" = 1 ] && break
  sleep 1
done
[ "$leaders" = 1 ] || fail "$leaders cron leaders after the deploy"
ok "exactly one cron leader"
echo "rolling deploy proof passed"
