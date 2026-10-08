#!/bin/sh
# What keeps a node standing when clients misbehave or the node is told to stop
# (compose.cluster.yaml must be up; needs curl):
#
#   1. Rate limiting: a client that guesses passwords is answered 429 with a
#      retry-after, while /health and the rest of the API keep working.
#   2. Graceful shutdown: a node that is stopped under load says "draining" on
#      /health first, finishes its requests, and exits cleanly; not one order
#      is lost or refused, and every order has both its events.
#   3. Request timeouts: a client that promises a body and never sends it, and one
#      that connects and says nothing, are cut off — they do not hold a node.
#      (Last: the silent client takes two minutes.)
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

# Puts the nodes' limits back, and node2 back up, whatever happens.
set_limits() { # API AUTH
  for n in node1 node2 node3; do
    rpc $n "Application.put_env(:acme, Platform.Web.RateLimit, api: {$1, 60_000}, auth: {$2, 60_000}, trust_forwarded_for: true); Dandelion.RateLimit.reset(); IO.write(:ok)" >/dev/null 2>&1 || true
  done
}
restore() {
  compose start node2 >/dev/null 2>&1 || true
  set_limits 100000 100000
  [ -z "${stop:-}" ] || touch "$stop"
}
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
tag="rel-$(date +%s)"

login() { # PASSWORD -> status; the response headers go to $hdr
  curl -s -o /dev/null -D "$hdr" -w '%{http_code}' -X POST http://localhost:8080/api/session \
    -H 'content-type: application/json' -d "{\"email\":\"admin@example.com\",\"password\":\"$1\"}"
}
admin_token() {
  curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
    -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}
hdr=$(mktemp)

