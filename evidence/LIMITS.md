# What this evidence does not prove

This page states the limits of our evidence in plain words. You do not have to find them out the hard way.

## One machine, not real VMs

The "cluster" is three containers on one Docker network. It uses the real code paths: Erlang distribution over TCP, Postgres, and a load balancer. It does not test real network latency, firewalls, or clock drift. [`example/deploy/vms.md`](../example/deploy/vms.md) is a guide for real VMs. We did not run it on real VMs.

## The job row of the killed node

We write the job row of the killed node by hand ([03](03-killed-node-job/)). No job is slow enough to catch in the middle of its run. The proof plants the state that a crash leaves behind, and then it kills a node. It shows that the cluster gives such a job back and runs it. It does not show the exact instant of a crash.

## Database failures

[13](13-database-failures/) cuts off the leader with `docker network disconnect`. Under load, it kills Postgres, stops it cleanly, and freezes it. We did not test these cases:

- An outage of minutes. The longest outage is about 25 s.
- A cut that drops connections one at a time.
- A database that is only slow. A frozen database is the extreme case.
- A failover to a replica. The test setup has no replica.

The outages are short: 15 s in [07](07-database-outage/) and up to 25 s in [13](13-database-failures/).

## One kind of partition

[09](09-network-partition/) splits the cluster into `node1 | node2 + node3`. Both halves keep their Postgres connection. To make the split, we give each side a wrong Erlang cookie for the other side. We did not test these cases:

- A half that Postgres also cannot reach.
- An asymmetric split, where A reaches B but B cannot reach A.
- A split that flaps on and off.
- A split that lasts longer than the cache TTL.

The split is a simulation at the Erlang layer. We do not drop packets. The test therefore does not use the TCP timeouts (`net_ticktime`).

## Tracing

We tested tracing only against Jaeger, with every span kept. The spans are standard OTLP, so other backends must work, but we tried none. We did not test sampling. A unit test covers propagation through the ordered queue. The cluster proof does not run it.

## The login

The login is better than a starting point, but it is not hardened. A password reset, address confirmation, and a lockout for each address exist ([25](25-accounts/)). A password change ends every session that exists before it. These limits remain:

- There is no two-factor login.
- The login does not look up breached passwords.
- A stolen token is valid for up to a day unless the password changes, because there is no session table.
- A person can use the lockout to lock a known address for 15 minutes. A reset unlocks the address.
- We saw the links only in mailpit. We did not test a real provider with its spam filters, link scanners that "click" links, and greylisting.

Passwords use PBKDF2-SHA256 at the OWASP 2023 count. Nothing here measures whether that count is enough for your threat model.

## Reliability of the web layer

These limits apply to [14](14-reliability/):

- The rate limit works for each node and each address. A cluster of three allows about three times the limit. Clients behind one address (a company NAT) share one count.
- If you do not say so, the service does not trust the address in `x-forwarded-for`. We did not test this against a spoofing client.
- We read the connection limit back. We did not fill it, because nothing here opens 4096 connections.
- There is no deadline around a whole handler. Deadlines exist only for reading the body, for an idle connection, and for each query.
- We tested the drain with nginx, which does not read `/health`. The test shows that nothing is lost. It does not show that a balancer with health checks moves away within the delay.
- A stop that takes longer than `stop_grace_period` is a kill. `SIGKILL` is also a kill. Claims 03 and 13 cover that case.

## Rolling deploy and retries

These limits apply to [15](15-rolling-deploy/), [16](16-idempotency/), and [24](24-upgrade/).

[15](15-rolling-deploy/) restarts the same image. [24](24-upgrade/) replaces it with a second version that has one more column. We did not test these cases:

- A change in what jobs or messages carry between versions.
- A migration that locks a large table.
- A rollback.

We simulate slow clients with `curl --limit-rate` and with nginx that streams the body.

In several runs, a few requests got a 503 while a node stopped. Some also got a 500 before we fixed the mapping. A Postgres `COMMIT` waited on the disk, and every commit that sends a notification waited behind it. This is a property of NOTIFY in Postgres. It can also be a property of the nearly full disk of this machine, but we did not prove that. A slow disk stalls all writers. Clients must therefore retry. The proof retries with idempotency keys.

The service keeps idempotency keys for the life of the order. They work only on `POST /api/orders`. A key belongs to one customer.

## Webhooks

These limits apply to [17](17-webhooks/):

- The receiver is nginx on the same Docker network. It uses http, and the configuration allows private addresses. The production defaults refuse both. A unit test covers this. The cluster proof does not run it.
- DNS rebinding is possible. A name can point to a public address at the time of the address test and to an address inside our network at the time of the connection. The service does not stop this.
- The service stores secrets in the clear.
- The circuit works for each node. Each of the three nodes learns by itself that a receiver is down. The service therefore makes three times the failed calls before all nodes are quiet.
- We did not test a receiver that answers slowly instead of not at all. We did not test a receiver that answers 410. We did not test a very large backlog after a long outage.

## Flags

These limits apply to [18](18-flags/):

- All users get one value. There is no targeting and no rollout.
- There is no history of changes.
- We split the "cut off" node at the Erlang layer with cookies, as in 09. We do not drop packets.
- The bound on staleness is the cache TTL of one minute. We measured 51 to 57 s.
- If a flag read cannot reach Postgres, it returns the default. The default is correct only if you chose it for that case.

