# 22 — Search, in Postgres

Claim: Full-text search over a table needs no second system. It behaves as a user expects.

1. It finds the right things. The table has 20 000 products.
   - A prefix of every word (`gre tea`) finds the green tea and the cup whose description mentions it. The product with that name is first.
   - The answer has a plain-text snippet with `[[highlighted]]` words.
   - `CAFE creme` finds `Café crème`.
   - A typo (`grean tea`) is accepted, and the answer says `"match":"fuzzy"`.
2. Nothing that a user types breaks it. Fourteen nasty queries (operators, quotes, a SQL injection, and 600 characters) all get 200.
3. A change is searchable at once on every node. The proof makes ten renames through the load balancer. After each rename, it searches for the new name and the old name three times (once for each node). It finds no stale answer. A deleted product is gone from the next search. The service indexes nothing on the side, so nothing can be late.
4. It uses the index. The query plan names the GIN index and does not scan 20 000 rows. The proof times 200 searches through the load balancer. On this machine the median is about 75 ms and the p95 is about 180 ms.

Code: `Dandelion.Search` and `Dandelion.Search.Migration` in the library (a generated `tsvector` column, a GIN index, a trigram index, and a sanitizer for the words of the user). In the example: `ProductService.search/1`, `ProductSearchHandler`, and the admin endpoints that change products. DESIGN.md §10.20 says where this is weaker than a search engine.

Negative controls ([`unsafequery.log`](../controls/unsafequery.log), [`noindex.log`](../controls/noindex.log)): If the text of the user reaches the query language, a typed `&` or `'` makes the search fail, and the proof stops at the nasty queries. If the service creates no index, the plan is a scan, and the proof stops at "the plan uses the GIN index".

Found by running it:
- `ts_headline` cuts its fragment around the match and drops markup after it. You cannot rely on a snippet to show stored HTML. The snippet is plain text, and you must escape it.
- The typo fallback applies when the words matched nothing. If you ask for `black green` and no such product exists, the search finds `Black tea` and `Green tea` as similar words. The answer labels them `fuzzy`.

Not shown:
- Other languages or stemming.
- Real product data.
- Many writers on the same table while searches run.
- A corpus that does not fit in memory.

See [LIMITS.md](../LIMITS.md).

To run it again, run `evidence/record.sh search`. This takes less than a minute. To run the controls, run `ONLY=unsafequery evidence/record.sh controls` and `ONLY=noindex …`.
