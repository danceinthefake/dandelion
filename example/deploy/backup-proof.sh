#!/bin/sh
# A lost machine can be rebuilt from a backup (compose.cluster.yaml must be up; needs curl,
# sha256sum). The cluster is filled and kept busy making orders, backed up while it works
# (backup.sh), then destroyed: containers, Postgres and the uploads volume (`down -v`).
# restore.sh rebuilds it from the backup alone, and:
#
#   1. the backup is one snapshot: every order in it has all of its events queued, and nothing
#      in it is a half-made order, though orders were being made while it was taken;
#   2. nothing is invented: every order that came back is, byte for byte, an order the cluster
#      had made, and none came back that the cluster never made;
#   3. what the people had comes back: the customer's password still signs in, the product is
#      found by search, the flag is set, the audit log has its entries (and is still append-only),
#      the uploaded file downloads with the same checksum;
#   4. work in flight is not lost or doubled: the events of the restored orders all complete
#      (each once, per subscriber), and the idempotency key of an order made before the backup
#      still returns that order;
#   5. the cluster is a cluster again, and takes new orders with ids after the old ones.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
psql_() { compose exec -T postgres psql -U postgres -d acme -At -c "$1"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

work=$(mktemp -d)
backup=$work/backup
touch "$work/load"
trap 'rm -f "$work/load"; for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1 || true; done' EXIT

wait_cluster() {
  for n in node1 node2 node3; do
    for _ in $(seq 1 120); do
      [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null || true)" = 2 ] && break
      sleep 1
    done
  done
}
wait_cluster
./seed.sh >/dev/null
SUBS=$(rpc node1 'IO.write(length(Platform.PubSub.subscriptions()["order.created"]))')
tag="bk-$(date +%s)"

login() { # EMAIL PASSWORD -> token
  curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}
json() { # METHOD PATH TOKEN BODY [header] -> body, then status on the last line
  curl -s -m 20 -w '\n%{http_code}' -X "$1" "http://localhost:8080$2" -H 'content-type: application/json' \
    -H "authorization: Bearer $3" ${5:+-H "$5"} -d "$4"
}
admin=$(login admin@example.com local-password-1)
[ -n "$admin" ] || fail "can't log in as the seeded admin"

echo "what people have made:"
pw="backup pass $tag"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/users -H 'content-type: application/json' \
  -d "{\"email\":\"$tag@example.com\",\"password\":\"$pw\"}")" = 201 ] || fail "can't register the customer"
cust=$(login "$tag@example.com" "$pw")
[ -n "$cust" ] || fail "the customer can't sign in"

sku="BK-$tag"
out=$(json POST /api/products "$admin" "{\"sku\":\"$sku\",\"name\":\"Backup $tag\",\"price_cents\":900,\"description\":\"harvested at dawn $tag\"}")
[ "$(echo "$out" | tail -n 1)" = 201 ] || fail "creating the product answered: $out"
out=$(json PUT /api/flags/backup.marker "$admin" "{\"value\":\"$tag\"}")
[ "$(echo "$out" | tail -n 1)" = 200 ] || fail "setting the flag answered: $out"

{ printf '\211PNG\r\n\032\n'; head -c 1500000 /dev/urandom; } > "$work/file.png"
sum=$(sha256sum "$work/file.png" | cut -d' ' -f1)
out=$(curl -s -m 30 -w '\n%{http_code}' -X POST http://localhost:8080/api/files -H "authorization: Bearer $cust" \
  -F "file=@$work/file.png;filename=keep.png;type=image/png")
[ "$(echo "$out" | tail -n 1)" = 201 ] || fail "uploading answered: $out"
file_id=$(echo "$out" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)

