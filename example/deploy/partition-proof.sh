#!/bin/sh
# A network partition, on the 3-node cluster (compose.cluster.yaml must be up):
#
#   node1 | node2 + node3      the halves can't reach each other,
#                              but both can still reach Postgres
#
# The split is made without any privileges: each side is given a wrong Erlang
# cookie for the other side's nodes (a different wrong one on each side, or they
# would match) and drops the connection; healing puts the right cookie back. Checks what DESIGN §10.3 says about a split:
#   - live broadcasts don't cross it (fire and forget)
#   - a cache on the cut-off side goes stale, and is emptied when the halves
#     meet again
#   - jobs, events and ordered payments still run exactly once, through Postgres
#   - there is still exactly one cron leader
#   - presence: each half sees its own viewers; they merge after the heal
#   - the same split five times in a row (flapping): everything still converges
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

# wait until all three nodes answer, and have found each other (90 s at most)
for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done

# the node names, and the product used by the cache checks
N1=$(rpc node1 'IO.write(node())')
N2=$(rpc node2 'IO.write(node())')
N3=$(rpc node3 'IO.write(node())')
sku="SPLIT-$(date +%s)"
sku2="SPLIT2-$(date +%s)"
tag="split-$(date +%s)"

# ex NODE: runs the Elixir code on stdin on NODE (__N1__ … __SKU__ filled in)
ex() {
  code=$(sed -e "s/__N1__/$N1/g" -e "s/__N2__/$N2/g" -e "s/__N3__/$N3/g" \
             -e "s/__SKU2__/$sku2/g" -e "s/__SKU__/$sku/g" -e "s/__TAG__/$tag/g")
  rpc "$1" "$code"
}
# until CMD EXPECTED SECONDS: until CMD prints EXPECTED
until_is() {
  for _ in $(seq 1 "$3"); do
    [ "$($1 2>/dev/null)" = "$2" ] && return 0
    sleep 1
  done
  return 1
}
# the other two nodes, sorted, as nodes_seen prints them
others() {
  case $1 in
    node1) a=$N2; b=$N3 ;;
    node2) a=$N1; b=$N3 ;;
    node3) a=$N1; b=$N2 ;;
  esac
  printf '%s\n%s\n' "$a" "$b" | sort | tr '\n' ' ' | sed 's/ $//'
}
nodes_seen() { rpc "$1" 'IO.write(Enum.join(Enum.sort(Node.list()), " "))'; }
viewers() { rpc "$1" 'IO.write(map_size(Platform.Realtime.Presence.list("partition-proof")))'; }
leaders() {
  n=0
  for node in node1 node2 node3; do
    [ "$(rpc $node 'IO.write(Oban.Peer.leader?())')" = true ] && n=$((n + 1))
  done
  echo $n
}
price_on() { rpc "$1" "{:ok, p} = App.Shop.Services.ProductService.get(\"$2\"); IO.write(p.price_cents)"; }
cached_on() { rpc "$1" "IO.write(elem(Cachex.exists?(Dandelion.Cache, {:product, \"$2\"}), 1))"; }

./seed.sh >/dev/null
for s in "$sku:1500" "$sku2:900"; do
  rpc node1 "Platform.Database.Repo.insert!(%App.Shop.Models.Product{sku: \"${s%%:*}\", name: \"Split\", price_cents: ${s##*:}})" >/dev/null
done

echo "before the split:"
for n in node1 node2 node3; do
  until_is "nodes_seen $n" "$(others $n)" 40 || fail "$n doesn't see the other two nodes"
done
ok "three nodes, each sees the other two"
for n in node1 node2 node3; do
  ex $n <<'ELIXIR' >/dev/null
spawn(fn ->
  {:ok, _} = Platform.Realtime.Presence.track(self(), "partition-proof", "viewer-" <> Atom.to_string(node()), %{})
  Process.sleep(:infinity)
end)
IO.write(:ok)
ELIXIR
done
for n in node1 node2 node3; do until_is "viewers $n" 3 30 || fail "$n doesn't see 3 viewers: $(viewers $n)"; done
ok "presence: 3 viewers (one per node), visible on every node"
[ "$(leaders)" = 1 ] || fail "want exactly one cron leader before the split, got $(leaders)"
ok "exactly one cron leader (Oban, through Postgres)"
for n in node1 node2 node3; do [ "$(price_on $n $sku)" = 1500 ] || fail "$n doesn't read the price"; done
ok "$sku read on all 3 nodes: each caches 1500"

