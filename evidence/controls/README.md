# Negative controls

A check that cannot fail proves nothing. Each log here comes from the same proof as in the claims. For most logs this is the cluster proof. For `rejoin` it is the partition proof. We run the proof after we break one thing on purpose. Each proof must fail at the step that depends on the broken thing. It must not fail before that step.

| Log | Broken on purpose | Fails at | Because |
|---|---|---|---|
| [`ordering.log`](ordering.log) | `Dandelion.Queue.Ordered.turn/1` always says "go" | `order N is paid, want refunded` | a refund ran before its payment, and the service dropped it |
| [`cache.log`](cache.log) | `Dandelion.Cache.delete/1` does not tell the other nodes | `node2 still reads the old price` | the delete stayed on one node |
| [`lifeline.log`](lifeline.log) | the service gives back the job of a dead node after a day and not after 10 s | `order N is pending, want refunded` | the event of the held order waited for the job of the dead node |
| [`rejoin.log`](rejoin.log) | `Dandelion.Cache.Listener` does not empty the cache when a node rejoins | `node1's cache was emptied when it rejoined` (the partition proof, claim 09) | an entry cached just before the heal was still there |
| [`dualwrite.log`](dualwrite.log) | an order's events are saved after its transaction commits, with a 1.5 s gap, not inside it | `an order never lacks its events` (the failure proof, claim 13) | a crash fell into the gap, and orders exist without their events |
| [`ratelimit.log`](ratelimit.log) | the rate limit plug is out of the endpoint | `20 guesses were let through` (the reliability proof, claim 14) | nothing counted the guesses |
| [`drain.log`](drain.log) | `Dandelion.Drain.start/1` is not called when a node gets the stop signal | `node2 never said it was draining on /health` (claim 14) | the node went from serving to gone with no warning |
| [`idempotency.log`](idempotency.log) | the `Idempotency-Key` header is ignored | `20 different orders came back` (claim 16) | every repeat made another order |
| [`rollingcut.log`](rollingcut.log) | a stopping node neither waits nor lets requests in flight finish (`DRAIN_DELAY_MS=0`, `SHUTDOWN_TIMEOUT_MS=0`) | `requests were cut off by a stopping node` (claim 15) | the requests of the slow clients got a 502 |
| [`webhooksig.log`](webhooksig.log) | deliveries are signed with the wrong secret | `the signature does not match` (claim 17) | the receiver was not able to trust what it got |
| [`nobreaker.log`](nobreaker.log) | the circuit never opens | `no node opened the circuit for the dead receiver` (claim 17) | a dead receiver was called again and again |
| [`noinvalidate.log`](noinvalidate.log) | changing a flag does not clear the cached copy | `after the pause, orders answered: 201 …` (claim 18) | every node kept serving the old value |
| [`uploadtype.log`](uploadtype.log) | the type of an upload is taken on trust (everything is an image) | `a script called picture.png … was kept as` (claim 19) | a script was stored and served as a PNG |
| [`unshared.log`](unshared.log) | each node has its own uploads directory | `download 1 is not the uploaded file` (claim 19) | the other nodes did not have the file |
| [`noaudit.log`](noaudit.log) | a flag change is not recorded | `the admin's flag, webhook and price changes are there` is never reached (claim 20) | the log lacked a change |
| [`mutable.log`](mutable.log) | the trigger lets UPDATE, DELETE and TRUNCATE through | `from every node, an UPDATE, a DELETE and a TRUNCATE are refused` is never reached (claim 20) | the log was open to a rewrite |
| [`mailnodedupe.log`](mailnodedupe.log) | a message that the service sent goes out again after its job runs again | `sent nothing: still one each` is never reached (claim 21) | the rerun mailed the customer twice |
| [`mailnoretry.log`](mailnoretry.log) | a send that failed for a passing reason is forgotten | `all 6 arrived, each exactly once` is never reached (claim 21) | the mail that the service sent while the server was down was lost |
| [`unsafequery.log`](unsafequery.log) | what the user types reaches the query language | `14 nasty queries` is never reached (claim 22) | an operator that a person typed into the box made the search fail |
| [`noindex.log`](noindex.log) | the full-text index is never created | `the plan uses the GIN index` is never reached (claim 22) | every search read the whole table |
| [`badpanel.log`](badpanel.log) | a panel's metric name has a typo | `and the 16 panels … all have data` is never reached (claim 23) | the panel ran and showed nothing |
| [`nocircuitmetric.log`](nocircuitmetric.log) | a circuit that opens is not counted (the metric is never emitted) | `the mail server stopped` is never reached (claim 23) | nothing on the dashboard said that the service left a dependency alone |
| [`breaking.log`](breaking.log) | the migration renames a column the running version still uses | `in the mixed state only 0 of 30 orders were answered` (claim 24) | the first version was not able to read its own table |
| [`tokenreuse.log`](tokenreuse.log) | a one-time link is not marked used | `using it again is a 400` is never reached (claim 25) | a link worked twice |
| [`nolockout.log`](nolockout.log) | an address is never locked | `five wrong passwords … locked the address` is never reached (claim 25) | the right password got through after the guesses, and a guesser got through too |
| [`norevoke.log`](norevoke.log) | a password change does not end old sessions | `… the session made under the old one is a 401` is never reached (claim 25) | a stolen session survived a reset |
| [`xss.log`](xss.log) | a product's name is put on the page as HTML (`v-html`) | `a name with HTML in it shows as the characters typed` is never reached (claim 26) | what an admin typed became markup |
| [`leakyorders.log`](leakyorders.log) | the orders page stays visible while another page is open | `the orders page is hidden while another page is open` is never reached (claim 26) | the orders list showed on top of every page |
| [`smeared.log`](smeared.log) | the database is backed up table by table, a second apart | `a snapshot, not a smear` is never reached (claim 27) | restored orders lacked their queued events |
| [`nofiles.log`](nofiles.log) | the uploaded files are left out of the backup | `the file downloads with the checksum` is never reached (claim 27) | the file rows came back without bytes |
| [`s3nodelete.log`](s3nodelete.log) | deleting a file never reaches the bucket | `deleted: the row and the object are gone` is never reached (claim 28) | the object stayed in the bucket |
| [`s3unsigned.log`](s3unsigned.log) | requests to the bucket are sent without a signature | `1.5 MB uploaded through the load balancer` is never reached (claim 28) | the bucket refused every request |

The header of each log says what we broke and where the proof must stop (`expected:`). It shows the verdict `ok` if the proof stopped there. The script ([`run.sh`](run.sh)) breaks the library in `example/vendor/dandelion`. The Docker image builds from this copy. The script never breaks `lib/`. If a control does not fail, the script fails.

To run the controls again, run `evidence/record.sh controls`. This takes about 20 minutes.
