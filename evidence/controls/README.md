# Negative controls

A check that can't fail proves nothing. Each log here is the **same proof** as in
the claims (the cluster proof, or for `rejoin` the partition proof), run after one thing was broken **on purpose**. Each
must fail, at the step that depends on the broken thing, and not before.

| Log | Broken on purpose | Fails at | Because |
|---|---|---|---|
| [`ordering.log`](ordering.log) | `Dandelion.Queue.Ordered.turn/1` always says "go" | `order N is paid, want refunded` | a refund ran before its payment and was dropped |
| [`cache.log`](cache.log) | `Dandelion.Cache.delete/1` no longer tells the other nodes | `node2 still reads the old price` | the delete stayed on one node |
| [`lifeline.log`](lifeline.log) | a dead node's job is given back after a day, not 10 s | `order N is pending, want refunded` | the held order's event waited for the dead node's job |

| [`rejoin.log`](rejoin.log) | `Dandelion.Cache.Listener` no longer empties the cache when a node rejoins | `node1's cache was emptied when it rejoined` (the partition proof, claim 09) | an entry cached just before the heal was still there |

| [`dualwrite.log`](dualwrite.log) | an order's events are saved after its transaction commits, with a 1.5 s gap, not inside it | `an order never lacks its events` (the failure proof, claim 13) | a crash fell into the gap: orders exist without their events |

| [`ratelimit.log`](ratelimit.log) | the rate limit plug is out of the endpoint | `20 guesses were let through` (the reliability proof, claim 14) | nothing counted the guesses |

| [`drain.log`](drain.log) | `Dandelion.Drain.start/1` is no longer called when a node is told to stop | `node2 never said it was draining on /health` (claim 14) | the node went from serving to gone, with no warning |

| [`idempotency.log`](idempotency.log) | the `Idempotency-Key` header is ignored | `20 different orders came back` (claim 16) | every repeat made another order |

| [`rollingcut.log`](rollingcut.log) | a stopping node neither waits nor lets requests in flight finish (`DRAIN_DELAY_MS=0`, `SHUTDOWN_TIMEOUT_MS=0`) | `requests were cut off by a stopping node` (claim 15) | the slow clients' requests got a 502 |

| [`webhooksig.log`](webhooksig.log) | deliveries are signed with the wrong secret | `the signature does not match` (claim 17) | the receiver could not trust what it got |

| [`nobreaker.log`](nobreaker.log) | the circuit never opens | `no node opened the circuit for the dead receiver` (claim 17) | a dead receiver was called again and again |

| [`noinvalidate.log`](noinvalidate.log) | changing a flag does not clear the cached copy | `after the pause, orders answered: 201 …` (claim 18) | every node kept serving the old value |

| [`uploadtype.log`](uploadtype.log) | the type of an upload is taken on trust (everything is an image) | `a script called picture.png … was kept as` (claim 19) | a script was stored and served as a PNG |

| [`unshared.log`](unshared.log) | each node has its own uploads directory | `download 1 is not the uploaded file` (claim 19) | the other nodes did not have the file |

| [`noaudit.log`](noaudit.log) | a flag change is not recorded | `the admin's flag, webhook and price changes are there` is never reached (claim 20) | the log lacked a change |

| [`mutable.log`](mutable.log) | the trigger lets UPDATE, DELETE and TRUNCATE through | `from every node, an UPDATE, a DELETE and a TRUNCATE are refused` is never reached (claim 20) | the log could be rewritten |

Each log's header says what was broken, where the proof must stop
(`expected:`), and the verdict `ok` if it did. The script
([`run.sh`](run.sh)) breaks the library in `example/vendor/dandelion` — the
copy the Docker image is built from — never in `lib/`, and fails if a control
does *not* fail.

**Re-run:** `evidence/record.sh controls` (about 20 minutes).