## Uploads

These limits apply to [19](19-uploads/):

- The directory is a Docker volume on one host. The test shows that the nodes see one directory. It does not show how NFS or a cloud file system behaves under load, with locks, or when it is briefly unavailable.
- The service does not collect a file that nothing points at. This happens after a crash between the file and the row.
- There is no virus scan, no quota, no file larger than 5 MB, and no resumable upload.
- Downloads read the file from disk each time. There is no cache and no range request.

## Audit

These limits apply to [20](20-audit/):

- The log is append-only for the application. It is also append-only for a person who uses the database role of the app and does not own the table.
- A superuser or the owner of the table can disable the trigger.
- The entries are not hash-chained and not signed. The log is not tamper-proof evidence against a malicious DBA.
- The log does not record reads.
- Each login attempt is a row. Prune the rows.
- The request id ties an entry to a request only while the logs and traces exist.

## Email

These limits apply to [21](21-email/):

- The mail server is mailpit on the same Docker network. It uses plain SMTP with no login and no TLS.
- We did not test the rate limits, greylisting, TLS, and login of a real provider.
- A unit test with a fake adapter covers a 5xx refusal. We did not see a 5xx refusal from a server.
- The server can accept a message just before a crash. The service can then send the message twice. The window is one write wide.
- The service does nothing with bounces and complaints.
- Without `SMTP_HOST`, the service logs the mail and does not send it.

## Search

These limits apply to [22](22-search/):

- The 20 000 products have synthetic names. They are not a real catalog.
- We measured the timings (median and p95 through the load balancer) on one machine. They say nothing about another machine.
- We tested only the `simple` configuration (no stemming) and only Latin text.
- There are no synonyms, no facets, and no relevance tuning.
- The typo fallback uses trigram similarity. It is weak for very short words.
- Search is public and has no cache. Only the rate limit, 50 rows a page, and 1 000 rows of depth bound its cost.

## Dashboard

We made sure that the dashboard of [23](23-dashboard/) runs and has data. We did not make sure that it is right to act on. These limits remain:

- The thresholds (the red and green of the stat panels) are a starting point.
- No alert rules ship with the dashboard.
- A plausible number in a test of one minute says nothing about the traffic of a day.
- Prometheus and Grafana are single local containers. They have no retention volume and no login to look. They scrape every 2 s.
- The screenshot shows a fresh cluster after a minute of made-up events.

## Files in a bucket

We tried [28](28-s3/) against SeaweedFS and Garage, one node each, in Docker on one machine. We did not try AWS S3, Google Cloud Storage, or any paid service, because we have no cloud budget. The interoperability endpoints of those services are untested here. Their limits are also untested: request rates, eventual behavior, regional endpoints, and virtual-hosted-style URLs. The adapter uses only path-style URLs.

- Files are 5 MB at most. The adapter holds a file whole in memory.
- There is no multipart upload, no streaming, and no presigned URL.
- The adapter does not retry. The caller must retry.
- A bucket that is slow and not down costs a request up to the 15 s timeout.

## Backup and restore

These limits apply to [27](27-backup/):

- The backup is a logical dump at one moment. You cannot recover anything between the dump and the loss. There is no WAL archive and no point-in-time recovery.
- We tried a database of a few thousand orders and a few megabytes of files on one machine. We did not try a large database. The time of `pg_dump` and `pg_restore` grows with the data. The restore time of 11 s here says nothing about your data.
- The backup is a directory on the same disk as the cluster. You must copy it elsewhere, encrypt it, and schedule it.
- The files are a second copy that the script takes after the dump. A file that you delete between the two steps comes back as a row without bytes.
- We restored into the same Postgres major version (18) that made the dump.

## The console

These limits apply to [26](26-console/):

- We drove the console only in Chromium, at one desktop width and one phone width. We did not test Firefox, Safari, a screen reader, the keyboard alone, or a slow network. The component library supports a screen reader and the keyboard. Nothing here proves that the pages do.
- There is no type check of the Vue code. `vue-tsc` is not wired in.
- We opened the emailed-link pages from the link in mailpit. We did not use a mail client that can open or rewrite the link.

## Performance

The evidence has no numbers for throughput, latency, or load. The claims are about behavior and not about speed.

## Best-effort broadcasts

Live broadcasts and presence are best-effort. They are fire-and-forget by design, like Redis pub/sub. A browser that was offline misses pushes. It reloads the list when it joins again. What must not be lost goes through Postgres.

## At least once

The guarantee is "at least once" and not "exactly once". Subscribers and jobs can run twice. For example, another node runs again the job of a dead node. Subscribers and jobs must be safe to repeat. The proof makes sure that a healthy run executes each of them one time.

## Order

Order means arrival at Postgres. It does not mean the time that the clocks of the senders give for an event. If you need that time, send a sequence number.

## One application

We tested the claims on the example service and on projects that we generated from it. We did not test arbitrary code.

## The generator and the library

We test the generator from this checkout and the library from hex. The integration tests run the code of the generator in this repository. They build the generated projects against the published `dandelion` package. They do not exercise the published `dandelion_new` archive. To test it, install the archive and run `mix dandelion.new`.

If you find a way to break a claim that this page does not list, that is a bug. Open an issue.
