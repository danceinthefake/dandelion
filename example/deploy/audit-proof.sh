#!/bin/sh
# Who did what, on the 3-node cluster (compose.cluster.yaml must be up; needs curl).
# Admin and customer actions go through the load balancer, so different nodes make them:
#
#   1. every change is in ONE log, with its actor, what changed (from and to), and the
#      request id of the request that made it — the id the response carried, so an entry
#      can be matched to the logs and the trace;
#   2. a change that was refused leaves no entry; a secret is in no entry;
#   3. the log cannot be rewritten: an UPDATE, a DELETE and a TRUNCATE are all refused
#      by the database, whichever node asks.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
tag="audit-$(date +%s)"
hdr=$(mktemp)

login() { # EMAIL PASSWORD -> token
  curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}
admin=$(login admin@example.com local-password-1)
[ -n "$admin" ] || fail "can't log in as the seeded admin"
admin_id=$(curl -s http://localhost:8080/api/me -H "authorization: Bearer $admin" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')

# api METHOD PATH [BODY] -> status; response headers in $hdr, body in $body_file
body_file=$(mktemp)
api() {
  m=$1; path=$2; shift 2
  if [ $# -gt 0 ]; then
    curl -s -o "$body_file" -D "$hdr" -w '%{http_code}' -X "$m" "http://localhost:8080$path" \
      -H 'content-type: application/json' -H "authorization: Bearer $admin" -d "$1"
  else
    curl -s -o "$body_file" -D "$hdr" -w '%{http_code}' -X "$m" "http://localhost:8080$path" \
      -H "authorization: Bearer $admin"
  fi
}
request_id() { grep -i '^x-request-id' "$hdr" | tr -d '\r' | sed 's/^[^:]*: *//'; }
upstream() { grep -i '^x-upstream' "$hdr" | tr -d '\r' | sed 's/^[^:]*: *//'; }
log_json() { curl -s "http://localhost:8080/api/audit?$1" -H "authorization: Bearer $admin"; }

echo "making changes through the load balancer:"
: > "$hdr.up"
[ "$(api PUT /api/flags/audit.$tag '{"value":"on"}')" = 200 ] || fail "setting a flag"
flag_rid=$(request_id); upstream >> "$hdr.up"
[ "$(api PUT /api/flags/audit.$tag '{"value":"off"}')" = 200 ] || fail "setting a flag again"
upstream >> "$hdr.up"
code=$(api POST /api/webhooks '{"url":"https://hooks.example.com/audit","events":["order.created"]}')
[ "$code" = 201 ] || fail "registering a webhook answered $code"
hook=$(sed -n 's/.*"id":\([0-9]*\).*/\1/p' "$body_file"); secret=$(sed -n 's/.*"secret":"\([^"]*\)".*/\1/p' "$body_file")
upstream >> "$hdr.up"
[ "$(api DELETE /api/webhooks/$hook)" = 204 ] || fail "deleting the webhook"
upstream >> "$hdr.up"
[ "$(api PUT /api/products/PROOF '{"price_cents":123}')" = 200 ] || fail "changing a price"
upstream >> "$hdr.up"
[ "$(api PUT /api/products/PROOF '{"price_cents":100}')" = 200 ] || fail "changing the price back"
[ "$(api DELETE /api/flags/audit.$tag)" = 204 ] || fail "unsetting the flag"
upstream >> "$hdr.up"
nodes=$(sort -u "$hdr.up" | grep -c . || true)
ok "7 changes made as the admin, answered by $nodes different node(s)"

register_status=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/users -H 'content-type: application/json' \
  -d "{\"email\":\"$tag@example.com\",\"password\":\"correct horse battery\"}")
[ "$register_status" = 201 ] || fail "registering answered $register_status"
curl -s -o /dev/null -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d "{\"email\":\"$tag@example.com\",\"password\":\"wrong password 1\"}"
cust=$(login "$tag@example.com" "correct horse battery")
cust_id=$(curl -s http://localhost:8080/api/me -H "authorization: Bearer $cust" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
oid=$(curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' -H "authorization: Bearer $cust" \
  -d "{\"customer_email\":\"$tag@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
curl -s -o /dev/null -X POST "http://localhost:8080/api/orders/$oid/cancel" -H "authorization: Bearer $cust"
ok "and a customer registered, failed a login, logged in, ordered and cancelled"

echo "what the log says:"
mine=$(log_json "actor=user:$admin_id&limit=200")
echo "$mine" | grep -q "\"action\":\"flag.set\"" || fail "no flag.set entry"
for a in flag.set flag.deleted webhook.created webhook.deleted product.price_changed; do
  echo "$mine" | grep -q "\"action\":\"$a\"" || fail "no $a entry for the admin"
done
ok "the admin's flag, webhook and price changes are there, under user:$admin_id"
echo "$mine" | grep -q '"from":100,"to":123\|"to":123,"from":100' || fail "the price change doesn't say from 100 to 123: $(echo "$mine" | grep -o 'product.price_changed.\{0,120\}' | head -1)"
ok "the price change says what it was and what it became: 100 to 123"
echo "$mine" | grep -q "\"request_id\":\"$flag_rid\"" || fail "the flag entry doesn't carry the request id the response had ($flag_rid)"
ok "an entry carries the request id of the request that made it ($flag_rid): the same one the response had"

theirs=$(log_json "actor=user:$cust_id&limit=50")
for a in order.cancelled session.created; do
  echo "$theirs" | grep -q "\"action\":\"$a\"" || fail "no $a entry for the customer"
done
echo "$theirs" | grep -q "\"subject\":\"order:$oid\"" || fail "the cancel is not about order $oid"
ok "the customer's login and cancel are there, under user:$cust_id, about order $oid"
rejected=$(log_json "action=session.rejected&limit=5")
echo "$rejected" | grep -q "\"subject\":\"email:$tag@example.com\"" || fail "the failed login is not in the log"
ok "the failed login is there (actor anonymous, the email typed)"
registered=$(log_json "action=user.registered&limit=20")
echo "$registered" | grep -q "\"actor\":\"user:$cust_id\"" || fail "the registration is not in the log"
ok "and the registration"

whole=$(log_json "limit=200")
if echo "$whole" | grep -q "$secret"; then fail "a webhook secret is in the log"; fi
if echo "$whole" | grep -q "correct horse\|wrong password"; then fail "a password is in the log"; fi
ok "no webhook secret and no password in any entry"

echo "a refused change leaves nothing:"
before=$(log_json "limit=200" | grep -o '"id":[0-9]*' | wc -l | tr -d ' ')
[ "$(api PUT /api/products/PROOF '{"price_cents":-5}')" = 422 ] || fail "a negative price was not refused"
[ "$(api PUT /api/products/NOPE '{"price_cents":5}')" = 404 ] || fail "an unknown product was not 404"
[ "$(api PUT /api/flags/Bad%20Key '{"value":1}')" = 400 ] || fail "a bad flag key was not 400"
after=$(log_json "limit=200" | grep -o '"id":[0-9]*' | wc -l | tr -d ' ')
[ "$before" = "$after" ] || fail "refused changes added $((after - before)) entries"
ok "three refused changes (422, 404, 400): not one entry"

echo "the log cannot be rewritten:"
for n in node1 node2 node3; do
  for sql in "UPDATE dandelion_audit SET actor = 'someone-else'" "DELETE FROM dandelion_audit" "TRUNCATE dandelion_audit"; do
    out=$(rpc $n "case Platform.Database.Repo.query(\"$sql\") do {:error, %Postgrex.Error{postgres: %{message: m}}} -> IO.write(m); {:ok, _} -> IO.write(\"ACCEPTED\") end")
    case "$out" in *append-only*) ;; *) fail "$n: '$sql' answered: $out" ;; esac
  done
done
ok "from every node, an UPDATE, a DELETE and a TRUNCATE are refused: dandelion_audit is append-only"
left=$(log_json "actor=user:$admin_id&limit=200" | grep -c '"action":"flag.set"' || true)
[ "$left" -ge 1 ] || fail "the entries are gone"
ok "and the entries are still there"
echo "audit proof passed"
