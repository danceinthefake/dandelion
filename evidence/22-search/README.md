# 22 — Search, in Postgres

**Claim.** Full-text search over a table needs no second system, and behaves like one a user
would expect:

1. **Finds the right things.** With 20 000 products in the table: a prefix of every word
   (`gre tea`) finds the green tea and the cup whose description mentions it, **the product
   named for it first**; the answer has a `[[highlighted]]` plain-text **snippet**; `CAFE
   creme` finds `Café crème`; a typo (`grean tea`) is forgiven and the answer says
   `"match":"fuzzy"`.
2. **Nothing a user types breaks it.** Fourteen nasty queries (operators, quotes, a SQL
   injection, 600 characters) are all answered 200.
3. **A change is searchable at once, on every node.** Ten renames through the load balancer,
   each searched for by its new name and its old name three times (the three nodes) straight
   after: **no stale answer**; a deleted product is gone from the very next search. Nothing is
   indexed on the side, so there is nothing to be late.
4. **It uses the index.** The query plan names the GIN index, not a scan of 20 000 rows; 200
   searches through the load balancer are timed (median about 75 ms, p95 about 180 ms, on this
   machine).

**Code:** `Dandelion.Search` and `Dandelion.Search.Migration` in the library (a generated
`tsvector` column, a GIN index, a trigram index; a sanitiser for the user's words);
`ProductService.search/1`, `ProductSearchHandler` and the admin endpoints that change products in
the example. DESIGN.md §10.20 says where this is weaker than a search engine.

**Negative controls** ([`unsafequery.log`](../controls/unsafequery.log),
[`noindex.log`](../controls/noindex.log)): with the user's text reaching the query language, a typed
`&` or `'` makes the search fail and the proof stops at the nasty queries; with no index created,
the plan is a scan and the proof stops at "the plan uses the GIN index".

**Found by running it:** `ts_headline` cuts its fragment around the match and drops markup after
it, so a snippet cannot be relied on to show stored HTML (it is plain text, to be escaped); and the
typo fallback applies when the words matched *nothing*, so asking for `black green` with no such
product finds `Black tea` and `Green tea` as similar words, which the answer labels `fuzzy`.

**Not shown:** other languages or stemming; real product data; many writers on the same table
while searching; a corpus that does not fit in memory. See [LIMITS.md](../LIMITS.md).

**Re-run:** `evidence/record.sh search` (under a minute); controls:
`ONLY=unsafequery evidence/record.sh controls`, `ONLY=noindex …`.
