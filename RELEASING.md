# Releasing

Two hex packages from this repository, released independently:

| Package | Directory | Tag |
|---|---|---|
| `dandelion` (library) | repo root | `dandelion-vX.Y.Z` |
| `dandelion_new` (generator) | `installer/` | `dandelion_new-vX.Y.Z` |

The library first, when both change: a generated project depends on it.

## Every release

1. Bump `@version` in that package's `mix.exs`. For the library, add a
   `## X.Y.Z` entry to `CHANGELOG.md` (the workflow refuses without one).
2. Commit, push to `main`, wait for CI to be green.
3. Tag and push the tag:

   ```sh
   git tag -a dandelion-v0.1.1 -m "dandelion 0.1.1"
   git push origin dandelion-v0.1.1
   ```

4. Open the run under **Actions → Release**, check the version it printed, and
   **approve** the `hex` environment. It runs the tests, publishes the package
   and its docs, and creates the GitHub release.
5. Check https://hex.pm/packages/dandelion (and `dandelion_new`).

A mistake in the first hour: `mix hex.publish --revert X.Y.Z` locally.
After that, publish the next patch (hex versions can't be overwritten).

## One-time setup

1. **A hex API key.** On your machine:

   ```sh
   mix hex.user key generate --key-name github-actions --permission api:write
   ```

   (`api:write` for all your packages; to limit it, use
   `--permission package:dandelion --permission package:dandelion_new`.)
   It prints the key **once**.

2. **A `hex` environment.** GitHub → Settings → Environments → New environment
   → `hex`. Add yourself under **Required reviewers**, and the key as an
   **environment secret** named `HEX_API_KEY` (not a repository secret: only
   jobs that wait for your approval can read it).

3. **Try it without publishing.** Actions → Release → Run workflow → package
   `dandelion`, *dry run* ticked. It does everything except publish.

Revoke the key any time: `mix hex.user key revoke github-actions` or on
hex.pm → Dashboard → Keys.
