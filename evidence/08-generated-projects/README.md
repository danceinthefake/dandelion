# 08 — Generated projects work

Claim: `mix dandelion.new` writes a project that compiles with warnings as errors. The project passes its own format check, its tests, and credo. It runs as a cluster. This is true with everything, without the frontend, and without the example.

Code: the generator (`installer/`), which depends on the library.

The [`run.log`](run.log) is the output of the integration test:

| Test | What it does |
|---|---|
| compiles, tests, credo, with the example | generates, `deps.get`, `compile --warnings-as-errors`, `format --check-formatted`, `test`, `credo --strict` |
| … without the frontend | the same with `--no-frontend` |
| … without the example | the same with `--no-example` |
| the generated frontend builds | `npm ci` and `npm run build` in the generated `assets/` |
| the generated cluster proof passes, with everything | builds the Docker image, starts 3 nodes, runs the project's own `deploy/cluster-proof.sh` |
| … without the example | the same, with the platform-only checks |

Status: The committed log is the run against the published `dandelion` 0.1.1. The header of the log names the version that it found on hex. All 6 tests pass.

Which library: `record.sh tests` builds the generated projects against the published `dandelion` package from hex (`DANDELION_FROM_HEX=1`). Without that variable, the tests point the projects at the library in this checkout. Development uses that library.

Not shown: the published `dandelion_new` archive itself. The tests run the code of the generator from this repository.

To run it again, run `evidence/record.sh tests`. This takes about ten minutes.
