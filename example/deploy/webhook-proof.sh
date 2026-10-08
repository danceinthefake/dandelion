#!/bin/sh
# Telling another service what happened here, reliably (compose.cluster.yaml must be
# up; needs curl and openssl). An admin registers a URL; every new order is sent to it
# as a signed webhook:
#
#   1. each order is delivered, once, signed — the signature checks out when
#      recomputed here from the secret, the id, the timestamp and the raw body;
#   2. the receiver goes away: nothing is lost and nothing hammers it — the
#      circuit opens, the deliveries wait and are retried with a growing wait;
#   3. the receiver comes back: every event arrives, under the same webhook-id it
#      would have had the first time.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

hook=
cleanup() {
  compose start hook-receiver >/dev/null 2>&1 || true
  [ -z "$hook" ] || curl -s -o /dev/null -X DELETE "http://localhost:8080/api/webhooks/$hook" -H "authorization: Bearer ${admin:-x}" || true
}
trap cleanup EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
compose start hook-receiver >/dev/null
tag="hook-$(date +%s)"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

new_order() { # N -> order id
  curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
    -H "authorization: Bearer $admin" \
    -d "{\"customer_email\":\"$tag-$1@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" \
    | sed -n 's/.*"id":\([0-9]*\).*/\1/p'
}
received() { compose logs --no-log-prefix hook-receiver 2>/dev/null | grep "|evt_order_created_$1|" || true; }

echo "registering a receiver:"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/webhooks \
  -H 'content-type: application/json' -d '{"url":"http://hook-receiver/hook","events":["order.created"]}')
[ "$code" = 401 ] || fail "registering without a login answered $code, want 401"
created=$(curl -s -X POST http://localhost:8080/api/webhooks -H 'content-type: application/json' \
  -H "authorization: Bearer $admin" -d '{"url":"http://hook-receiver/hook","events":["order.created"]}')
hook=$(echo "$created" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
secret=$(echo "$created" | sed -n 's/.*"secret":"\([^"]*\)".*/\1/p')
[ -n "$hook" ] && [ -n "$secret" ] || fail "the endpoint was not created: $created"
ok "an admin registered it (endpoint $hook); the secret was shown once"
curl -s http://localhost:8080/api/webhooks -H "authorization: Bearer $admin" | grep -q "$secret" && fail "the secret is in the list"
ok "and it is not in the list afterwards"

echo "orders while the receiver is up:"
ids=""
for i in 1 2 3 4 5; do ids="$ids $(new_order up$i)"; done
for id in $ids; do
  for _ in $(seq 1 30); do [ -n "$(received "$id")" ] && break; sleep 1; done
  lines=$(received "$id")
  [ "$(echo "$lines" | grep -c .)" = 1 ] || fail "order $id was received $(echo "$lines" | grep -c .) times, want 1"
  ts=$(echo "$lines" | cut -d'|' -f3)
  sig=$(echo "$lines" | cut -d'|' -f4)
  body=$(echo "$lines" | cut -d'|' -f5-)
  want="v1,$(printf '%s' "evt_order_created_$id.$ts.$body" | openssl dgst -sha256 -hmac "$secret" -binary | base64)"
  [ "$sig" = "$want" ] || fail "order $id: the signature does not match ($sig, want $want)"
  echo "$body" | grep -q "\"order_id\":$id" || fail "order $id: the body is not about this order: $body"
done
ok "5 orders: each received once, and each signature recomputes from the secret and the raw body"

echo "the receiver goes away:"
compose stop hook-receiver >/dev/null 2>&1
down_ids=""
for i in 1 2 3 4 5 6; do down_ids="$down_ids $(new_order down$i)"; done
opened=""
for _ in $(seq 1 40); do
  for n in node1 node2 node3; do
    s=$(rpc $n 'IO.write(Dandelion.Resilience.state({:webhook, "hook-receiver"}))' 2>/dev/null || true)
    case "$s" in open|half_open) opened="$opened $n:$s" ;; esac
  done
  [ -n "$opened" ] && break
  sleep 1
done
[ -n "$opened" ] || fail "no node opened the circuit for the dead receiver"
ok "the circuit for it opened on:$opened — callers stop waiting on it"
waiting=$(rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM oban_jobs WHERE worker = 'App.Webhooks.Workers.Deliver' AND state IN ('retryable','scheduled','available','executing') AND args->>'event_id' LIKE 'evt_order_created_%'\"); IO.write(n)")
[ "$waiting" -ge 6 ] || fail "only $waiting deliveries are waiting, want at least 6"
ok "$waiting deliveries are waiting to be retried (none lost, none given up)"

echo "the receiver comes back:"
compose start hook-receiver >/dev/null
for id in $down_ids; do
  for _ in $(seq 1 90); do [ -n "$(received "$id")" ] && break; sleep 1; done
  [ -n "$(received "$id")" ] || fail "order $id was never delivered after the receiver came back"
done
ok "all 6 orders made while it was away arrived"
for id in $down_ids; do
  lines=$(received "$id")
  ts=$(echo "$lines" | head -1 | cut -d'|' -f3)
  sig=$(echo "$lines" | head -1 | cut -d'|' -f4)
  body=$(echo "$lines" | head -1 | cut -d'|' -f5-)
  want="v1,$(printf '%s' "evt_order_created_$id.$ts.$body" | openssl dgst -sha256 -hmac "$secret" -binary | base64)"
  [ "$sig" = "$want" ] || fail "order $id: the signature of the late delivery does not match"
done
ok "each under its own webhook-id, and signed: the retry is the same event, not a new one"
echo "webhook proof passed"