echo "during the split:"
# a collector on node2 for live broadcasts, started before the split
ex node2 <<'ELIXIR' >/dev/null
collector = spawn(fn ->
  Phoenix.PubSub.subscribe(Platform.Broadcast, "partition-proof-bc")
  loop = fn loop, got ->
    receive do
      {:get, from} -> send(from, {:got, got}); loop.(loop, got)
      msg -> loop.(loop, [msg | got])
    end
  end
  loop.(loop, [])
end)
Process.register(collector, :bc_collector)
IO.write(:ok)
ELIXIR
split_at=$(date +%s)
ex node1 <<'ELIXIR' >/dev/null
for p <- [:"__N2__", :"__N3__"] do
  Node.set_cookie(p, :split_a)
  Node.disconnect(p)
end
IO.write(:ok)
ELIXIR
for n in node2 node3; do
  ex $n <<'ELIXIR' >/dev/null
Node.set_cookie(:"__N1__", :split_b)
Node.disconnect(:"__N1__")
IO.write(:ok)
ELIXIR
done
until_is "nodes_seen node1" "" 20 || fail "node1 still sees nodes: $(nodes_seen node1)"
until_is "nodes_seen node2" "$N3" 20 || fail "node2 sees: $(nodes_seen node2) (want just $N3)"
until_is "nodes_seen node3" "$N2" 20 || fail "node3 sees: $(nodes_seen node3) (want just $N2)"
ok "split: node1 alone | node2 + node3 together (both halves still reach Postgres)"

# a live broadcast on node1 doesn't reach node2's side
rpc node1 'Phoenix.PubSub.broadcast(Platform.Broadcast, "partition-proof-bc", {:hello, node()}); IO.write(:sent)' >/dev/null
sleep 2
got=$(rpc node2 'send(:bc_collector, {:get, self()}); receive do {:got, g} -> IO.write(length(g)) after 3000 -> IO.write("none") end')
[ "$got" = 0 ] || fail "a broadcast on node1 reached node2 during the split ($got)"
ok "a live broadcast on node1 did not reach node2 (fire and forget: lost across a split)"

# the price is changed on node2's side: node3 hears, node1 can't
rpc node2 "{:ok, _} = App.Shop.Services.ProductService.update_price(\"$sku\", %{\"price_cents\" => 1700}); IO.write(:ok)" >/dev/null
[ "$(price_on node2 $sku)" = 1700 ] || fail "node2 doesn't read the new price"
until_is "price_on node3 $sku" 1700 10 || fail "node3 (same half) still reads $(price_on node3 $sku)"
[ "$(price_on node1 $sku)" = 1500 ] || fail "node1 reads $(price_on node1 $sku), want the stale 1500"
ok "price changed on node2's side: node2 and node3 read 1700, cut-off node1 still serves the old 1500"

# jobs and events go through Postgres, which both halves reach
for i in 1 2 3 4 5; do
  for n in node1 node2; do
    ex $n <<'ELIXIR' >/dev/null
{:ok, _} = App.Shop.Services.OrderService.create(%{
  "customer_email" => "__TAG__-#{System.unique_integer([:positive])}@example.com",
  "items" => [%{"sku" => "A", "quantity" => 1}]
})
IO.write(:ok)
ELIXIR
  done
done
subs() {
  ex node1 <<'ELIXIR'
import Ecto.Query
rows = Platform.Database.Repo.all(from j in Oban.Job,
  where: j.state == "completed" and fragment("args->>'topic' = 'order.created' AND args->'payload'->>'customer_email' LIKE '__TAG__-%'"),
  select: j.attempt)
IO.write("#{length(rows)} #{Enum.max(rows, fn -> 0 end)}")
ELIXIR
}
until_is subs "20 1" 60 || fail "10 orders made on both sides: want 20 subscriber jobs completed in 1 attempt each, got '$(subs)'"
ok "10 orders made on both sides: 20 subscriber jobs, each completed once (1 attempt)"

[ "$(leaders)" = 1 ] || fail "want exactly one cron leader during the split, got $(leaders)"
ok "still exactly one cron leader during the split"

