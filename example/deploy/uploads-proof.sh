#!/bin/sh
# Uploaded files on the 3-node cluster (compose.cluster.yaml must be up; needs curl,
# sha256sum, head). The nodes share one directory (a Docker volume), the file's row is
# in Postgres:
#
#   1. a file uploaded through the load balancer is downloaded, byte for byte, from
#      every node — 12 downloads answered by all three — and its checksum is the one
#      computed here;
#   2. it is the customer's own: another customer gets 404, no login gets 401;
#   3. what the file is comes from its bytes: a script uploaded as "picture.png" and
#      called image/png is refused; a file over the limit is refused (413);
#   4. ten uploads at once all arrive, each under its own key;
#   5. deleting removes the row and the bytes, on every node;
#   6. a node killed while a file is still arriving leaves no half file and no row.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

restore() { for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1 || true; done; rm -rf "${work:-/nonexistent}"; }
trap restore EXIT
work=$(mktemp -d)

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
tag="up-$(date +%s)"

register() { # NAME -> token
  curl -s -o /dev/null -X POST http://localhost:8080/api/users -H 'content-type: application/json' \
    -d "{\"email\":\"$tag-$1@example.com\",\"password\":\"correct horse battery\"}"
  curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
    -d "{\"email\":\"$tag-$1@example.com\",\"password\":\"correct horse battery\"}" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}
alice=$(register alice); bob=$(register bob)
[ -n "$alice" ] && [ -n "$bob" ] || fail "can't register the test customers"

# a PNG header followed by random bytes, $2 bytes long in all
png() { { printf '\211PNG\r\n\032\n'; head -c "$(( $2 - 8 ))" /dev/urandom; } > "$1"; }
stored_keys() { rpc node1 'IO.write(length(Dandelion.Storage.Local.keys(App.Files.Services.FileService.root())))'; }
upload() { # TOKEN FILE NAME [curl args] -> prints "STATUS BODY"
  token=$1; file=$2; name=$3; shift 3
  curl -s -m 30 "$@" -w ' %{http_code}' -X POST http://localhost:8080/api/files \
    -H "authorization: Bearer $token" -F "file=@$file;filename=$name;type=image/png"
}
field() { echo "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\).*/\1/p"; }
before=$(stored_keys)

echo "upload and download:"
png "$work/pic.png" 200000
want=$(sha256sum "$work/pic.png" | cut -d' ' -f1)
out=$(upload "$alice" "$work/pic.png" "holiday.png")
[ "${out##* }" = 201 ] || fail "the upload answered: $out"
id=$(field "$out" id); got=$(field "$out" sha256)
[ "$got" = "$want" ] || fail "the stored checksum is $got, the file's is $want"
ok "uploaded through the load balancer: file $id, sha256 $(echo "$want" | cut -c1-16)…"

: > "$work/nodes"
for i in $(seq 1 12); do
  curl -s -o "$work/got-$i" -D "$work/h-$i" "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice"
  [ "$(sha256sum "$work/got-$i" | cut -d' ' -f1)" = "$want" ] || fail "download $i is not the uploaded file"
  grep -i '^x-upstream' "$work/h-$i" | tr -d '\r' >> "$work/nodes"
done
[ "$(sort -u "$work/nodes" | wc -l | tr -d ' ')" = 3 ] || fail "the downloads were not served by 3 different nodes: $(sort -u "$work/nodes" | tr '\n' ' ')"
ok "12 downloads, answered by all 3 nodes, each byte for byte the file that was uploaded"
grep -qi '^content-disposition: attachment' "$work/h-1" && grep -qi '^x-content-type-options: nosniff' "$work/h-1" \
  || fail "a download is not an attachment with nosniff"
ok "a download is an attachment with nosniff: a browser never shows it as a page of ours"

echo "whose it is:"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $bob")" = 404 ] || fail "another customer can read the file"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id")" = 401 ] || fail "the file is readable without a login"
ok "another customer gets 404, no login gets 401"

