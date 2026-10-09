# From zero to a three-node cluster

About twenty minutes of your time, plus the first Docker build (a few minutes).
You need Erlang and Elixir ([mise](https://mise.jdx.dev) installs them), Docker,
`curl` and `jq`. Written for `dandelion_new` 0.2.1 or later.

## 1. Make a project

```sh
mix archive.install hex dandelion_new
mix dandelion.new shop_demo
cd shop_demo
```

You get a service laid out like a Go service (`lib/platform/`, `lib/app/<domain>/`),
a Vue console, and a compose file that runs **three copies of it** behind nginx.

## 2. Start the cluster

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
deploy/seed.sh      # a few products, two users
```

The first build takes a few minutes (the next ones seconds). When
`curl localhost:8080/health` says `{"status":"ok"}`, three nodes are running and
have found each other through Postgres: nothing else to install.

## 3. Sign in and make orders on two nodes

Open http://localhost:8080 in **two browsers**, sign in as `admin@example.com`
with password `local-password-1` (public, local only). The page says which node
you are connected to; nginx gives each browser a node. Make an order in one:
it appears in the other at once, and "online now" counts both.

![two browsers on two different nodes](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/02-live-feed/live-feed.gif)

No Redis, no socket server: the nodes are connected to each other. (Claim 02 of
the [evidence](evidence/).)

The same from the command line. Log in as the customer, make an order, and see
that the API needs the token:

```sh
TOKEN=$(curl -s -X POST localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"customer@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":2}]}'
curl -o /dev/null -w '%{http_code}\n' localhost:8080/api/orders      # 401: no token
```

The price comes from the products table, never from the request. A customer sees
only their own orders; the token works on any of the three nodes (it is signed,
not stored).

## 4. Follow one order across nodes

Open http://localhost:16686 (Jaeger). Service: your app's name (`shop_demo`),
operation `POST /api/orders`, **Find Traces**, open one. You see the request, its
database queries, and the background jobs the order queued (its confirmation email,
the customer's stats, the webhook fan-out) — and the jobs may have run on a
**different node** than the request. Click a span, open *Process*:
`service.instance.id` is the node.

![an order's trace in Jaeger: the request, its queries, and the jobs it queued](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/11-tracing/jaeger-ui.png)

## 5. Kill a node

```sh
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 3
docker compose -f deploy/compose.cluster.yaml kill -s KILL node2
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 2, within seconds
curl localhost:8080/health                                              # still ok
docker compose -f deploy/compose.cluster.yaml start node2              # back to 3 in ~15 s
```

Jobs a dead node was running are run again by the others, and a payment event for
one order is never applied before the one that came first.

## 6. Deploy without dropping a request

A deploy stops nodes and starts new ones. In one terminal, keep making orders and count
what comes back; in another, stop and start the nodes one at a time, as a deploy would:

```sh
# terminal 1 (Ctrl-C to see the count): one order every 0.2 s
while true; do curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/api/orders \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":1}]}'; sleep 0.2; done | sort | uniq -c

# terminal 2
for n in node1 node2 node3; do
  docker compose -f deploy/compose.cluster.yaml stop $n
  docker compose -f deploy/compose.cluster.yaml start $n
  sleep 15
done
```

Terminal 1 should count only `201`. A node told to stop says so on `/health` (a 503) while it
keeps serving, then finishes the requests it has and exits; the others carry on. (Claim 15
of the [evidence](evidence/); claim 14 has the pieces, and says what it cannot show.)

## 7. Make it say no, and ask again safely

**A client that asks twice.** An order sent with an `Idempotency-Key` is made once, however
many times it arrives — a retry after a timeout, a double click:

```sh
for i in 1 2; do curl -s -i -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -H 'idempotency-key: my-first-order' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":1}]}' | grep -iE '^HTTP|^idempotent|"id"'; done
# 201 the first time; 200 and `idempotent-replayed: true` the second, the same order id
```

**A switch you can flip while it runs.** Pause new orders on every node, then turn them back
on (an admin token; `ADMIN` is made like `TOKEN`, with `admin@example.com`):

```sh
curl -X PUT localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"value":false}'
curl -i -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":1}]}'   # 503, retry-after: 30
curl -X PUT localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"value":true}'
```

**A client that guesses passwords.** Logging in is limited per address (10 a minute per node
by default; the compose file lifts it so the proofs can make hundreds of requests). Lower it
and guess:

```sh
RATE_LIMIT_AUTH=3 docker compose -f deploy/compose.cluster.yaml up -d node1 node2 node3
sleep 40; for i in $(seq 1 20); do curl -s -o /dev/null -w '%{http_code} ' -X POST localhost:8080/api/session \
  -H 'content-type: application/json' -d '{"email":"nobody@example.com","password":"wrong-password-1"}'; done; echo