# payment, then refund, sent through different halves: order is kept
rpc node1 'Oban.pause_queue(queue: :ordered); IO.write(:ok)' >/dev/null
oid=$(ex node1 <<'ELIXIR'
{:ok, o} = App.Shop.Services.OrderService.create(%{"customer_email" => "__TAG__-pay@example.com", "items" => [%{"sku" => "A", "quantity" => 1}]})
IO.write(o.id)
ELIXIR
)
rpc node1 "App.Shop.Services.PaymentService.receive_event(%{\"event_id\" => \"$tag-pay\", \"type\" => \"payment.succeeded\", \"order_id\" => $oid}); IO.write(:ok)" >/dev/null
rpc node2 "App.Shop.Services.PaymentService.receive_event(%{\"event_id\" => \"$tag-refund\", \"type\" => \"payment.refunded\", \"order_id\" => $oid}); IO.write(:ok)" >/dev/null
rpc node1 'Oban.resume_queue(queue: :ordered); IO.write(:ok)' >/dev/null
order_status() { rpc node1 "{:ok, o} = App.Shop.Services.OrderService.get($oid); IO.write(o.status)"; }
until_is order_status refunded 40 || fail "order $oid is $(order_status), want refunded"
ok "order $oid: payment sent on node1's side, refund on node2's side: ran in that order (refunded)"

# warm a second product on node1, so the heal check doesn't depend on a TTL
[ "$(price_on node1 $sku2)" = 900 ] && [ "$(cached_on node1 $sku2)" = true ] || fail "node1 didn't cache $sku2"

echo "presence during the split:"
until_is "viewers node1" 1 60 || fail "node1 sees $(viewers node1) viewers, want its own 1"
until_is "viewers node2" 2 60 || fail "node2 sees $(viewers node2) viewers, want 2 (itself and node3)"
until_is "viewers node3" 2 60 || fail "node3 sees $(viewers node3) viewers, want 2 (itself and node2)"
ok "each half sees only its own viewers: node1 1, node2 2, node3 2"

echo "after the heal:"
healed_at=$(date +%s)
for n in node1 node2 node3; do
  ex $n <<'ELIXIR' >/dev/null
for p <- [:"__N1__", :"__N2__", :"__N3__"], p != node() do
  Node.set_cookie(p, Node.get_cookie())
end
IO.write(:ok)
ELIXIR
done
for n in node1 node2 node3; do
  until_is "nodes_seen $n" "$(others $n)" 90 || fail "$n doesn't see the other two after the heal: $(nodes_seen $n)"
done
ok "the halves found each other again ($(( $(date +%s) - healed_at )) s after the cookies were restored)"

until_is "cached_on node1 $sku2" false 20 || fail "node1 kept $sku2 in its cache after rejoining"
ok "node1's cache was emptied when it rejoined (a fresh entry, not an expired one, was gone)"
[ "$(price_on node1 $sku)" = 1700 ] || fail "node1 reads $(price_on node1 $sku) after the heal, want 1700"
ok "node1 now reads the current price: 1700"

for n in node1 node2 node3; do until_is "viewers $n" 3 90 || fail "$n sees $(viewers $n) viewers after the heal, want 3"; done
ok "presence merged: every node sees all 3 viewers again ($(( $(date +%s) - healed_at )) s after the heal)"
[ "$(leaders)" = 1 ] || fail "want exactly one cron leader after the heal, got $(leaders)"
ok "exactly one cron leader after the heal"
rpc node1 "import Ecto.Query; IO.write(Platform.Database.Repo.aggregate(from(j in Oban.Job, where: fragment(\"args->>'event_id' IN ('$tag-pay', '$tag-refund') AND ? = 'completed'\", j.state)), :count))" | grep -q '^2$' || fail "the two payment events aren't both completed exactly once"
ok "the two payment events each completed exactly once"