raw() { # NODE 'REQUEST (Elixir string)' WAIT_MS -> first line of the answer, or closed:SECONDS
  rpc "$1" "
    {:ok, s} = :gen_tcp.connect(~c\"localhost\", 4000, [:binary, active: false])
    :ok = :gen_tcp.send(s, $2)
    t = System.monotonic_time(:millisecond)
    case :gen_tcp.recv(s, 0, $3) do
      {:ok, data} -> IO.write(data |> String.split(\"\\r\\n\") |> hd())
      {:error, :closed} -> IO.write(\"closed:\" <> Integer.to_string(div(System.monotonic_time(:millisecond) - t, 1000)))
      {:error, :timeout} -> IO.write(\"still open after $3 ms\")
    end
  " 2>&1
}

echo "rate limiting (3 logins a minute per node, 20 wrong guesses):"
set_limits 1000 3
codes=""
for _ in $(seq 1 20); do codes="$codes $(login wrong-password-1)"; done
guessed=$(echo $codes | tr ' ' '\n' | grep -c '^401$' || true)
refused=$(echo $codes | tr ' ' '\n' | grep -c '^429$' || true)
other=$(echo $codes | tr ' ' '\n' | grep -vc '^401$\|^429$' || true)
[ "$other" = 0 ] || fail "logins answered something else than 401/429: $codes"
[ "$guessed" -ge 3 ] && [ "$guessed" -le 9 ] || fail "$guessed guesses were let through (3 nodes x 3 expected, at most 9): $codes"
[ "$refused" -ge 11 ] || fail "only $refused of 20 guesses were refused: $codes"
ok "of 20 guesses, $guessed were checked (401) and $refused refused (429): the limit is per node, 3 nodes x 3"
[ "$(login wrong-password-1)" = 429 ] || fail "the client is not limited"
grep -qi '^retry-after: [0-9]' "$hdr" || fail "a 429 without a retry-after"
ok "the refusal says when to come back: $(grep -i '^retry-after' "$hdr" | tr -d '\r')"
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)" = 200 ] || fail "/health is limited"
[ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/products/TEA-01)" = 200 ] || fail "the catalogue is limited by the login limit"
ok "/health and the rest of the API still answer: logins have their own count"
set_limits 100000 100000
[ "$(login local-password-1)" = 201 ] || [ "$(login local-password-1)" = 200 ] || fail "can't log in once the limit is lifted"
ok "a limit lifted, the right password logs in again"

echo "a node told to stop, under load:"
admin=$(admin_token)
[ -n "$admin" ] || fail "can't log in as the seeded admin"
stop=$(mktemp -u)
log=$(mktemp)
load() {
  w=$1; n=0
  while [ ! -e "$stop" ]; do
    n=$((n + 1))
    body=$(curl -s -m 10 -w ' %{http_code}' -X POST http://localhost:8080/api/orders \
      -H 'content-type: application/json' -H "authorization: Bearer $admin" \
      -d "{\"customer_email\":\"$tag-$w-$n@example.com\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}") || body=" 000"
    id=$(echo "$body" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
    echo "${body##* } ${id:--}" >> "$log"
    sleep 0.1
  done
}
load 1 & l1=$!
load 2 & l2=$!
load 3 & l3=$!
sleep 5
before=$(wc -l < "$log")

started=$(date +%s)
compose stop -t 40 node2 >/dev/null 2>&1 &
stopper=$!
saw=""
for _ in $(seq 1 20); do
  saw=$(raw node2 '"GET /health HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n"' 3000 || true)
  case "$saw" in "HTTP/1.1 503"*) break ;; esac
  saw=""
  sleep 0.25
done
[ -n "$saw" ] || fail "node2 never said it was draining on /health"
ok "node2, told to stop, answered /health with 503 while it was still serving"
wait "$stopper"
took=$(( $(date +%s) - started ))
code=$(docker inspect "$(compose ps -aq node2)" --format '{{.State.ExitCode}}')
[ "$code" = 0 ] || fail "node2 exited with $code"
[ "$took" -lt 40 ] || fail "node2 needed $took s to stop"
ok "node2 stopped itself in $took s and exited 0 (not killed)"

sleep 5
touch "$stop"
wait "$l1" "$l2" "$l3" || true
total=$(wc -l < "$log")
[ "$total" -gt "$before" ] || fail "the load did not continue after the stop"
bad=$(awk '$1 != 201' "$log" | sort | uniq -c | tr '\n' ' ')
[ -z "$bad" ] || fail "orders were refused or lost while node2 stopped: $bad"
ok "all $total orders made during it were answered 201, none refused"

compose start node2 >/dev/null
for _ in $(seq 1 90); do
  [ "$(rpc node2 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
  sleep 1
done
ids=$(awk '$2 != "-" {print $2}' "$log" | paste -sd, -)
missing=$(rpc node1 "
  ids = [$ids]
  %{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM orders WHERE id = ANY(\$1)\", [ids])
  IO.write(length(ids) - n)
")
[ "$missing" = 0 ] || fail "$missing acknowledged orders are not in the database"
ok "every acknowledged order is in the database"
for _ in $(seq 1 60); do
  open=$(rpc node1 "
    %{rows: [[n]]} = Platform.Database.Repo.query!(\"\"\"
      SELECT count(*) FROM orders o WHERE o.customer_email LIKE '$tag-%' AND
        (SELECT count(*) FROM oban_jobs j WHERE j.args->>'topic' = 'order.created'
           AND j.args->'payload'->>'order_id' = o.id::text AND j.state = 'completed') <> 2
    \"\"\")
    IO.write(n)
  ")
  [ "$open" = 0 ] && break
  sleep 1
done
[ "$open" = 0 ] || fail "$open orders don't have exactly two completed events"
ok "every order has both its events, handled once"
echo "request timeouts:"
answer=$(raw node1 '"POST /api/users HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/json\r\ncontent-length: 100\r\n\r\n{"' 30000)
case "$answer" in
  "HTTP/1.1 408"*|closed:*) ok "a body that never arrives is cut off, not waited for ($answer)" ;;
  *) fail "a client that promises a body and sends none: $answer" ;;
esac
answer=$(raw node1 '""' 150000)
case "$answer" in
  "HTTP/1.0 408"*|closed:*) ok "a client that connects and says nothing is answered 408 and disconnected (after about two read timeouts: $answer)" ;;
  *) fail "a silent client: $answer" ;;
esac
[ "$(rpc node1 'IO.write(Application.get_env(:acme, Platform.Web.Endpoint)[:http][:thousand_island_options][:num_connections])')" = 4096 ] \
  || fail "the connection limit is not set"
ok "connections are bounded at 4096 per node (set; not filled here: LIMITS.md)"

echo "reliability proof passed"