# 401 401 401 … then 429 429 429 (with a retry-after); 3 nodes each allow 3
docker compose -f deploy/compose.cluster.yaml up -d node1 node2 node3      # back to the default
```

(Claims 14, 16 and 18 of the [evidence](evidence/).)

## 8. See who changed what

The flag changes above, the failed logins, order cancels, price changes and more are recorded
— in the same transaction as the change, in a table the database will not let anyone rewrite:

```sh
curl -s "localhost:8080/api/audit?action=flag.&limit=3" -H "authorization: Bearer $ADMIN" \
  | jq -c '.entries[] | {actor, action, subject, details}'
# {"actor":"user:1","action":"flag.set","subject":"flag:orders.enabled","details":{"value":true}} …
```

Each entry also has the `request_id` of the request that made it: the id in the `x-request-id`
header of the response, in the logs and in the trace. (Claim 20.)

## 9. Tell the outside world: webhooks and email

**A webhook.** Register a URL (the compose file has a receiver, `hook-receiver`, that prints what it
gets), make an order, and read what arrived:

```sh
curl -X POST localhost:8080/api/webhooks -H "authorization: Bearer $ADMIN" -H 'content-type: application/json' \
  -d '{"url":"http://hook-receiver/hook","events":["order.created"]}'      # shows the secret, once
curl -s -o /dev/null -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"customer_email":"hook@example.com","items":[{"sku":"TEA-01","quantity":1}]}'
sleep 6; docker compose -f deploy/compose.cluster.yaml logs --no-log-prefix hook-receiver | tail -1
# time | webhook-id | timestamp | v1,signature | the JSON body
```

The receiver checks the signature with `Dandelion.Webhook.verify/4`. Stop `hook-receiver` and the
deliveries wait and are retried (and the circuit for that host opens); start it and they arrive.
(Claim 17.)

**Email.** Every order also emails its customer. The compose file has a mail server that keeps
what it receives — http://localhost:18025:

```sh
curl -s "localhost:18025/api/v1/search?query=to%3Ahook%40example.com" | jq -c '.messages[0] | {Subject, To: .To[0].Address}'
docker compose -f deploy/compose.cluster.yaml stop mailpit      # the mail server goes away …
# … make an order: it is accepted at once, its email waits; start it again and it arrives, once
docker compose -f deploy/compose.cluster.yaml start mailpit
```

(Claim 21.) With `SMTP_HOST` set, mail goes to your server instead.

## 10. Search, and keep files

**Search** is Postgres full-text search, with nothing indexed on the side:

```sh
curl -s 'localhost:8080/api/search/products?q=gre' | jq -c '.results[] | {sku, name}'     # a prefix finds "Green tea"
curl -s 'localhost:8080/api/search/products?q=grean' | jq -c '{match, results: [.results[].name]}'   # a typo: "match":"fuzzy"
```

An admin adds and renames products (`POST /api/products`, `PUT /api/products/:sku/details`) and the
change is searchable on every node at once. (Claim 22.)

**Files** are kept on a directory all three nodes share:

```sh
printf '\211PNG\r\n\032\nhello' > pic.png
curl -s -X POST localhost:8080/api/files -H "authorization: Bearer $TOKEN" -F 'file=@pic.png;filename=pic.png'
curl -s -o out.png localhost:8080/api/files/1 -H "authorization: Bearer $TOKEN"; cmp pic.png out.png && echo same bytes
```

What a file is comes from its bytes, not from its name; downloads are attachments. (Claim 19.)

## 11. Do it all from the browser

Everything above has a page in the console at http://localhost:8080 (sign in as the admin, or as the
customer to see what a customer sees):

- **Products** — type `gre` and watch the list narrow as you type; try `grean tea` (a typo: the page says
  the names are only close). Add a product as the admin, with a description, and search for a word in it:
  the match is highlighted. Put `<b>bold</b>` in a name: it shows as the characters, never as bold.
- **Settings** — the *Accept new orders* switch pauses orders on every node. Turn it off, go to *Orders*,
  make one: "orders are paused". Turn it on again.
- **Audit log** — the switch you just flipped, and who flipped it. Filter to *settings*.
- **Webhooks** — add `http://hook-receiver/hook`; the signing secret is shown once.
- **Files** — drop a PNG or a PDF: a progress bar, then a list; download it back. A program renamed
  `.png` is refused.