echo "flapping:"
# The same split, five times in a row, with a few seconds between: the halves
# barely meet before they are cut again. Orders, payments and refunds go on
# throughout, through both halves.
tag="flap-$(date +%s)"
flap_split() {
  ex node1 <<'ELIXIR' >/dev/null
for p <- [:"__N2__", :"__N3__"] do
  Node.set_cookie(p, :split_a)
  Node.disconnect(p)
end
IO.write(:ok)
ELIXIR
  for n in node2 node3; do
    ex $n <<'ELIXIR' >/dev/null
Node.set_cookie(:"__N1__", :split_b)
Node.disconnect(:"__N1__")
IO.write(:ok)
ELIXIR
  done
}
flap_heal() {
  for n in node1 node2 node3; do
    ex $n <<'ELIXIR' >/dev/null
for p <- [:"__N1__", :"__N2__", :"__N3__"], p != node() do
  Node.set_cookie(p, Node.get_cookie())
end
IO.write(:ok)
ELIXIR
  done
}
flap_started=$(date +%s)
for round in 1 2 3 4 5; do
  flap_split
  sleep 3
  # an order and its payment on node1's side, its refund on node2's side
  oid=$(ex node1 <<ELIXIR
{:ok, o} = App.Shop.Services.OrderService.create(%{"customer_email" => "__TAG__-pay-$round@example.com", "items" => [%{"sku" => "A", "quantity" => 1}]})
IO.write(o.id)
ELIXIR
)
  ex node1 <<ELIXIR >/dev/null
:ok = App.Shop.Services.PaymentService.receive_event(%{"event_id" => "__TAG__-pay-$round", "type" => "payment.succeeded", "order_id" => $oid})
IO.write(:ok)
ELIXIR
  ex node2 <<ELIXIR >/dev/null
:ok = App.Shop.Services.PaymentService.receive_event(%{"event_id" => "__TAG__-refund-$round", "type" => "payment.refunded", "order_id" => $oid})
{:ok, _} = App.Shop.Services.OrderService.create(%{"customer_email" => "__TAG__-plain-$round@example.com", "items" => [%{"sku" => "A", "quantity" => 1}]})
IO.write(:ok)
ELIXIR
  flap_heal
  sleep 3
done
ok "split and healed 5 times in $(( $(date +%s) - flap_started )) s, with 10 orders, 5 payments and 5 refunds sent meanwhile through both halves"

until_is "nodes_seen node1" "$(others node1)" 120 || fail "node1 doesn't see the others after the flapping: $(nodes_seen node1)"
until_is "nodes_seen node2" "$(others node2)" 120 || fail "node2 doesn't see the others after the flapping"
until_is "nodes_seen node3" "$(others node3)" 120 || fail "node3 doesn't see the others after the flapping"
ok "after the last heal, every node sees the other two again"
for n in node1 node2 node3; do until_is "viewers $n" 3 120 || fail "$n sees $(viewers $n) viewers after the flapping, want 3"; done
ok "presence has merged: every node sees all 3 viewers"
until_is leaders 1 90 || fail "$(leaders) cron leaders after the flapping, want 1"
ok "exactly one cron leader"

orders_not_done() { # orders of this run without exactly two completed order.created jobs
  ex node1 <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("""
  SELECT count(*) FROM orders o WHERE o.customer_email LIKE '__TAG__-%' AND
    (SELECT count(*) FROM oban_jobs j WHERE j.args->>'topic' = 'order.created'
       AND j.args->'payload'->>'order_id' = o.id::text AND j.state = 'completed') <> 2
""")
IO.write(n)
ELIXIR
}
until_is orders_not_done 0 90 || fail "$(orders_not_done) of the flapping orders lack exactly two completed subscriber jobs"
ok "all 10 orders have exactly two completed subscriber jobs: nothing lost, nothing twice"
not_refunded() {
  ex node1 <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM orders WHERE customer_email LIKE '__TAG__-pay-%' AND status <> 'refunded'")
IO.write(n)
ELIXIR
}
until_is not_refunded 0 90 || fail "$(not_refunded) payment order(s) didn't end refunded"
payment_jobs=$(ex node1 <<'ELIXIR'
%{rows: [[n]]} = Platform.Database.Repo.query!("SELECT count(*) FROM oban_jobs WHERE args->>'event_id' LIKE '__TAG__-%' AND state = 'completed'")
IO.write(n)
ELIXIR
)
[ "$payment_jobs" = 10 ] || fail "$payment_jobs payment events completed, want 10 (each once)"
ok "all 5 orders ended refunded, in order, and each of the 10 payment events completed exactly once"

echo "all good"
