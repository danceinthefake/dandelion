#!/bin/sh
# A client can ask again without ordering twice (compose.cluster.yaml must be up;
# needs curl). `POST /api/orders` with an `Idempotency-Key` header:
#
#   1. twenty identical requests at once, through the load balancer and so on all
#      three nodes: exactly ONE order is made, every answer is that order (one 201,
#      the rest 200 with `idempotent-replayed: true`), and its events ran once;
#   2. a retry later, on whichever node, returns the same order again;
#   3. the same key with a different request is refused (409) and makes nothing;
#   4. a client that never got an answer — the request was cut off while its body
#      was still arriving, the node killed — asks again with the same key and
#      ends up with exactly one order.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

restore() { for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1 || true; done; }
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
SUBS=$(rpc node1 'IO.write(length(Platform.PubSub.subscriptions()["order.created"]))')
tag="idem-$(date +%s)"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

order() { # KEY EMAIL [curl args...] -> "STATUS ID"
  key=$1; email=$2; shift 2
  { curl -s -m 20 "$@" -w ' %{http_code}' -X POST http://localhost:8080/api/orders \
    -H 'content-type: application/json' -H "authorization: Bearer $admin" -H "idempotency-key: $key" \
    -d "{\"customer_email\":\"$email\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}"; echo; } \
    | sed -n 's/.*"id":\([0-9]*\).*} \([0-9]*\)$/\2 \1/p'
}
orders_with() { # EMAIL -> how many orders in the database
  rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE customer_email = '$1'\"); IO.write(n)"
}

echo "the same request twenty times at once:"
email="$tag-race@example.com"
out=$(mktemp)
for i in $(seq 1 20); do order "$tag-race" "$email" >> "$out" & done
wait
total=$(grep -c . "$out")
created=$(grep -c '^201 ' "$out" || true)
replayed=$(grep -c '^200 ' "$out" || true)
ids=$(awk '{print $2}' "$out" | sort -u | wc -l | tr -d ' ')
[ "$total" = 20 ] || fail "only $total of 20 requests were answered with an order: $(sort "$out" | uniq -c | tr '\n' ' ')"
[ "$ids" = 1 ] || fail "$ids different orders came back"
[ "$created" = 1 ] || fail "$created requests were told they created the order (want 1)"
[ "$(orders_with "$email")" = 1 ] || fail "$(orders_with "$email") orders were made"
ok "20 requests, 1 order: 1 answered 201, $replayed answered 200 with the same order"
id=$(awk '{print $2}' "$out" | head -1)

for _ in $(seq 1 60); do
  done_jobs=$(rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM oban_jobs WHERE args->'payload'->>'order_id' = '$id' AND state = 'completed'\"); IO.write(n)")
  [ "$done_jobs" = "$SUBS" ] && break
  sleep 1
done
[ "$done_jobs" = "$SUBS" ] || fail "the order has $done_jobs completed events, want $SUBS"
ok "its events ran once each, one per subscriber (no event for the retries)"

echo "asking again later:"
again=$(order "$tag-race" "$email")
[ "$again" = "200 $id" ] || fail "a later retry answered '$again', want '200 $id'"
ok "a retry on a later request returns order $id again"

echo "the same key, a different request:"
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/orders \
  -H 'content-type: application/json' -H "authorization: Bearer $admin" -H "idempotency-key: $tag-race" \
  -d "{\"customer_email\":\"$tag-other@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}")
[ "$status" = 409 ] || fail "a reused key with another request answered $status, want 409"
[ "$(orders_with "$tag-other@example.com")" = 0 ] || fail "the refused request made an order"
ok "refused with 409, and nothing was made"

echo "a request cut off, then asked again:"
email2="$tag-cut@example.com"
# a slow client: the body takes ~3 s to arrive; the node it reached is killed meanwhile
pad=$(printf '%3000s' '')
( curl -s -m 20 --limit-rate 1k -o /dev/null -X POST http://localhost:8080/api/orders \
    -H 'content-type: application/json' -H "authorization: Bearer $admin" -H "idempotency-key: $tag-cut" \
    -d "{\"customer_email\":\"$email2\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]$pad}" || true ) &
slow=$!
sleep 1
for n in node1 node2 node3; do compose kill -s KILL "$n" >/dev/null 2>&1 || true; done
wait "$slow" || true
for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1; done
for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
before=$(orders_with "$email2")
retry=$(order "$tag-cut" "$email2")
case "$retry" in 201\ *|200\ *) ;; *) fail "the retry after the nodes came back answered '$retry'" ;; esac
[ "$(orders_with "$email2")" = 1 ] || fail "$(orders_with "$email2") orders exist after the retry (had $before before it)"
ok "the nodes were killed mid-request (an order before the retry: $before); the retry left exactly one order"
retry2=$(order "$tag-cut" "$email2")
[ "${retry2%% *}" = 200 ] || fail "asking a third time answered '$retry2'"
ok "and asking once more returns it, still one order"
echo "idempotency proof passed"
