#!/bin/sh
# The dashboard shows what is happening (compose.cluster.yaml must be up; needs curl and jq).
# Prometheus collects /metrics from the three nodes, Grafana draws dashboards/dandelion.json:
#
#   1. Prometheus reads all three nodes, and Grafana has the dashboard and can reach Prometheus;
#   2. things are made to happen — traffic, a client over its rate limit, orders paused, a mail
#      server that goes away (a circuit opens, mail waits), a node told to stop (draining);
#   3. EVERY query on the dashboard runs without error, and the panels that show those things
#      have data: a panel with a misspelled metric, or a metric nothing emits, is caught here.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
PROM=http://localhost:19090
GRAFANA=http://localhost:13000
DASH=grafana/dashboards/dandelion.json

restore() {
  compose start mailpit node3 >/dev/null 2>&1 || true
  for n in node1 node2 node3; do
    rpc $n 'Application.put_env(:acme, Platform.Web.RateLimit, api: {100000, 60_000}, auth: {100000, 60_000}, trust_forwarded_for: true); Dandelion.Flags.delete("orders.enabled"); Dandelion.RateLimit.reset(); IO.write(:ok)' >/dev/null 2>&1 || true
  done
}
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
compose start mailpit >/dev/null 2>&1 || true

# prom QUERY -> the instant-query result array (empty when the query returned nothing)
prom() {
  curl -s -G "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -c 'if .status == "success" then .data.result else error("query failed: " + (.error // "?")) end'
}
prom_value() { prom "$1" | jq -r '.[0].value[1] // "none"'; }

echo "the pieces:"
up=0
for _ in $(seq 1 60); do
  up=$(curl -s "$PROM/api/v1/targets" | jq '[.data.activeTargets[] | select(.health == "up")] | length')
  [ "$up" = 3 ] && break
  sleep 1
done
[ "$up" = 3 ] || fail "Prometheus reads $up of 3 nodes"
ok "Prometheus reads /metrics from all 3 nodes"
for _ in $(seq 1 60); do
  curl -sf "$GRAFANA/api/health" >/dev/null && curl -sf -u admin:local-only "$GRAFANA/api/dashboards/uid/dandelion" >/dev/null && break
  sleep 1
done
panels=$(jq '[.panels[] | select(.targets)] | length' "$DASH")
loaded=$(curl -s -u admin:local-only "$GRAFANA/api/dashboards/uid/dandelion" | jq '[.dashboard.panels[] | select(.targets)] | length')
[ "$loaded" = "$panels" ] || fail "Grafana has $loaded of the dashboard's $panels panels"
[ "$(curl -s -u admin:local-only "$GRAFANA/api/datasources/uid/prometheus/health" | jq -r .status)" = OK ] || fail "Grafana can't reach Prometheus"
ok "Grafana has the dashboard ($panels panels, provisioned from the file) and reaches Prometheus"

echo "making things happen:"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"
order() { curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8080/api/orders -H 'content-type: application/json' -H "authorization: Bearer $admin" -d "{\"customer_email\":\"dash-$1@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}"; }
tag="dash$(date +%s)"
for i in $(seq 1 30); do order "$tag-$i" >/dev/null; curl -s -o /dev/null "http://localhost:8080/api/search/products?q=tea"; curl -s -o /dev/null http://localhost:8080/api/products/NOPE; done
ok "30 orders, 30 searches and 30 unknown products through the load balancer"

for n in node1 node2 node3; do rpc $n 'Application.put_env(:acme, Platform.Web.RateLimit, api: {3, 60_000}, auth: {3, 60_000}, trust_forwarded_for: true); Dandelion.RateLimit.reset(); IO.write(:ok)' >/dev/null; done
limited=0
for _ in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/products/NOPE)" = 429 ] && limited=$((limited + 1)); done
for n in node1 node2 node3; do rpc $n 'Application.put_env(:acme, Platform.Web.RateLimit, api: {100000, 60_000}, auth: {100000, 60_000}, trust_forwarded_for: true); Dandelion.RateLimit.reset(); IO.write(:ok)' >/dev/null; done
[ "$limited" -ge 5 ] || fail "only $limited of 30 requests were rate limited"
ok "a client over its limit: $limited requests answered 429"

