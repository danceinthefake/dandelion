#!/bin/sh
# Uploaded files in an S3-compatible bucket instead of a shared directory (compose.cluster.yaml
# must be up; needs curl, sha256sum, head). Run once against each of two servers that are not
# Amazon's — SeaweedFS and Garage — started here (`--profile s3`), the nodes restarted to use them
# (S3_* settings; no volume is needed):
#
#   1. a file uploaded through the load balancer is downloaded, byte for byte, from every node,
#      and its bytes are in the bucket (the adapter lists the key), not in the uploads volume;
#   2. it is the customer's own (another customer gets 404), a program named .png is refused;
#   3. deleting removes the row and the object, and every node answers 404;
#   4. with the bucket stopped, a download and an upload answer 503 with Retry-After (not 500),
#      no row is made for the upload that failed, and when the bucket is back the file is intact;
#   5. a node replaced from scratch still serves the file (nothing was on its disk).
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml --profile s3 "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

work=$(mktemp -d)
cleanup() {
  compose rm -sfv seaweedfs garage >/dev/null 2>&1 || true
  # (the nodes go back to the uploads volume)
  S3_BUCKET= compose up -d node1 node2 node3 >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_cluster() {
  for n in node1 node2 node3; do
    for _ in $(seq 1 120); do
      [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null || true)" = 2 ] && break
      sleep 1
    done
  done
}

login() { # EMAIL PASSWORD -> token
  curl -s -X POST http://localhost:8080/api/session -H 'content-type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
}
upload() { # TOKEN FILE NAME -> "BODY STATUS"
  curl -s -m 30 -w ' %{http_code}' -X POST http://localhost:8080/api/files \
    -H "authorization: Bearer $1" -F "file=@$2;filename=$3;type=image/png"
}
status_of() { echo "${1##* }"; }
field() { echo "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\).*/\1/p"; }
stored_keys() { rpc node1 '{a, c} = App.Files.Services.FileService.storage(); IO.write(a.keys(c) |> Enum.join(" "))'; }
rows() { rpc node1 'IO.write(Platform.Database.Repo.aggregate("stored_files", :count))'; }

{ printf '\211PNG\r\n\032\n'; head -c 1500000 /dev/urandom; } > "$work/file.png"
sum=$(sha256sum "$work/file.png" | cut -d' ' -f1)
printf 'MZ\220\000\003 not a picture' > "$work/program.png"

for backend in seaweedfs garage; do
  echo "$backend:"
  compose up -d "$backend" >/dev/null 2>&1

  case $backend in
    seaweedfs)
      endpoint=http://seaweedfs:8333 region=us-east-1 key=seaweedkey secret=seaweedsecret-local-only host=http://localhost:18333
      for _ in $(seq 1 60); do curl -s -o /dev/null "$host/" && break; sleep 1; done
      for _ in $(seq 1 30); do
        code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --aws-sigv4 "aws:amz:$region:s3" --user "$key:$secret" "$host/uploads")
        [ "$code" = 200 ] && break
        sleep 2
      done
      [ "$code" = 200 ] || fail "SeaweedFS refused to make the bucket ($code)" ;;
    garage)
      endpoint=http://garage:3900 region=garage key=GK1f2a3b4c5d6e7f8091a2b3c4 secret=4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b
      g() { compose exec -T garage /garage "$@" 2>/dev/null; }
      for _ in $(seq 1 60); do g status >/dev/null 2>&1 && break; sleep 1; done
      id=$(g node id -q | cut -d@ -f1)
      g layout assign -z dc1 -c 1G "$id" >/dev/null
      g layout apply --version 1 >/dev/null
      g key import --yes -n acme "$key" "$secret" >/dev/null
      g bucket create uploads >/dev/null
      g bucket allow --read --write --owner uploads --key acme >/dev/null ;;
  esac

  export S3_ENDPOINT=$endpoint S3_BUCKET=uploads S3_REGION=$region S3_ACCESS_KEY_ID=$key S3_SECRET_ACCESS_KEY=$secret
  compose up -d --force-recreate node1 node2 node3 >/dev/null 2>&1
  wait_cluster
  ./seed.sh >/dev/null
  adapter=$(rpc node1 '{a, _} = App.Files.Services.FileService.storage(); IO.write(inspect(a))')
  [ "$adapter" = "Dandelion.Storage.S3" ] || fail "the nodes use $adapter, not the S3 adapter"

  tag="s3-$backend-$(date +%s)"
  for who in alice bob; do
    curl -s -o /dev/null -X POST http://localhost:8080/api/users -H 'content-type: application/json' \
      -d "{\"email\":\"$tag-$who@example.com\",\"password\":\"correct horse battery\"}"
  done
  alice=$(login "$tag-alice@example.com" "correct horse battery")
  bob=$(login "$tag-bob@example.com" "correct horse battery")
  [ -n "$alice" ] && [ -n "$bob" ] || fail "can't sign in the two customers"

  out=$(upload "$alice" "$work/file.png" "holiday.png")
  [ "$(status_of "$out")" = 201 ] || fail "uploading to $backend answered: $out"
  id=$(field "$out" id)
  key_in_bucket=$(stored_keys)
  [ -n "$key_in_bucket" ] || fail "the bucket holds no object after the upload"
  files_on_volume=$(compose exec -T node1 sh -c 'find /data/uploads -type f | wc -l' | tr -d '\r ')
  [ "$files_on_volume" = 0 ] || fail "$files_on_volume files were written to the uploads volume"
  ok "1.5 MB uploaded through the load balancer: the bucket holds it, the uploads volume has no file"

  for n in 1 2 3 4 5 6; do
    curl -s -m 20 -o "$work/dl" "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice"
    [ "$(sha256sum "$work/dl" | cut -d' ' -f1)" = "$sum" ] || fail "download $n differs from what was uploaded"
  done
  ok "6 downloads (all three nodes) have the checksum it was uploaded with"

  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $bob")" = 404 ] \
    || fail "another customer was not told 404"
  out=$(upload "$alice" "$work/program.png" "picture.png")
  [ "$(status_of "$out")" = 400 ] || fail "a program named .png answered: $out"
  ok "another customer gets 404; a program named .png is refused (400), by what the bytes are"

  curl -s -o /dev/null -X DELETE "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice"
  [ "$(rows)" = 0 ] || fail "the row is still there after deleting"
  [ -z "$(stored_keys)" ] || fail "the object is still in the bucket after deleting: $(stored_keys)"
  for _ in 1 2 3 4 5 6; do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice")" = 404 ] \
      || fail "a deleted file is still served"
  done
  ok "deleted: the row and the object are gone, 404 from every node"

  out=$(upload "$alice" "$work/file.png" "again.png")
  id=$(field "$out" id)
  [ "$(status_of "$out")" = 201 ] || fail "uploading again answered: $out"
  compose stop "$backend" >/dev/null 2>&1
  rows_before=$(rows)
  hdr=$work/hdr
  code=$(curl -s -m 30 -D "$hdr" -o /dev/null -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice")
  [ "$code" = 503 ] || fail "a download with the bucket stopped answered $code, want 503"
  grep -qi '^retry-after' "$hdr" || fail "the 503 has no Retry-After"
  out=$(upload "$alice" "$work/file.png" "lost.png")
  [ "$(status_of "$out")" = 503 ] || fail "an upload with the bucket stopped answered: $out"
  [ "$(rows)" = "$rows_before" ] || fail "an upload that failed left a row"
  ok "bucket stopped: download and upload answer 503 with Retry-After, and the failed upload left no row"

  compose start "$backend" >/dev/null 2>&1
  for _ in $(seq 1 60); do
    code=$(curl -s -m 20 -o "$work/dl" -w '%{http_code}' "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice")
    [ "$code" = 200 ] && break
    sleep 2
  done
  [ "$code" = 200 ] || fail "the file is not served after the bucket came back ($code)"
  [ "$(sha256sum "$work/dl" | cut -d' ' -f1)" = "$sum" ] || fail "the file changed while the bucket was stopped"
  ok "bucket back: the file is intact"

  compose rm -sfv node3 >/dev/null 2>&1
  compose up -d node3 >/dev/null 2>&1
  wait_cluster
  for n in 1 2 3 4 5 6; do
    curl -s -m 20 -o "$work/dl" "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice"
    [ "$(sha256sum "$work/dl" | cut -d' ' -f1)" = "$sum" ] || fail "download $n after replacing a node differs"
  done
  ok "a node replaced from scratch serves it too: nothing was on its disk"

  curl -s -o /dev/null -X DELETE "http://localhost:8080/api/files/$id" -H "authorization: Bearer $alice"
  compose rm -sfv "$backend" >/dev/null 2>&1
done

echo "s3 proof passed"
