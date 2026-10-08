#!/bin/sh
# Searching products on the 3-node cluster, with 20 000 products in the table (compose.cluster.yaml
# must be up; needs curl). The search is Postgres full-text search; nothing is indexed on the side:
#
#   1. it finds the right products — by prefix, all words, in the name or the description, the
#      name first, accents ignored, a typo forgiven (and said so) — and nothing a user types
#      makes it fail;
#   2. a change is searchable at once, on every node: ten renames through the load balancer,
#      each searched for by its new name and its old one from all three nodes straight after —
#      not one stale answer — and a deleted product is gone from the next search;
#   3. it uses the index (the plan says so) and answers fast enough to be typed into: 200 searches
#      are timed.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

cleanup() {
  rpc node1 "Platform.Database.Repo.query!(\"DELETE FROM products WHERE sku LIKE 'GEN-%' OR sku LIKE 'SRCH-%'\"); IO.write(:ok)" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
cleanup
tag="srch$(date +%s)"
admin=$(curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"

echo "20 000 products:"
rpc node1 '
  words = ~w(green black white oolong jasmine mint ginger honey lemon cup pot kettle strainer sugar cinnamon vanilla rose hibiscus chamomile)
  Platform.Database.Repo.query!("""
    INSERT INTO products (sku, name, description, price_cents, updated_at)
    SELECT "GEN-" || i,
           ($1::text[])[1 + i % 19] || " " || ($1::text[])[1 + (i / 19) % 19] || " " || i,
           "Batch " || (i / 100) || " of " || ($1::text[])[1 + (i / 7) % 19] || " from the " || ($1::text[])[1 + (i / 13) % 19] || " estate",
           100 + i % 5000, now()
    FROM generate_series(1, 20000) i
  """ |> String.replace("\"", "\x27"), [words])
  Platform.Database.Repo.query!("ANALYZE products")
  IO.write(:ok)
' >/dev/null
total=$(rpc node1 'IO.write(hd(hd(Platform.Database.Repo.query!("SELECT count(*) FROM products WHERE sku LIKE \x27GEN-%\x27").rows)))')
[ "$total" = 20000 ] || fail "$total generated products, want 20000"
ok "20 000 products in the table"

search() { curl -s -G "http://localhost:8080/api/search/products" --data-urlencode "q=$1" ${2:+--data-urlencode "limit=$2"}; }
skus() { grep -o '"sku":"[^"]*"' | cut -d'"' -f4 || true; }
admin_api() { # METHOD PATH [BODY] -> status
  m=$1; path=$2; shift 2
  if [ $# -gt 0 ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$m" "http://localhost:8080$path" -H 'content-type: application/json' -H "authorization: Bearer $admin" -d "$1"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$m" "http://localhost:8080$path" -H "authorization: Bearer $admin"
  fi
}

echo "finding things:"
[ "$(admin_api POST /api/products "{\"sku\":\"SRCH-1\",\"name\":\"$tag Green tea\",\"description\":\"Fresh leaves from the hills, picked by hand\",\"price_cents\":1500}")" = 201 ] || fail "creating a product"
[ "$(admin_api POST /api/products "{\"sku\":\"SRCH-2\",\"name\":\"$tag Tea cup\",\"description\":\"Holds green tea or anything else you like to drink\",\"price_cents\":4000}")" = 201 ] || fail "creating a product"
[ "$(admin_api POST /api/products "{\"sku\":\"SRCH-3\",\"name\":\"$tag Café crème\",\"description\":\"Plain\",\"price_cents\":900}")" = 201 ] || fail "creating a product"
out=$(search "$tag gre tea")
echo "$out" | skus | grep -q SRCH-1 && echo "$out" | skus | grep -q SRCH-2 || fail "'$tag gre tea' (prefix, all words) did not find both: $out"
[ "$(echo "$out" | skus | head -1)" = SRCH-1 ] || fail "the name match is not first: $(echo "$out" | skus | tr '\n' ' ')"
ok "'gre tea' finds the green tea and the cup that mentions it, the product named for it first"
echo "$out" | grep -q '"snippet":"[^"]*\[\[' || fail "no [[highlighted]] snippet in: $out"
ok "the snippet marks the matching words ([[…]]), as plain text"
echo "$(search "$tag CAFE creme")" | skus | grep -q SRCH-3 || fail "'CAFE creme' did not find 'Café crème'"
ok "accents and capitals are ignored: 'CAFE creme' finds 'Café crème'"
out=$(search "$tag grean tea")
echo "$out" | grep -q '"match":"fuzzy"' || fail "a typo did not fall back to similar names: $out"
echo "$out" | skus | grep -q SRCH-1 || fail "the typo 'grean tea' did not find the green tea"
ok "a typo ('grean tea') finds it too, and the answer says \"match\":\"fuzzy\""
bad=0
for q in '&' '|' '!' "'" '"' '\' '(' ')' ':*' 'tea & !' '<->' "' OR 1=1 --" 'a:b' "$(printf 'x%.0s' $(seq 1 600))"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -G "http://localhost:8080/api/search/products" --data-urlencode "q=$q")
  [ "$code" = 200 ] || { bad=$((bad + 1)); echo "  query '$q' answered $code" >&2; }
done
[ "$bad" = 0 ] || fail "$bad queries made the search fail"
ok "14 nasty queries (operators, quotes, a SQL injection, 600 characters): all answered 200"

echo "a change is searchable at once, on every node:"
stale=0
for i in $(seq 1 10); do
  [ "$(admin_api PUT /api/products/SRCH-1/details "{\"name\":\"$tag round$i Green tea\"}")" = 200 ] || fail "rename $i"
  for _ in 1 2 3; do
    new=$(search "round$i $tag" | skus | grep -c SRCH-1 || true)
    [ "$new" = 1 ] || { stale=$((stale + 1)); echo "  rename $i: not found by its new name" >&2; }
    if [ "$i" -gt 1 ]; then
      old=$(search "round$((i - 1)) $tag" 5 | grep -c '"match":"text"' || true)
      [ "$old" = 0 ] || { stale=$((stale + 1)); echo "  rename $i: still found by the old name" >&2; }
    fi
  done
done
[ "$stale" = 0 ] || fail "$stale stale answers"
ok "10 renames through the load balancer, each searched 3 times (all three nodes) by the new and the old name: no stale answer"
[ "$(admin_api DELETE /api/products/SRCH-2)" = 204 ] || fail "deleting a product"
for _ in 1 2 3; do
  search "$tag cup" | skus | grep -q SRCH-2 && fail "a deleted product is still found"
done
ok "a deleted product is gone from the very next search, from every node"

echo "the index:"
plan=$(rpc node1 "IO.write(Enum.join(List.flatten(Platform.Database.Repo.query!(\"EXPLAIN SELECT sku FROM products WHERE search @@ to_tsquery('simple', 'tea:* & ginger:*')\").rows), \"\\n\"))")
echo "$plan" | grep -q "products_search_index" || fail "the plan does not use the index: $plan"
ok "the plan uses the GIN index (products_search_index), not a scan of 20 000 rows"
times=$(mktemp)
for i in $(seq 1 200); do
  case $((i % 5)) in
    0) q="gre" ;; 1) q="honey ging" ;; 2) q="batch 12 oolong" ;; 3) q="lemon" ;; *) q="mint estate" ;;
  esac
  curl -s -o /dev/null -w '%{time_total}\n' -G "http://localhost:8080/api/search/products" --data-urlencode "q=$q" >> "$times"
done
p50=$(sort -n "$times" | sed -n 100p); p95=$(sort -n "$times" | sed -n 190p); max=$(sort -n "$times" | tail -1)
ok "200 searches through the load balancer over 20 000 products: median ${p50}s, p95 ${p95}s, slowest ${max}s"
awk -v p="$p95" 'BEGIN { exit !(p < 1.0) }' || fail "p95 is $p95 s"
echo "search proof passed"
