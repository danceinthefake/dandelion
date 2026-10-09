#!/bin/sh
# Keeping an account yours, on the 3-node cluster (compose.cluster.yaml must be up; needs curl and jq).
# The mail server is mailpit (http://localhost:18025 shows what it received):
#
#   1. registering sends a confirmation link; using it confirms the address, once;
#   2. a forgotten password: asking gives the same answer for an address with an account and one
#      without; the link sets a new password, once; a password that is too short does not use it up;
#      an expired link, or a made-up one, is refused; and every session the old password had ends;
#   3. guessing: five wrong passwords lock the address, even for the right one, on every node (the
#      answer carries a retry-after); an address nobody has is locked the same way; a reset unlocks;
#   4. a mail server that is down delays the email and nothing else: asking still answers at once and
#      the link arrives, once, when the mail server is back;
#   5. no link is kept anywhere it could be read: not in the table of links (only a hash), not in the
#      job, not in the sent email's body, not in the audit log.
set -eu
cd "$(dirname "$0")"

compose() { docker compose -f compose.cluster.yaml "$@"; }
rpc() { compose exec -T "$1" bin/acme rpc "$2"; }
ok() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
MAILPIT=http://localhost:18025
API=http://localhost:8080/api

set_accounts() { # ELIXIR keyword changes, on every node, e.g. "resend_gap_seconds: 0"
  for n in node1 node2 node3; do
    rpc $n "Application.put_env(:acme, App.Accounts, Keyword.merge(Application.fetch_env!(:acme, App.Accounts), [$1])); IO.write(:ok)" >/dev/null
  done
}
restore() {
  compose start mailpit >/dev/null 2>&1 || true
  set_accounts "resend_gap_seconds: 60, require_confirmed_email: false" 2>/dev/null || true
}
trap restore EXIT

for n in node1 node2 node3; do
  for _ in $(seq 1 90); do
    [ "$(rpc $n 'IO.write(length(Node.list()))' 2>/dev/null)" = 2 ] && break
    sleep 1
  done