- **Create an account** (from the sign-in page): the console signs you in and says the address is not
  confirmed. Open http://localhost:18025 (the mail server that keeps what it receives), click the link in
  the email: the address is confirmed. *Forgot your password?* works the same way, and five wrong passwords
  lock the address.

(Claim 26: a real browser does all of this, and checks it.)

## 12. Lose everything, and get it back

The cluster survives a node, a split and a deploy. What it cannot survive is losing the state itself, so
back it up (the cluster keeps serving while this runs):

```sh
./deploy/backup.sh ~/backup-1       # the database in one snapshot, then the uploaded files
```

Now destroy it: `docker compose -f deploy/compose.cluster.yaml down -v` removes the containers, Postgres
and the uploads volume. Everything is gone; the backup directory is all that is left.

```sh
./deploy/restore.sh ~/backup-1      # checks the backup, replaces the database, puts the files back, starts the nodes
```

About ten seconds later, sign in with the same passwords, search for your products, download your files:
all there, and the orders that were still being processed finish. (`./deploy/backup-proof.sh` does this
with the cluster busy making orders and checks every claim; it is claim 27.)

## 13. Watch it

Open http://localhost:13000 (Grafana, no login to look): requests, latency and errors, what is
refused, the circuits of the services it calls, jobs waiting, the database, the cache. Make
some of the above happen and watch the panels move. (Claim 23.)

![the dashboard](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/23-dashboard/dashboard.png)

## 14. Check the claims yourself

```sh
deploy/cluster-proof.sh        # ~10 min: broadcast, jobs, ordering, cache, logins, traces, outage
deploy/partition-proof.sh      # ~4 min: a network split into node1 | node2+node3, then the heal
deploy/failure-proof.sh        # Postgres killed, stopped and frozen under load
deploy/rolling-proof.sh        # a deploy under load: no request cut off, no order lost or doubled
deploy/reliability-proof.sh    # rate limit, a node stopped under load, timeouts
deploy/idempotency-proof.sh    # the same order 20 times at once is one order
deploy/webhook-proof.sh        # signed webhooks, a receiver that goes away
deploy/email-proof.sh          # mail sent once, queued while the mail server is down
deploy/flags-proof.sh  deploy/audit-proof.sh  deploy/uploads-proof.sh
deploy/search-proof.sh  deploy/dashboard-proof.sh
```

Each line it prints is a claim; [`evidence/`](evidence/) has the same runs
recorded, the negative controls (the same proof must *fail* when a feature is
broken on purpose), and [what is not proven](evidence/LIMITS.md).

## 15. Add your own resource

```sh
docker compose up -d           # Postgres on localhost:55432
mix setup && mix test          # about a minute the first time
mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer paid:boolean
mix ecto.migrate && mix test
mix phx.server                 # http://localhost:4000
```

It writes the model, repo, service, handler, migration, tests and routes in the
project's own layout, behind the login. The routes go in the domain's own file,
`lib/app/billing/routes.ex`; a new domain also gets one line in
[`lib/app/router.ex`](example/lib/app/router.ex), which mounts every domain
(`mix phx.routes App.Router` lists them all). Add the rules (who may see what, a
cancel, an event) by hand the way `lib/app/shop/` does.

## 16. Clean up

```sh
docker compose -f deploy/compose.cluster.yaml down -v
```

## Where to go next

[`phrasebook/`](phrasebook/) maps each Go habit to the Elixir way (19 short
pages), and [`DESIGN.md`](DESIGN.md) says why it's built this way.