echo "what is accepted:"
printf '<script>alert(1)</script>' > "$work/evil.png"
out=$(upload "$alice" "$work/evil.png" "picture.png")
[ "$(field "$out" content_type)" = "text/plain" ] || fail "a script called picture.png, typed image/png, was kept as: $out"
ok "a script named picture.png and typed image/png is kept as what it is, text/plain (never as an image)"
printf '\177ELF\002\001\001\000\000\000\000\000' > "$work/elf.png"
out=$(upload "$alice" "$work/elf.png" "picture.png")
[ "${out##* }" = 400 ] || fail "a binary called picture.png, typed image/png, answered: $out"
ok "an executable named picture.png and typed image/png is refused (400): the bytes decide"
keys_now=$(stored_keys)
png "$work/big.png" 5500000
out=$(upload "$alice" "$work/big.png" "big.png")
[ "${out##* }" = 413 ] || fail "5.5 MB answered: ${out##* }"
png "$work/huge.png" 7500000
out=$(upload "$alice" "$work/huge.png" "huge.png")
[ "${out##* }" = 413 ] || fail "7.5 MB answered: ${out##* }"
ok "5.5 MB and 7.5 MB are refused (413)"
[ "$(stored_keys)" = "$keys_now" ] || fail "refused uploads left files behind ($(stored_keys) stored, want $keys_now)"
ok "and the refused uploads left nothing in the directory"

echo "ten at once:"
for i in $(seq 1 10); do
  png "$work/p$i.png" 50000
  ( upload "$alice" "$work/p$i.png" "p$i.png" > "$work/up-$i" ) &
done
wait
ids=$(for i in $(seq 1 10); do field "$(cat "$work/up-$i")" id; done | sort -u | wc -l | tr -d ' ')
created=$(cat "$work"/up-* | grep -o '} 201' | wc -l | tr -d ' ')
[ "$created" = 10 ] && [ "$ids" = 10 ] || fail "$created of 10 uploads were created, $ids distinct ids"
[ "$(stored_keys)" = "$((before + 12))" ] || fail "the directory has $(stored_keys) files, want $((before + 12))"
for i in 1 5 10; do
  fid=$(field "$(cat "$work/up-$i")" id)
  curl -s -o "$work/c-$i" "http://localhost:8080/api/files/$fid" -H "authorization: Bearer $alice"
  [ "$(sha256sum "$work/c-$i" | cut -d' ' -f1)" = "$(sha256sum "$work/p$i.png" | cut -d' ' -f1)" ] || fail "file $fid is not what was uploaded"
done
ok "10 uploads at once: 10 files, 10 ids, 10 keys, contents intact"

echo "deleting:"
[ "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice")" = 204 ] || fail "delete failed"
for i in 1 2 3 4 5 6; do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice")" = 404 ] || fail "a deleted file is still downloadable"
done
[ "$(stored_keys)" = "$((before + 11))" ] || fail "the bytes were not removed ($(stored_keys) files, want $((before + 11)))"
ok "deleted: 404 from every node, and the bytes are gone from the directory"

echo "a node killed while a file is arriving:"
png "$work/slow.png" 60000
rows_before=$(rpc node1 'IO.write(hd(hd(Platform.Database.Repo.query!("SELECT count(*) FROM stored_files").rows)))')
( upload "$alice" "$work/slow.png" "slow.png" --limit-rate 3k > "$work/slow.out" 2>&1 || true ) &
slow=$!
sleep 3
for n in node1 node2 node3; do compose kill -s KILL "$n" >/dev/null 2>&1 || true; done
wait "$slow" || true
grep -q " 201$" "$work/slow.out" && fail "the slow upload finished before the nodes were killed; the check proves nothing"
for n in node1 node2 node3; do compose start "$n" >/dev/null 2>&1; done
for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
[ "$(stored_keys)" = "$((before + 11))" ] || fail "a half-received upload left a file ($(stored_keys), want $((before + 11)))"
rows_after=$(rpc node1 'IO.write(hd(hd(Platform.Database.Repo.query!("SELECT count(*) FROM stored_files").rows)))')
[ "$rows_before" = "$rows_after" ] || fail "a half-received upload left a row ($rows_before before, $rows_after after)"
ok "all three nodes killed mid-upload: no half file in the directory, no row in the table"
out=$(upload "$alice" "$work/slow.png" "slow.png")
[ "${out##* }" = 201 ] || fail "uploading again after the restart answered: $out"
ok "and the same upload works afterwards"
echo "uploads proof passed"
