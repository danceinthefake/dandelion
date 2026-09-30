#!/bin/sh
# Checks what the 3-node cluster promises (compose.cluster.yaml must be up):
#   - every node sees the other two
#   - a broadcast on one node reaches a subscriber on another
#   - requests through the load balancer are answered
#   - a queued job runs once, on one node
#   - a job left behind by a killed node is run again by another node
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
    [j] = Platform.Database.Repo.all(from j in Oban.Job, where: fragment(\"args->>'order_id' = ?\", ^\"$1\"), select: {j.state, j.attempt, j.attempted_by})
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
      from(j in Oban.Job, where: fragment("args->>\x27order_id\x27 = ?", ^"#{order.id}")),
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