out=$(json POST /api/orders "$cust" "{\"customer_email\":\"$tag@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":2}]}" "idempotency-key: $tag-first")
order_id=$(echo "$out" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
[ -n "$order_id" ] || fail "the first order was not made: $out"
ok "a customer with a password, a product, a flag, a 1.5 MB file and an order (#$order_id)"

echo "a backup taken while the cluster is busy:"
first_load=$(psql_ "SELECT coalesce(max(id), 0) + 1 FROM orders")
for w in 1 2 3 4; do
  (
    i=0
    while [ -e "$work/load" ]; do
      i=$((i + 1))
      curl -s -m 10 -o /dev/null -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
        -H "authorization: Bearer $admin" -H "idempotency-key: $tag-load-$w-$i" \
        -d "{\"customer_email\":\"load-$w@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" || true
    done
  ) &
done
sleep 6
./backup.sh "$backup" > "$work/backup.out" 2>&1 || { cat "$work/backup.out" >&2; fail "backup.sh failed"; }
sed 's/^/        /' "$work/backup.out"
sleep 3
rm -f "$work/load"
wait
made=$(psql_ "SELECT count(*) FROM orders WHERE id >= $first_load")
[ "$made" -ge 50 ] || fail "only $made orders were made while backing up: the cluster was not busy"
ok "$made orders made during the backup, and the backup is of a cluster that never stopped"

psql_ "COPY (SELECT id, customer_email, status, total_cents, user_id FROM orders ORDER BY id) TO STDOUT" | sort > "$work/live_orders.txt"
live_count=$(wc -l < "$work/live_orders.txt")
live_max=$(psql_ "SELECT max(id) FROM orders")

echo "the machine is lost:"
compose down -v >/dev/null 2>&1
[ -z "$(docker volume ls -q | grep -E '(^|_)uploads$' || true)" ] || fail "the uploads volume survived"
ok "containers, Postgres and the uploads volume are gone"

echo "rebuilt from the backup alone:"
start=$(date +%s)
./restore.sh "$backup" > "$work/restore.out" 2>&1 || { cat "$work/restore.out" >&2; fail "restore.sh failed"; }
sed 's/^/        /' "$work/restore.out"
wait_cluster
until curl -sf -o /dev/null http://localhost:8080/health 2>/dev/null; do sleep 1; done
ok "three nodes are a cluster again, $(( $(date +%s) - start )) s after the restore started"

restored=$(psql_ "SELECT count(*) FROM orders")
restored_max=$(psql_ "SELECT max(id) FROM orders")
[ "$restored" -ge 20 ] || fail "only $restored orders came back"
[ "$restored" -lt "$live_count" ] || fail "all $live_count orders came back: the cluster was not making orders after the snapshot, so nothing here was taken mid-flow"
ok "$restored orders came back; the cluster had $live_count when it was lost (the rest were made after the snapshot)"

# 1. one snapshot: events queued with each order, items with each order
lacking=$(psql_ "SELECT count(*) FROM orders o WHERE (SELECT count(*) FROM oban_jobs j WHERE j.args->'payload'->>'order_id' = o.id::text) <> $SUBS")
[ "$lacking" = 0 ] || fail "$lacking restored orders do not have their $SUBS queued events: the backup is not a snapshot"
itemless=$(psql_ "SELECT count(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.id)")
[ "$itemless" = 0 ] || fail "$itemless restored orders have no items"
ok "every restored order has its $SUBS events and its items: a snapshot, not a smear"

# 2. nothing invented
psql_ "COPY (SELECT id, customer_email, status, total_cents, user_id FROM orders ORDER BY id) TO STDOUT" | sort > "$work/restored_orders.txt"
invented=$(comm -23 "$work/restored_orders.txt" "$work/live_orders.txt" | wc -l | tr -d ' ')
[ "$invented" = 0 ] || fail "$invented restored orders are not what the cluster made: $(comm -23 "$work/restored_orders.txt" "$work/live_orders.txt" | head -2)"
ok "every restored order is, byte for byte, one the cluster made"

# 3. what people have
admin=$(login admin@example.com local-password-1)
[ -n "$admin" ] || fail "the admin can't sign in after the restore"
cust=$(login "$tag@example.com" "$pw")
[ -n "$cust" ] || fail "the customer's password no longer signs in"
ok "the customer's password signs in (the admin's too)"

found=$(curl -s -G http://localhost:8080/api/search/products --data-urlencode "q=dawn $tag" -H "authorization: Bearer $cust")
echo "$found" | grep -q "$sku" || fail "the product is not found by its description: $found"
ok "the product is found by a word of its description (the search index came back with the table)"

flag=$(curl -s http://localhost:8080/api/flags -H "authorization: Bearer $admin")
echo "$flag" | grep -q "$tag" || fail "the flag is not set: $flag"
ok "the flag has its value"

audit=$(curl -s "http://localhost:8080/api/audit?limit=100" -H "authorization: Bearer $admin")
echo "$audit" | grep -q "product:$sku" || fail "the audit log lacks the product"
echo "$audit" | grep -q "flag:backup.marker" || fail "the audit log lacks the flag"
if psql_ "UPDATE dandelion_audit SET actor = 'someone-else'" 2>/dev/null; then
  fail "an audit entry can be changed after the restore"
fi
ok "the audit log has the product and the flag, and still refuses to be changed"

mkdir -p "$work/dl"
for n in 1 2 3 4 5 6; do
  curl -s -m 20 -o "$work/dl/$n" "http://localhost:8080/api/files/$file_id" -H "authorization: Bearer $cust"
  [ "$(sha256sum "$work/dl/$n" | cut -d' ' -f1)" = "$sum" ] || fail "download $n differs from what was uploaded"
done
ok "the file downloads with the checksum it was uploaded with (6 downloads, all three nodes)"

# 4. work in flight
for _ in $(seq 1 90); do
  open=$(psql_ "SELECT count(*) FROM oban_jobs WHERE args->'payload'->>'order_id' IS NOT NULL AND state NOT IN ('completed','discarded','cancelled')")
  [ "$open" = 0 ] && break
  sleep 1
done
[ "$open" = 0 ] || fail "$open events of the restored orders never completed"
done_each=$(psql_ "SELECT count(*) FROM orders o WHERE (SELECT count(*) FROM oban_jobs j WHERE j.args->'payload'->>'order_id' = o.id::text AND j.state = 'completed') <> $SUBS")
[ "$done_each" = 0 ] || fail "$done_each restored orders have a different number of completed events than the $SUBS subscribers"
ok "the events still in flight when the backup was taken ran: every restored order has $SUBS completed, none doubled"

out=$(json POST /api/orders "$cust" "{\"customer_email\":\"$tag@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":2}]}" "idempotency-key: $tag-first")
[ "$(echo "$out" | tail -n 1)" = 200 ] || fail "the old idempotency key answered $(echo "$out" | tail -n 1), want 200"
echo "$out" | grep -q "\"id\":$order_id" || fail "the old key returned another order: $out"
ok "the idempotency key of the order made before the backup still returns order #$order_id"

# 5. new work
# (a busy Postgres can answer 503 for a moment; a client asks again with the same key, as designed)
for _ in 1 2 3 4 5 6; do
  out=$(json POST /api/orders "$cust" "{\"customer_email\":\"$tag@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}" "idempotency-key: $tag-after")
  case $(echo "$out" | tail -n 1) in 201|200) break ;; esac
  sleep 2
done
case $(echo "$out" | tail -n 1) in 201|200) ;; *) fail "a new order answered $(echo "$out" | tail -n 1)" ;; esac
new_id=$(echo "$out" | sed -n 's/.*"id":\([0-9]*\).*/\1/p' | head -1)
[ "$new_id" -gt "$restored_max" ] || fail "the new order has id $new_id, not after the restored ones (up to $restored_max): a sequence went back"
ok "a new order is #$new_id, after the restored ones (up to #$restored_max)"

echo "backup proof passed"
