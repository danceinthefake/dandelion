# From zero to a three-node cluster

This tutorial takes about twenty minutes. The first Docker build takes a few more minutes. You need Erlang and Elixir ([mise](https://mise.jdx.dev) installs them), Docker, `curl`, and `jq`. It is for `dandelion_new` 0.2.1 or later.

## 1. Make a project

```sh
mix archive.install hex dandelion_new
mix dandelion.new shop_demo
cd shop_demo
```

The command makes a service with the layout of a Go service (`lib/platform/` and `lib/app/<domain>/`). It also makes a Vue console and a compose file. The compose file runs three copies of the service behind nginx.

## 2. Start the cluster

```sh
docker compose -f deploy/compose.cluster.yaml up -d --build
deploy/seed.sh      # a few products, two users
```

The first build takes a few minutes. The next builds take seconds. Run `curl localhost:8080/health`. If it answers `{"status":"ok"}`, three nodes run and they found each other through Postgres. You do not install anything else.

## 3. Sign in and make orders on two nodes

1. Open http://localhost:8080 in two browsers.
2. Sign in as `admin@example.com` with the password `local-password-1`. This password is public and is for local use only.
3. Read the node name on the page. nginx gives each browser its own node.
4. Make an order in one browser.

The order appears in the other browser at once. The "online now" count shows both browsers.

![two browsers on two different nodes](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/02-live-feed/live-feed.gif)

The stack has no Redis and no socket server. The nodes connect to each other. This is claim 02 of the [evidence](evidence/).

You can do the same from the command line. Log in as the customer and make an order. Then make sure that the API needs the token:

```sh
TOKEN=$(curl -s -X POST localhost:8080/api/session -H 'content-type: application/json' \
  -d '{"email":"customer@example.com","password":"local-password-1"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":2}]}'
curl -o /dev/null -w '%{http_code}\n' localhost:8080/api/orders      # 401: no token
```

The price comes from the products table. It never comes from the request. A customer sees only their own orders. The token works on any of the three nodes because the server signs it and does not store it.

## 4. Follow one order across nodes

1. Open http://localhost:16686 (Jaeger).
2. Select the service that has the name of your app (`shop_demo`).
3. Select the operation `POST /api/orders` and click **Find Traces**.
4. Open one trace.

The trace shows the request and its database queries. It also shows the background jobs that the order queued: its confirmation email, the customer statistics, and the webhook fan-out. A different node than the request node can run these jobs. To see the node, click a span and open *Process*. The value `service.instance.id` is the node.

![an order's trace in Jaeger: the request, its queries, and the jobs it queued](https://raw.githubusercontent.com/danceinthefake/dandelion/main/evidence/11-tracing/jaeger-ui.png)

## 5. Kill a node

```sh
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 3
docker compose -f deploy/compose.cluster.yaml kill -s KILL node2
curl -s localhost:8080/metrics | grep platform_cluster_nodes_count     # 2, within seconds
curl localhost:8080/health                                              # still ok
docker compose -f deploy/compose.cluster.yaml start node2              # back to 3 in ~15 s
```

The other nodes run again the jobs that the dead node ran. A payment event for one order never runs before the event that came first.

## 6. Deploy without dropping a request

A deploy stops nodes and starts new nodes. In the first terminal, make orders without a stop and count the answers. In the second terminal, stop and start the nodes one at a time, as a deploy does:

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

Terminal 1 must count only `201`. A node that gets the stop signal says so on `/health` with a 503. It keeps serving, finishes the requests that it has, and then exits. The other nodes continue to work. This is claim 15 of the [evidence](evidence/). Claim 14 has the separate parts and says what it cannot show.

## 7. Make it say no, and ask again safely

### A client that asks twice

If you send an order with an `Idempotency-Key`, the service makes the order one time. This is true when the request arrives many times. A timeout or a double click can cause this.

```sh
for i in 1 2; do curl -s -i -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -H 'idempotency-key: my-first-order' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":1}]}' | grep -iE '^HTTP|^idempotent|"id"'; done
# 201 the first time; 200 and `idempotent-replayed: true` the second, the same order id
```

### A switch that you can flip while the app runs

Pause new orders on every node, and then turn them on again. You need an admin token. Make the `ADMIN` variable in the same way as `TOKEN`, with `admin@example.com`.

```sh
curl -X PUT localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"value":false}'
curl -i -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"customer_email":"sari@example.com","items":[{"sku":"TEA-01","quantity":1}]}'   # 503, retry-after: 30
curl -X PUT localhost:8080/api/flags/orders.enabled -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"value":true}'
```

### A client that guesses passwords

The service limits logins for each address. The limit is 10 each minute for each node. The compose file lifts the limit so that the proofs can make hundreds of requests. Lower the limit and guess passwords:

```sh
RATE_LIMIT_AUTH=3 docker compose -f deploy/compose.cluster.yaml up -d node1 node2 node3
sleep 40; for i in $(seq 1 20); do curl -s -o /dev/null -w '%{http_code} ' -X POST localhost:8080/api/session \
  -H 'content-type: application/json' -d '{"email":"nobody@example.com","password":"wrong-password-1"}'; done; echo
# 401 401 401 … then 429 429 429 (with a retry-after); 3 nodes each allow 3
docker compose -f deploy/compose.cluster.yaml up -d node1 node2 node3      # back to the default
```

This is claims 14, 16, and 18 of the [evidence](evidence/).

## 8. See who changed what

The service records the flag changes above, the failed logins, order cancels, price changes, and more. It records each change in the same transaction as the change. The table does not let anyone rewrite an entry.

```sh
curl -s "localhost:8080/api/audit?action=flag.&limit=3" -H "authorization: Bearer $ADMIN" \
  | jq -c '.entries[] | {actor, action, subject, details}'
# {"actor":"user:1","action":"flag.set","subject":"flag:orders.enabled","details":{"value":true}} …
```

Each entry has the `request_id` of the request that made it. The same id is in the `x-request-id` header of the response, in the logs, and in the trace. This is claim 20.

## 9. Tell the outside world: webhooks and email

### A webhook

The compose file has a receiver named `hook-receiver`. It prints what it gets. Register a URL, make an order, and read what arrived:

```sh
curl -X POST localhost:8080/api/webhooks -H "authorization: Bearer $ADMIN" -H 'content-type: application/json' \
  -d '{"url":"http://hook-receiver/hook","events":["order.created"]}'      # shows the secret, once
curl -s -o /dev/null -X POST localhost:8080/api/orders -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"customer_email":"hook@example.com","items":[{"sku":"TEA-01","quantity":1}]}'
sleep 6; docker compose -f deploy/compose.cluster.yaml logs --no-log-prefix hook-receiver | tail -1
# time | webhook-id | timestamp | v1,signature | the JSON body
```

The receiver makes sure that the signature is valid with `Dandelion.Webhook.verify/4`. If you stop `hook-receiver`, the deliveries wait and the service tries them again. The circuit for that host opens. If you start the receiver, the deliveries arrive. This is claim 17.

### Email

Each order also sends an email to its customer. The compose file has a mail server that keeps what it receives. Open it at http://localhost:18025.

```sh
curl -s "localhost:18025/api/v1/search?query=to%3Ahook%40example.com" | jq -c '.messages[0] | {Subject, To: .To[0].Address}'
docker compose -f deploy/compose.cluster.yaml stop mailpit      # the mail server goes away …
# … make an order: it is accepted at once, its email waits; start it again and it arrives, once
docker compose -f deploy/compose.cluster.yaml start mailpit
```

This is claim 21. If you set `SMTP_HOST`, the mail goes to your server.

## 10. Search, and keep files

### Search

Search is Postgres full-text search. Nothing is indexed on the side.

```sh
curl -s 'localhost:8080/api/search/products?q=gre' | jq -c '.results[] | {sku, name}'     # a prefix finds "Green tea"
curl -s 'localhost:8080/api/search/products?q=grean' | jq -c '{match, results: [.results[].name]}'   # a typo: "match":"fuzzy"
```

An admin adds and renames products with `POST /api/products` and `PUT /api/products/:sku/details`. The change is searchable on every node at once. This is claim 22.

### Files

The three nodes share one directory, and the service keeps files in it.

```sh
printf '\211PNG\r\n\032\nhello' > pic.png
curl -s -X POST localhost:8080/api/files -H "authorization: Bearer $TOKEN" -F 'file=@pic.png;filename=pic.png'
curl -s -o out.png localhost:8080/api/files/1 -H "authorization: Bearer $TOKEN"; cmp pic.png out.png && echo same bytes
```

The type of a file comes from its bytes and not from its name. Downloads are attachments. This is claim 19.

### Files in a bucket instead

The uploads above went to a Docker volume that the three nodes share. You can keep them in an S3-compatible bucket instead. Amazon, Google, Cloudflare R2, or a small server that you run yourself can provide the bucket. Set five variables on the nodes:

- `S3_ENDPOINT`
- `S3_BUCKET`
- `S3_REGION`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`

Nothing else changes, and you do not need a volume. Run `./deploy/s3-proof.sh` to try this against SeaweedFS and Garage. This is claim 28. The proof includes a bucket that stops for a while. Uploads and downloads then answer 503, and no file is lost or half made.

## 11. Do it all from the browser

The console at http://localhost:8080 has a page for each item above. Sign in as the admin. To see what a customer sees, sign in as the customer. These are the pages:

- **Products.** Type `gre` and watch the list get shorter as you type. Try `grean tea`. This is a typo, and the page says that the names are only close. Add a product as the admin with a description. Search for a word in the description, and the page highlights the match. Put `<b>bold</b>` in a name. The page shows the characters and never shows bold text.
- **Settings.** The *Accept new orders* switch pauses orders on every node. Turn it off, go to *Orders*, and make an order. The page says "orders are paused". Turn the switch on again.
- **Audit log.** This page shows the switch that you flipped and who flipped it. Filter to *settings*.
- **Webhooks.** Add `http://hook-receiver/hook`. The page shows the signing secret one time.
- **Files.** Drop a PNG or a PDF. A progress bar shows, and then a list. Download the file again. The page refuses a program that has the name `.png`.
- **Create an account.** Use the link on the sign-in page. The console signs you in and says that the address is not confirmed. Open http://localhost:18025, which is the mail server that keeps what it receives. Click the link in the email, and the address is confirmed. *Forgot your password?* works in the same way. Five wrong passwords lock the address.

This is claim 26. A real browser does all of this and checks it.

## 12. Lose everything, and get it back

The cluster survives a node failure, a network split, and a deploy. It cannot survive the loss of the state itself. Make a backup. The cluster continues to serve while the backup runs.

```sh
./deploy/backup.sh ~/backup-1       # the database in one snapshot, then the uploaded files
```

Now destroy the cluster. The command `docker compose -f deploy/compose.cluster.yaml down -v` removes the containers, Postgres, and the uploads volume. Everything is gone. Only the backup directory is left.

```sh
./deploy/restore.sh ~/backup-1      # checks the backup, replaces the database, puts the files back, starts the nodes
```

After about ten seconds, sign in with the same passwords. Search for your products and download your files. All of them are there. The orders that the nodes were still processing finish. Run `./deploy/backup-proof.sh` to do this while the cluster is busy with orders. It makes sure that each claim holds. This is claim 27.

## 13. Watch it

Open http://localhost:13000 (Grafana). You do not need a login to look. The dashboard shows requests, latency, errors, what the service refuses, the circuits of the services that it calls, waiting jobs, the database, and the cache. Make some of the events above happen and watch the panels move. This is claim 23.

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

Each line that a script prints is a claim. The [`evidence/`](evidence/) directory has the same runs recorded. It also has the negative controls. In a negative control, we break a feature on purpose, and the same proof must fail. The directory also has the list of [what we did not prove](evidence/LIMITS.md).

## 15. Add your own resource

```sh
docker compose up -d           # Postgres on localhost:55432
mix setup && mix test          # about a minute the first time
mix dandelion.gen.domain Billing Invoice number:string amount_cents:integer paid:boolean
mix ecto.migrate && mix test
mix phx.server                 # http://localhost:4000
```

The generator writes the model, repo, service, handler, migration, tests, and routes in the layout of the project. All of them are behind the login. The routes go in the file of the domain, `lib/app/billing/routes.ex`. A new domain also gets one line in [`lib/app/router.ex`](example/lib/app/router.ex), which mounts every domain. Run `mix phx.routes App.Router` to list all routes. Add the rules by hand in the same way as `lib/app/shop/`. The rules are who can see what, a cancel, and an event.

## 16. Clean up

```sh
docker compose -f deploy/compose.cluster.yaml down -v
```

## Where to go next

The [`phrasebook/`](phrasebook/) directory maps each Go habit to the Elixir way in 19 short pages. The file [`DESIGN.md`](DESIGN.md) explains why we built it this way.
