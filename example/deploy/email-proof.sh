#!/bin/sh
# Mail on the 3-node cluster (compose.cluster.yaml must be up; needs curl). Each new order
# emails its customer; the mail server is mailpit (http://localhost:18025 shows what it got):
#
#   1. every order's confirmation arrives at the mail server exactly once, with the order
#      number and total in it;
#   2. the mail server goes away: orders are still accepted at once (an order never waits
#      for mail), the circuit for the server opens, and the messages wait, written down;
#   3. it comes back: every message arrives, exactly once;
#   4. the job is run again for an order already mailed (it is at-least-once): no second mail.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
MAILPIT=http://localhost:18025

restore() { compose start mailpit >/dev/null 2>&1 || true; }
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
compose start mailpit >/dev/null
for _ in $(seq 1 30); do curl -sf "$MAILPIT/api/v1/info" >/dev/null && break; sleep 1; done
tag="mail-$(date +%s)"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

new_order() { # NAME -> prints "ID"; the customer's address is $tag-NAME@example.com
  curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
    -H "authorization: Bearer $admin" \
    -d "{\"customer_email\":\"$tag-$1@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" \
    | sed -n 's/.*"id":\([0-9]*\).*/\1/p'
}
# how many messages the mail server holds for this customer
received() { curl -s "$MAILPIT/api/v1/search?query=to%3A$tag-$1%40example.com" | sed -n 's/.*"messages_count":\([0-9]*\).*/\1/p'; }
until_received() { # NAME COUNT SECONDS
  for _ in $(seq 1 "$3"); do
    [ "$(received "$1" 2>/dev/null)" = "$2" ] && return 0
    sleep 1
  done
  return 1
}

echo "orders while the mail server is up:"
ids=""
for i in 1 2 3 4 5 6; do ids="$ids $(new_order up$i)"; done
for i in 1 2 3 4 5 6; do until_received up$i 1 60 || fail "up$i: $(received up$i) message(s) arrived, want 1"; done
sleep 5
for i in 1 2 3 4 5 6; do [ "$(received up$i)" = 1 ] || fail "up$i: $(received up$i) messages after waiting, want exactly 1"; done
first=$(echo $ids | cut -d' ' -f1)
msg_id=$(curl -s "$MAILPIT/api/v1/search?query=to%3A$tag-up1%40example.com" | sed -n 's/.*"messages":\[{"ID":"\([^"]*\)".*/\1/p')
text=$(curl -s "$MAILPIT/api/v1/message/$msg_id")
echo "$text" | grep -q "Your order #$first" || fail "the subject doesn't name order $first"
echo "$text" | grep -q "Total: 1.00" || fail "the body doesn't have the total"
ok "6 orders: 6 confirmations arrived, each once, naming the order ($first …) and the total"

echo "the mail server goes away:"
compose stop mailpit >/dev/null 2>&1
down_ids=""
start=$(date +%s)
for i in 1 2 3 4 5 6; do down_ids="$down_ids $(new_order down$i)"; done
took=$(( $(date +%s) - start ))
[ -n "$(echo $down_ids | tr -d ' ')" ] || fail "orders were not accepted while the mail server was down"
[ "$(echo $down_ids | wc -w | tr -d ' ')" = 6 ] || fail "only some orders were accepted while the mail server was down"
ok "6 orders accepted in $took s with the mail server down: an order never waits for mail"
opened=""
for _ in $(seq 1 60); do
  for n in node1 node2 node3; do
    s=$(rpc $n 'IO.write(Dandelion.Resilience.state({:smtp, "mailpit"}))' 2>/dev/null || true)
    case "$s" in open|half_open) opened="$opened $n:$s" ;; esac
  done
  [ -n "$opened" ] && break
  sleep 1
done
[ -n "$opened" ] || fail "no node opened the circuit for the dead mail server"
ok "the circuit for it opened on:$opened — workers stop waiting on it"
queued=$(rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM outgoing_emails WHERE status = 'queued' AND to_address LIKE '$tag-down%'\"); IO.write(n)")
[ "$queued" = 6 ] || fail "$queued messages are waiting, want 6"
ok "6 messages are waiting, written down in outgoing_emails (queued)"

echo "the mail server comes back:"
compose start mailpit >/dev/null
for _ in $(seq 1 30); do curl -sf "$MAILPIT/api/v1/info" >/dev/null && break; sleep 1; done
for i in 1 2 3 4 5 6; do until_received down$i 1 150 || fail "down$i: $(received down$i) message(s) arrived after it came back, want 1"; done
sleep 5
for i in 1 2 3 4 5 6; do [ "$(received down$i)" = 1 ] || fail "down$i: $(received down$i) messages after waiting, want exactly 1"; done
ok "all 6 arrived, each exactly once"
for i in 1 2 3 4 5 6; do [ "$(received up$i)" = 1 ] || fail "up$i changed: $(received up$i) messages"; done
ok "and the first 6 are still just one each"
left=$(rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM outgoing_emails WHERE status <> 'sent' AND to_address LIKE '$tag-%'\"); IO.write(n)")
[ "$left" = 0 ] || fail "$left messages are not marked sent"
ok "every message is marked sent"

echo "the job runs again:"
first_down=$(echo $down_ids | cut -d' ' -f1)
for id in $first $first_down; do
  [ "$(rpc node2 "IO.write(App.Shop.Workers.SendOrderConfirmation.perform(%Oban.Job{args: %{\"payload\" => %{\"order_id\" => $id}}}))")" = ok ] || fail "running the job again for order $id did not answer ok"
done
sleep 3
[ "$(received up1)" = 1 ] && [ "$(received down1)" = 1 ] || fail "running the job again mailed a second time"
ok "the job run again for two orders already mailed sent nothing: still one each"
echo "email proof passed"
