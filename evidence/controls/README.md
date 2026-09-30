# Negative controls

A check that can't fail proves nothing. Each log here is the **same cluster
proof** as in the claims, run after one thing was broken **on purpose**. Each
must fail, at the step that depends on the broken thing, and not before.

| Log | Broken on purpose | Fails at | Because |
|---|---|---|---|
| [`ordering.log`](ordering.log) | `Dandelion.Queue.Ordered.turn/1` always says "go" | `order N is paid, want refunded` | a refund ran before its payment and was dropped |
| [`cache.log`](cache.log) | `Dandelion.Cache.delete/1` no longer tells the other nodes | `node2 still reads the old price` | the delete stayed on one node |
| [`lifeline.log`](lifeline.log) | a dead node's job is given back after a day, not 10 s | `order N is pending, want refunded` | the held order's event waited for the dead node's job |

Each log's header says what was broken, where the proof must stop
(`expected:`), and the verdict `ok` if it did. The script
([`run.sh`](run.sh)) breaks the library in `example/vendor/dandelion` — the
copy the Docker image is built from — never in `lib/`, and fails if a control
does *not* fail.

**Re-run:** `evidence/record.sh controls` (about 10 minutes).