done
./seed.sh >/dev/null
compose start mailpit >/dev/null
for _ in $(seq 1 30); do curl -sf "$MAILPIT/api/v1/info" >/dev/null && break; sleep 1; done
tag="acct$(date +%s)"
admin=$(curl -s -X POST $API/session -H 'content-type: application/json' \
  -d '{"email":"admin@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$admin" ] || fail "can't log in as the seeded admin"
json() { curl -s -X "$1" "$API$2" -H 'content-type: application/json' ${3:+-H "authorization: Bearer $3"} ${4:+-d "$4"}; }
status() { curl -s -o /dev/null -w '%{http_code}' -X "$1" "$API$2" -H 'content-type: application/json' ${3:+-H "authorization: Bearer $3"} ${4:+-d "$4"}; }
login() { json POST /session "" "{\"email\":\"$1\",\"password\":\"$2\"}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }
# mail for an address (and, optionally, a word of the subject): how many messages, and the code in the newest
mails() { curl -s -G "$MAILPIT/api/v1/search" --data-urlencode "query=to:$1 ${2:+subject:$2}" | jq -r '.messages_count // 0'; }
wait_mails() { for _ in $(seq 1 "$3"); do [ "$(mails "$1" "${4:-}" 2>/dev/null)" = "$2" ] && return 0; sleep 1; done; return 1; }
code_in_mail() {
  id=$(curl -s -G "$MAILPIT/api/v1/search" --data-urlencode "query=to:$1 ${2:+subject:$2}" | jq -r '.messages[0].ID')
  curl -s "$MAILPIT/api/v1/message/$id" | jq -r '.Text' | sed -n 's/.*the code is  *\([^ ]*\).*/\1/p'
}
register() { status POST /users "" "{\"email\":\"$1\",\"password\":\"correct horse battery\"}"; }
PW="correct horse battery"
NEW="a brand new password"

echo "confirming an address:"
me="$tag-me@example.com"
[ "$(register "$me")" = 201 ] || fail "registering"
tok=$(login "$me" "$PW")
json GET /me "$tok" | jq -e '.email_confirmed == false' >/dev/null || fail "a new user is already confirmed"
wait_mails "$me" 1 40 || fail "no confirmation email arrived ($(mails "$me"))"
code=$(code_in_mail "$me")
[ -n "$code" ] || fail "no code in the confirmation email"
[ "$(status POST /email/confirm "" "{\"token\":\"$code\"}")" = 200 ] || fail "the confirmation link did not work"
json GET /me "$tok" | jq -e '.email_confirmed == true' >/dev/null || fail "still not confirmed after using the link"
[ "$(status POST /email/confirm "" "{\"token\":\"$code\"}")" = 400 ] || fail "a confirmation link worked twice"
ok "registering sent one email with a link; using it confirmed the address; using it again is a 400"

echo "a forgotten password:"
user="$tag-forgot@example.com"
register "$user" >/dev/null
old_tok=$(login "$user" "$PW")
wait_mails "$user" 1 40 || fail "no confirmation email for $user"
known=$(json POST /password/forgot "" "{\"email\":\"$user\"}")
unknown=$(json POST /password/forgot "" "{\"email\":\"$tag-nobody@example.com\"}")
[ "$known" = "$unknown" ] || fail "asking answers differently for a known and an unknown address: '$known' / '$unknown'"
wait_mails "$user" 2 40 || fail "no reset email arrived ($(mails "$user"))"
sleep 5
[ "$(mails "$tag-nobody@example.com")" = 0 ] || fail "an address with no account was sent an email"
ok "asking answers the same for an address with an account and one without; only the first got an email"
json POST /password/forgot "" "{\"email\":\"$user\"}" >/dev/null
sleep 8
[ "$(mails "$user")" = 2 ] || fail "asking again at once made a second reset email ($(mails "$user") messages)"
ok "asking again within the minute did not send another"

reset_code=$(code_in_mail "$user")
[ "$(status GET /me "$old_tok")" = 200 ] || fail "the session was not valid before the reset"
[ "$(status POST /password/reset "" "{\"token\":\"$reset_code\",\"password\":\"short\"}")" = 422 ] || fail "a short password was not refused"
[ "$(status POST /password/reset "" "{\"token\":\"made-up\",\"password\":\"$NEW\"}")" = 400 ] || fail "a made-up link was accepted"
[ "$(status POST /password/reset "" "{\"token\":\"$reset_code\",\"password\":\"$NEW\"}")" = 200 ] || fail "the reset failed"
[ "$(status POST /password/reset "" "{\"token\":\"$reset_code\",\"password\":\"another password 1\"}")" = 400 ] || fail "a reset link worked twice"
ok "a short password was refused (the link not used up); a made-up link refused; the link worked once"
[ -z "$(login "$user" "$PW")" ] || fail "the old password still works"
[ -n "$(login "$user" "$NEW")" ] || fail "the new password does not work"
for i in 1 2 3 4 5 6; do
  [ "$(status GET /me "$old_tok")" = 401 ] || fail "the old session still works (request $i, through nginx: every node)"
done
ok "the new password works, the old does not, and the session made under the old one is a 401 on all three nodes"

set_accounts "resend_gap_seconds: 0"
json POST /password/forgot "" "{\"email\":\"$user\"}" >/dev/null
wait_mails "$user" 3 40 || fail "no second reset email"
late=$(code_in_mail "$user")
rpc node1 "Platform.Database.Repo.query!(\"UPDATE user_tokens SET expires_at = now() AT TIME ZONE 'utc' - interval '1 second' WHERE user_id = (SELECT id FROM users WHERE email = '$user')\"); IO.write(:ok)" >/dev/null
[ "$(status POST /password/reset "" "{\"token\":\"$late\",\"password\":\"yet another password\"}")" = 400 ] || fail "an expired link worked"
ok "an expired link is refused"

echo "guessing:"
lock="$tag-lock@example.com"
register "$lock" >/dev/null
for i in 1 2 3 4 5; do
  [ "$(status POST /session "" "{\"email\":\"$lock\",\"password\":\"wrong password $i\"}")" = 401 ] || fail "wrong password $i was not a 401"
done
for i in 1 2 3 4 5 6; do
  [ "$(status POST /session "" "{\"email\":\"$lock\",\"password\":\"$PW\"}")" = 429 ] || fail "the right password got through a locked address (request $i)"
done
retry=$(curl -s -D - -o /dev/null -X POST $API/session -H 'content-type: application/json' -d "{\"email\":\"$lock\",\"password\":\"$PW\"}" | grep -i '^retry-after' | tr -d '\r' | sed 's/^[^:]*: *//')
[ "${retry:-0}" -gt 600 ] || fail "retry-after is '$retry', want about 900"
ok "five wrong passwords through the load balancer locked the address; the right one is 429 from all three nodes (retry-after: ${retry}s)"
ghost="$tag-ghost@example.com"
for i in 1 2 3 4 5; do status POST /session "" "{\"email\":\"$ghost\",\"password\":\"wrong password $i\"}" >/dev/null; done
[ "$(status POST /session "" "{\"email\":\"$ghost\",\"password\":\"wrong password 6\"}")" = 429 ] || fail "an address with no account was not locked the same way"
ok "an address nobody has is locked the same way: a lock does not say an account exists"
json POST /password/forgot "" "{\"email\":\"$lock\"}" >/dev/null
wait_mails "$lock" 2 40 || fail "no reset email for the locked address"
[ "$(status POST /password/reset "" "{\"token\":\"$(code_in_mail "$lock")\",\"password\":\"$NEW\"}")" = 200 ] || fail "the reset for the locked address failed"
[ -n "$(login "$lock" "$NEW")" ] || fail "the address is still locked after a reset"
ok "a password reset unlocks it"

echo "the mail server goes away:"
down="$tag-down@example.com"
register "$down" >/dev/null
wait_mails "$down" 1 40 || fail "no confirmation email for $down"
compose stop mailpit >/dev/null 2>&1
start=$(date +%s)
[ "$(status POST /password/forgot "" "{\"email\":\"$down\"}")" = 202 ] || fail "asking failed with the mail server down"
took=$(( $(date +%s) - start ))
[ "$took" -le 3 ] || fail "asking took $took s with the mail server down"
ok "asking answered 202 in $took s with the mail server down"
compose start mailpit >/dev/null
for _ in $(seq 1 30); do curl -sf "$MAILPIT/api/v1/info" >/dev/null && break; sleep 1; done
wait_mails "$down" 2 150 || fail "the reset email never arrived after the mail server came back ($(mails "$down"))"
sleep 5
[ "$(mails "$down")" = 2 ] || fail "the email arrived $(mails "$down") times"
down_code=$(code_in_mail "$down")
[ "$(status POST /password/reset "" "{\"token\":\"$down_code\",\"password\":\"$NEW\"}")" = 200 ] || fail "the late link did not work"
ok "it arrived once the mail server was back, and the link works"

echo "where the links are not:"
for c in "$reset_code" "$late" "$down_code" "$code"; do
  [ -n "$c" ] || fail "an empty code"
  n=$(rpc node1 "%{rows: [[a]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM user_tokens WHERE token_hash = \$1\", [\"$c\"]); %{rows: [[b]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM oban_jobs WHERE args::text LIKE \$1\", [\"%$c%\"]); %{rows: [[d]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM outgoing_emails WHERE body LIKE \$1\", [\"%$c%\"]); IO.write(a + b + d)")
  [ "$n" = 0 ] || fail "a link was found in the database ($n places)"
done
audit=$(curl -s "$API/audit?limit=200" -H "authorization: Bearer $admin")
for c in "$reset_code" "$late" "$down_code" "$code"; do
  if echo "$audit" | grep -qF -- "$c"; then fail "a link is in the audit log"; fi
done
left=$(rpc node1 "%{rows: [[n]]} = Platform.Database.Repo.query!(\"SELECT count(*) FROM outgoing_emails WHERE kind IN ('password_reset', 'email_confirmation') AND status = 'sent' AND body LIKE '%token=%' AND to_address LIKE '$tag-%'\"); IO.write(n)")
[ "$left" = 0 ] || fail "$left sent emails still hold their link"
ok "no link in the table of links (a hash only), in a job's arguments, in a sent email's body, or in the audit log"
for a in password.reset_requested password.reset email.confirmed session.locked; do
  echo "$(curl -s "$API/audit?action=$a&limit=5" -H "authorization: Bearer $admin")" | jq -e '.entries | length > 0' >/dev/null || fail "no $a in the audit log"
done
ok "and what happened is in the audit log: reset asked and made, address confirmed, address locked"

echo "an order and an unconfirmed address:"
gate="$tag-gate@example.com"
register "$gate" >/dev/null
gtok=$(login "$gate" "$PW")
order() { status POST /orders "$gtok" "{\"customer_email\":\"$gate\",\"items\":[{\"sku\":\"A\",\"quantity\":1}]}"; }
[ "$(order)" = 201 ] || fail "an order without the setting was not accepted"
set_accounts "require_confirmed_email: true"
[ "$(order)" = 403 ] || fail "an unconfirmed address could order with the setting on"
wait_mails "$gate" 1 120 Confirm || fail "no confirmation email for $gate"
status POST /email/confirm "" "{\"token\":\"$(code_in_mail "$gate" Confirm)\"}" >/dev/null
[ "$(order)" = 201 ] || fail "a confirmed address could not order"
ok "with the setting on, an unconfirmed address's order is a 403; confirmed, a 201"
echo "accounts proof passed"
