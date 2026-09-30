#!/bin/sh
# Checks what the 3-node cluster promises (compose.cluster.yaml must be up):
#   - every node sees the other two
#   - a broadcast on one node reaches a subscriber on another
#   - requests through the load balancer are answered
#   - a queued job runs once, on one node
#   - a job left behind by a killed node is run again by another node
#   - each order.created subscriber runs once per order
#   - payment events for one order run in arrival order across the nodes
#   - a dead node's unfinished payment job holds back its order, until rescued
#   - a price changed through one node is seen by the cache on every node
#   - a node that joins again starts with an empty cache
#   - a node killed without warning drops out; started again, it rejoins
#   - the database going away crashes nothing and splits nothing
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

# wait_for NODE COUNT: until NODE sees COUNT other nodes (30 s at most)
wait_for() {
  for _ in $(seq 1 30); do
    [ "$(rpc "$1" 'IO.write(length(Node.list()))' 2>/dev/null)" = "$2" ] && return 0
    sleep 1
  done
  return 1
}

echo "cluster:"
for n in node1 node2 node3; do
  wait_for "$n" 2 || fail "$n doesn't see the other two nodes"
  ok "$n sees $(rpc "$n" 'IO.write(Enum.join(Enum.sort(Node.list()), " "))')"
done

echo "broadcast:"
# A subscriber on another node; node1 broadcasts; the subscriber reports back.
got=$(rpc node1 '
  [target | _] = Node.list()
  me = self()
  Node.spawn(target, fn ->
    Phoenix.PubSub.subscribe(Platform.Broadcast, "proof")
    send(me, :subscribed)
    receive do
      msg -> send(me, {:got, node(), msg})
    after
      5_000 -> send(me, :timeout)
    end
  end)
  receive do: (:subscribed -> :ok)
  Phoenix.PubSub.broadcast(Platform.Broadcast, "proof", {:hello, node()})
  receive do
    {:got, on, {:hello, from}} -> IO.write("#{from} -> #{on}")
    :timeout -> IO.write("timeout")
  end
')
case "$got" in *" -> "*) ok "$got" ;; *) fail "broadcast didn't cross nodes: $got" ;; esac

echo "load balancer:"
for _ in 1 2 3 4 5 6; do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)
  [ "$code" = 200 ] || fail "GET /health through nginx: $code"
done
ok "6 × GET /health through nginx: 200"