rpc node1 'Dandelion.Flags.put("orders.enabled", false); IO.write(:ok)' >/dev/null
paused=0
for i in 1 2 3 4 5 6; do [ "$(order "$tag-paused$i")" = 503 ] && paused=$((paused + 1)); done
rpc node1 'Dandelion.Flags.delete("orders.enabled"); IO.write(:ok)' >/dev/null
[ "$paused" -ge 3 ] || fail "only $paused orders were refused while paused"
ok "orders paused by a flag: $paused answered 503"

compose stop mailpit >/dev/null 2>&1
for i in 1 2 3 4 5 6 7 8; do order "$tag-mail$i" >/dev/null; done
waiting="none"
for _ in $(seq 1 40); do
  waiting=$(prom_value 'sum(max by (queue, state) (platform_oban_queue_jobs{queue="mail",state=~"available|retryable|scheduled"}))')
  case "$waiting" in none) ;; *) awk -v w="$waiting" 'BEGIN { exit !(w >= 1) }' && break ;; esac
  sleep 1
done
awk -v w="$waiting" 'BEGIN { exit !(w >= 1) }' || fail "no mail was seen waiting in the queue panel's query ($waiting)"
opens=0
for _ in $(seq 1 60); do
  opens=$(prom_value 'sum(increase(dandelion_resilience_circuit_changes_total{state="open"}[5m]))')
  awk -v o="$opens" 'BEGIN { exit !(o + 0 >= 1) }' && break
  sleep 1
done
awk -v o="$opens" 'BEGIN { exit !(o + 0 >= 1) }' || fail "no circuit opening was counted ($opens)"
ok "the mail server stopped: $waiting mail jobs waiting, and a circuit opened (counted $opens)"
compose start mailpit >/dev/null 2>&1

compose stop -t 40 node3 >/dev/null 2>&1 &
stopper=$!
drained=0
for _ in $(seq 1 30); do
  d=$(prom_value 'max(platform_node_draining)')
  [ "$d" = 1 ] && { drained=1; break; }
  sleep 0.5
done
wait "$stopper"
compose start node3 >/dev/null 2>&1
[ "$drained" = 1 ] || fail "no node was seen draining"
ok "a node told to stop: seen draining (1) while it finished its requests"
for _ in $(seq 1 90); do
  [ "$(rpc node3 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
  sleep 1
done
sleep 6

echo "the queries:"
jq -r '.panels[] | select(.targets) | .title as $t | .targets[] | [$t, .expr] | @tsv' "$DASH" > /tmp/dash-queries.$$
count=0
while IFS="$(printf '\t')" read -r title expr; do
  prom "$expr" >/dev/null || fail "panel '$title': the query failed: $expr"
  count=$((count + 1))
done < /tmp/dash-queries.$$
ok "all $count queries on the dashboard run without error"

# panels that must have data now, by title
empty=""
for title in "Nodes in the cluster" "Nodes being scraped" "Requests per second, by status" "Latency: median, 95th and 99th percentile" "Requests per second, by node" "Slowest routes (95th percentile)" "Calls to other services, by circuit and result" "Circuit changes (last 5 minutes)" "Jobs waiting, by queue" "Jobs finished per second, by worker and outcome" "Job time, 95th percentile by worker" "Database: waiting for a connection (95th percentile)" "Cache fetches per second" "Memory of the VM, by node" "Scheduler load (processes waiting to run), by node" "Node draining (1 = told to stop)"; do
  jq -r --arg t "$title" '.panels[] | select(.title == $t) | .targets[].expr' "$DASH" | while IFS= read -r expr; do
    # a panel's queries that look at "now" need traffic in the last minute: widen the window
    # for rates, which is what a human looking at the 15 minute graph sees
    echo "$expr"
  done > /tmp/dash-expr.$$
  [ -s /tmp/dash-expr.$$ ] || { empty="$empty [no such panel: $title]"; continue; }
  has=0
  while IFS= read -r expr; do
    wide=$(echo "$expr" | sed 's/\[1m\]/[10m]/g')
    [ "$(prom "$wide" | jq 'length')" -gt 0 ] && has=1
  done < /tmp/dash-expr.$$
  [ "$has" = 1 ] || empty="$empty [$title]"
done
rm -f /tmp/dash-queries.$$ /tmp/dash-expr.$$
[ -z "$empty" ] || fail "panels with no data after the traffic:$empty"
ok "and the 16 panels that show what we made happen all have data"
echo "dashboard proof passed"
