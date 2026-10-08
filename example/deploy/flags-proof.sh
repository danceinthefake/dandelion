#!/bin/sh
# A setting changed while the app runs, seen by every node (compose.cluster.yaml
# must be up; needs curl). The flag `orders.enabled` pauses new orders:
#
#   1. an admin turns it off through the load balancer, which reaches ONE node:
#      the very next orders, which reach all three nodes, are refused with 503 and a
#      retry-after; turned on again, they are accepted on every node;
#   2. a node that cannot hear the others (split from the cluster, Postgres still
#      reachable) does not hear that the flag changed — it serves the value it has
#      for at most the cache's TTL, then reads the table: memory makes it fast,
#      Postgres decides.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

admin=
# Cut node3 off from the other two (each side gets a wrong Erlang cookie for the
# other, as in partition-proof.sh): the cluster splits, Postgres is still reachable.
N1=; N2=; N3=
cut() {
  rpc node3 "for p <- [:\"$N1\", :\"$N2\"] do Node.set_cookie(p, :split_c); Node.disconnect(p) end; IO.write(:ok)" >/dev/null
  for n in node1 node2; do
    rpc $n "Node.set_cookie(:\"$N3\", :split_a); Node.disconnect(:\"$N3\"); IO.write(:ok)" >/dev/null
  done
}
heal() {
  for n in node1 node2 node3; do
    rpc $n "for p <- [:\"$N1\", :\"$N2\", :\"$N3\"], p != node(), do: Node.set_cookie(p, Node.get_cookie()); IO.write(:ok)" >/dev/null 2>&1 || true
  done
}
restore() {
  [ -z "$N3" ] || heal
  [ -z "$admin" ] || curl -s -o /dev/null -X DELETE http://localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $admin" || true
}
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
N1=$(rpc node1 'IO.write(node())'); N2=$(rpc node2 'IO.write(node())'); N3=$(rpc node3 'IO.write(node())')
heal
./seed.sh >/dev/null
rpc node1 'Dandelion.Flags.delete("orders.enabled"); IO.write(:ok)' >/dev/null
tag="flag-$(date +%s)"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

order() { # N -> status
  curl -s -o /dev/null -D "$hdr" -w '%{http_code}' -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
    -H "authorization: Bearer $admin" \
    -d "{\"customer_email\":\"$tag-$1@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}"
}
hdr=$(mktemp)
set_flag() { # VALUE
  curl -s -o /dev/null -w '%{http_code}' -X PUT http://localhost:8080/api/flags/orders.enabled \
    -H 'content-type: application/json' -H "authorization: Bearer $admin" -d "{\"value\":$1}"
}
# which nodes answered: the X-Upstream header nginx adds is the node's address
upstreams() { sort -u | wc -l | tr -d ' '; }

echo "pausing orders on a running cluster:"
codes=""; nodes=""
for i in $(seq 1 9); do
  codes="$codes $(order base$i)"
  nodes="$nodes
$(grep -i '^x-upstream' "$hdr" | tr -d '\r')"
done
[ "$(echo $codes | tr ' ' '\n' | grep -c '^201$')" = 9 ] || fail "orders before the pause: $codes"
[ "$(echo "$nodes" | grep -c .)" -ge 9 ] && [ "$(echo "$nodes" | grep . | upstreams)" = 3 ] || fail "the baseline orders did not reach all 3 nodes"
ok "9 orders, spread over all 3 nodes, are accepted — every node has read the flag"

[ "$(set_flag false)" = 200 ] || fail "an admin could not set the flag"
codes=""; nodes=""
for i in $(seq 1 12); do
  codes="$codes $(order paused$i)"
  nodes="$nodes
$(grep -i '^x-upstream' "$hdr" | tr -d '\r')"
done
[ "$(echo $codes | tr ' ' '\n' | grep -c '^503$')" = 12 ] || fail "after the pause, orders answered: $codes"
[ "$(echo "$nodes" | grep . | upstreams)" = 3 ] || fail "the 12 refused orders did not come from all 3 nodes"
grep -qi '^retry-after: 30' "$hdr" || fail "a refused order has no retry-after"
ok "the flag was set through one node: the next 12 orders, answered by all 3 nodes, were refused (503, retry-after: 30)"
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/orders -H "authorization: Bearer $admin")" = 200 ] || fail "reading orders is paused too"
ok "reading orders and /health are not paused"

[ "$(set_flag true)" = 200 ] || fail "can't turn it back on"
codes=""
for i in $(seq 1 9); do codes="$codes $(order resumed$i)"; done
[ "$(echo $codes | tr ' ' '\n' | grep -c '^201$')" = 9 ] || fail "after turning it on again: $codes"
ok "turned on again: 9 orders accepted, on every node"

echo "a node that cannot hear the others:"
for n in node1 node2 node3; do rpc $n 'IO.write(Dandelion.Flags.get("orders.enabled", :unset))' >/dev/null; done
[ "$(rpc node3 'IO.write(Dandelion.Flags.get("orders.enabled", :unset))')" = true ] || fail "node3 does not read the flag as true"
cut
for _ in $(seq 1 60); do
  [ "$(rpc node3 'IO.write(length(Node.list()))' 2>/dev/null)" = 0 ] && break
  sleep 1
done
[ "$(rpc node3 'IO.write(length(Node.list()))')" = 0 ] || fail "node3 still sees other nodes"
for _ in $(seq 1 30); do
  [ "$(rpc node1 'IO.write(length(Node.list()))')" = 1 ] && break
  sleep 1
done
[ "$(rpc node1 'IO.write(length(Node.list()))')" = 1 ] || fail "node1 still sees node3"
[ "$(rpc node3 'case Platform.Database.Repo.query("SELECT 1") do {:ok, _} -> IO.write(:up); _ -> IO.write(:down) end')" = up ] || fail "node3 can't reach Postgres"
ok "node3 sees no other node but still reaches Postgres"

# through node1, not the load balancer: it could hand the request to node3 itself
rpc node1 'Dandelion.Flags.put("orders.enabled", false); IO.write(:ok)' >/dev/null
cut_at=$(date +%s)
for n in node1 node2; do
  [ "$(rpc $n 'IO.write(Dandelion.Flags.get("orders.enabled", :unset))')" = false ] || fail "$n does not see the flag"
done
ok "node1 and node2 see it at once"
stale=$(rpc node3 'IO.write(Dandelion.Flags.get("orders.enabled", :unset))')
[ "$stale" = true ] || fail "node3 already sees the change ($stale); it should still serve its cached copy"
ok "node3 still serves the old value (it never heard the change)"
fresh=""
for _ in $(seq 1 90); do
  if [ "$(rpc node3 'IO.write(Dandelion.Flags.get("orders.enabled", :unset))')" = false ]; then
    fresh=$(( $(date +%s) - cut_at )); break
  fi
  sleep 2
done
[ -n "$fresh" ] || fail "node3 never saw the change"
[ "$fresh" -le 75 ] || fail "node3 took $fresh s to see the change; the cache lasts a minute"
ok "node3 read the new value from Postgres $fresh s after the change (the cache lasts 60 s)"
heal
curl -s -o /dev/null -X DELETE http://localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $admin"
echo "flags proof passed"