echo "jobs:"
# Creating an order queues its confirmation; one node runs it, once.
job=$(rpc node1 '
  {:ok, order} = App.Shop.Services.OrderService.create(%{
    "customer_email" => "proof@example.com",
    "items" => [%{"sku" => "PROOF", "quantity" => 1, "price_cents" => 100}]
  })
  IO.write(order.id)
')
job_state() { # ORDER_ID -> "state attempt attempts-by-node-count"
  rpc node1 "
    import Ecto.Query
    [j] = Platform.Database.Repo.all(from j in Oban.Job, where: fragment(\"args->'payload'->>'order_id' = ? AND args->>'topic' = 'order.created' AND worker LIKE '%SendOrderConfirmation'\", ^\"$1\"), select: {j.state, j.attempt, j.attempted_by})
    {state, attempt, by} = j
    IO.write(inspect({state, attempt, length(by)}))
  "
}
for _ in $(seq 1 30); do
  [ "$(job_state "$job")" = '{"completed", 1, 2}' ] && break
  sleep 1
done
[ "$(job_state "$job")" = '{"completed", 1, 2}' ] || fail "the confirmation job didn't complete once: $(job_state "$job")"
ok "order $job: confirmation job completed, 1 attempt"

echo "events:"
oid=$(curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
  -d '{"customer_email":"events@example.com","items":[{"sku":"A","quantity":1,"price_cents":100}]}' |
  sed -n 's/.*"id":\([0-9]*\).*/\1/p')
[ -n "$oid" ] || fail "POST /api/orders through nginx didn't return an order"
subs() { # ORDER_ID -> how many order.created jobs for it are completed
  rpc node1 "
    import Ecto.Query
    IO.write(Platform.Database.Repo.aggregate(from(j in Oban.Job, where: j.state == \"completed\" and fragment(\"args->>'topic' = 'order.created' AND args->'payload'->>'order_id' = ?\", ^\"$1\")), :count))
  "
}
for _ in $(seq 1 30); do [ "$(subs "$oid")" = 2 ] && break; sleep 1; done
[ "$(subs "$oid")" = 2 ] || fail "order $oid: want both subscribers completed, got $(subs "$oid")"
ok "order $oid: both order.created subscribers completed, once each"

# wait_status ORDER_ID STATUS: until the order has that status (40 s at most)
order_status() { rpc node1 "{:ok, o} = App.Shop.Services.OrderService.get($1); IO.write(o.status)"; }
wait_status() {
  for _ in $(seq 1 40); do [ "$(order_status "$1")" = "$2" ] && return 0; sleep 1; done
  return 1
}
webhook() { # ORDER_ID EVENT_ID TYPE -> http code
  curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/payments/webhook \
    -H 'content-type: application/json' -H 'x-callback-token: local-only-webhook-token' \
    -d "{\"event_id\":\"$2\",\"type\":\"$3\",\"order_id\":$1}"
}
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/payments/webhook \
  -H 'content-type: application/json' -d '{}')" = 401 ] || fail "the webhook answered without the token"
ok "webhook without the token: 401"

echo "ordered queue:"
# Hold the queue, send "paid" then "refunded" for 10 orders (in that order),
# let all three nodes loose on them. A refund that ran before its payment
# would be dropped (a pending order can't be refunded), so every order
# ending refunded means the order was kept.
rpc node1 'Oban.pause_queue(queue: :ordered)' >/dev/null
ids=""
for i in $(seq 1 10); do
  id=$(curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
    -d '{"customer_email":"order@example.com","items":[{"sku":"A","quantity":1,"price_cents":100}]}' |
    sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  [ "$(webhook "$id" "pay-$id" payment.succeeded)" = 202 ] || fail "webhook refused payment.succeeded for $id"
  [ "$(webhook "$id" "refund-$id" payment.refunded)" = 202 ] || fail "webhook refused payment.refunded for $id"
  ids="$ids $id"
done
rpc node1 'Oban.resume_queue(queue: :ordered)' >/dev/null
for id in $ids; do wait_status "$id" refunded || fail "order $id is $(order_status "$id"), want refunded"; done
ok "10 orders: payment then refund, each ended refunded (nodes raced, order held)"

# A job stuck `executing` on a dead node holds back the next event of its
# order, until the lifeline gives it back; other orders aren't held.
rpc node1 'Oban.pause_queue(queue: :ordered)' >/dev/null
held=$(curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
  -d '{"customer_email":"held@example.com","items":[{"sku":"A","quantity":1,"price_cents":100}]}' |
  sed -n 's/.*"id":\([0-9]*\).*/\1/p')
[ "$(webhook "$held" "pay-$held" payment.succeeded)" = 202 ] || fail "webhook refused the payment"
rpc node1 "
  import Ecto.Query
  {1, _} =
    Platform.Database.Repo.update_all(
      from(j in Oban.Job, where: fragment(\"args->>'event_id' = ?\", ^\"pay-$held\")),
      set: [state: \"executing\", attempt: 1, attempted_at: DateTime.utc_now(),
            attempted_by: [\"acme@killed-node\", \"0\"]]
    )
" >/dev/null
[ "$(webhook "$held" "refund-$held" payment.refunded)" = 202 ] || fail "webhook refused the refund"
free=$(curl -s -X POST http://localhost:8080/api/orders -H 'content-type: application/json' \
  -d '{"customer_email":"free@example.com","items":[{"sku":"A","quantity":1,"price_cents":100}]}' |
  sed -n 's/.*"id":\([0-9]*\).*/\1/p')
[ "$(webhook "$free" "pay-$free" payment.succeeded)" = 202 ] || fail "webhook refused the payment"
rpc node1 'Oban.resume_queue(queue: :ordered)' >/dev/null
wait_status "$free" paid || fail "another order was held back by the dead node's job"
ok "order $free (other order) paid while order $held waited"
wait_status "$held" refunded || fail "order $held is $(order_status "$held"), want refunded"
ok "order $held: the dead node's job was rescued, then its refund ran after it"

echo "cache:"
sku="PROOF-$(date +%s)"
rpc node1 "Platform.Database.Repo.insert!(%App.Shop.Models.Product{sku: \"$sku\", name: \"Proof\", price_cents: 1500})" >/dev/null
price_on() { rpc "$1" "{:ok, p} = App.Shop.Services.ProductService.get(\"$sku\"); IO.write(p.price_cents)"; }
cached_on() { rpc "$1" "IO.write(elem(Cachex.exists?(Platform.Cache, {:product, \"$sku\"}), 1))"; }
for n in node1 node2 node3; do
  [ "$(price_on $n)" = 1500 ] || fail "$n doesn't read the price"
  [ "$(cached_on $n)" = true ] || fail "$n didn't keep the product in its cache"
done
ok "$sku read on all 3 nodes: each keeps its own copy"
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "http://localhost:8080/api/products/$sku" \
  -H 'content-type: application/json' -d '{"price_cents":1600}')
[ "$code" = 200 ] || fail "PUT through nginx: $code"
for n in node1 node2 node3; do
  for _ in $(seq 1 10); do [ "$(cached_on $n)" = false ] && break; sleep 0.5; done
  [ "$(price_on $n)" = 1600 ] || fail "$n still reads the old price: $(price_on $n)"
done
ok "price changed through nginx (some node): every node reads 1600"

# A node that joins (again) may have missed deletes while apart: it empties
# its cache. node1 drops node2; the cluster strategy connects them again.
[ "$(price_on node1)" = 1600 ] && [ "$(cached_on node1)" = true ] || fail "node1 didn't keep the product"
rpc node1 'Node.disconnect(hd(Node.list())); IO.write(:ok)' >/dev/null
for _ in $(seq 1 30); do [ "$(cached_on node1)" = false ] && break; sleep 1; done
[ "$(cached_on node1)" = false ] || fail "node1 kept its cache after a node joined again"
wait_for node1 2 || fail "node1 didn't get its nodes back"
ok "node1 lost a node and got it back: its cache was emptied"

echo "node failure:"
compose kill -s KILL node2 >/dev/null 2>&1
wait_for node1 1 || fail "node1 still sees node2 after it was killed"
ok "node2 killed; node1 now sees $(rpc node1 'IO.write(length(Node.list()))') other node"
for _ in 1 2 3 4 5 6; do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)
  [ "$code" = 200 ] || fail "GET /health with node2 down: $code"
done
ok "6 × GET /health with node2 down: 200"

compose start node2 >/dev/null 2>&1
wait_for node2 2 && wait_for node1 2 || fail "node2 didn't rejoin"
ok "node2 started again and rejoined"

echo "job on a killed node:"
# A killed node leaves its job row `executing`. Write that row by hand (no job
# here runs long enough to catch one mid-flight), kill node2, and wait for
# Oban's lifeline on another node to give the job back and have it run.
orphan=$(rpc node1 '
  {:ok, order} = App.Shop.Services.OrderService.create(%{
    "customer_email" => "orphan@example.com",
    "items" => [%{"sku" => "PROOF", "quantity" => 1, "price_cents" => 100}]
  })
  import Ecto.Query
  {1, _} =
    Platform.Database.Repo.update_all(
      from(j in Oban.Job, where: fragment("args->\x27payload\x27->>\x27order_id\x27 = ? AND worker LIKE \x27%SendOrderConfirmation\x27", ^"#{order.id}")),
      set: [state: "executing", attempt: 1, attempted_at: DateTime.utc_now(),
            attempted_by: ["acme@killed-node", "0"]]
    )
  IO.write(order.id)
')
compose kill -s KILL node2 >/dev/null 2>&1
for _ in $(seq 1 40); do
  [ "$(job_state "$orphan")" = '{"completed", 2, 2}' ] && break
  sleep 1
done
[ "$(job_state "$orphan")" = '{"completed", 2, 2}' ] || fail "the orphaned job wasn't run again: $(job_state "$orphan")"
ok "order $orphan: job left executing by a killed node was run again, 2nd attempt, completed"
compose start node2 >/dev/null 2>&1
wait_for node2 2 && wait_for node1 2 || fail "node2 didn't rejoin"

echo "database outage:"
restarts() { docker inspect --format '{{.RestartCount}}' $(compose ps -q node1 node2 node3) | awk '{ s += $1 } END { print s }'; }
before=$(restarts)
compose stop postgres >/dev/null 2>&1
sleep 15
[ "$(restarts)" = "$before" ] || fail "nodes restarted while the database was down"
[ "$(rpc node1 'IO.write(length(Node.list()))')" = 2 ] || fail "the cluster split while the database was down"
code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)
[ "$code" = 503 ] || fail "GET /health with the database down: $code (want 503)"
ok "15 s without Postgres: no node restarted, still 3 nodes, /health says 503"
compose start postgres >/dev/null 2>&1
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)
  [ "$code" = 200 ] && break
  sleep 1
done
[ "$code" = 200 ] || fail "GET /health after the database came back: $code"
ok "Postgres back: /health 200"

echo "all good"
