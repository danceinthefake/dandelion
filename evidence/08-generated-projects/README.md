# 08 — Generated projects work

**Claim.** `mix dandelion.new` writes a project that compiles with warnings as
errors, passes its own format check, tests and credo, and runs as a cluster —
with everything, without the frontend, and without the example.

**Code:** the generator (`installer/`), which depends on the library.

[`run.log`](run.log) is the integration test output:

| Test | What it does |
|---|---|
| compiles, tests, credo — with the example | generates, `deps.get`, `compile --warnings-as-errors`, `format --check-formatted`, `test`, `credo --strict` |
| … without the frontend | the same with `--no-frontend` |
| … without the example | the same with `--no-example` |
| the generated frontend builds | `npm ci` and `npm run build` in the generated `assets/` |
| the generated cluster proof passes — with everything | builds the Docker image, starts 3 nodes, runs the project's own `deploy/cluster-proof.sh` |
| … without the example | the same, with the platform-only checks |

**Status:** the committed log is the run against the published `dandelion` 0.1.1
(the log header names the version it found on hex), all 6 passing.

**Which library:** `record.sh tests` builds the generated projects against the
**published** `dandelion` package from hex (`DANDELION_FROM_HEX=1`); without
that variable the tests point them at the library in this checkout, which is
what development uses.

**Not shown:** the published `dandelion_new` archive itself — the tests run the
generator's code from this repository.

**Re-run:** `evidence/record.sh tests` (about ten minutes)
