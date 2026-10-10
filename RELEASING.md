# Releasing

This repository has two hex packages. Each package has its own release.

| Package | Directory | Tag |
|---|---|---|
| `dandelion` (library) | repo root | `dandelion-vX.Y.Z` |
| `dandelion_new` (generator) | `installer/` | `dandelion_new-vX.Y.Z` |

If both packages change, release the library first. A generated project depends on the library.

## Every release

1. Change `@version` in the `mix.exs` of the package.
2. For the library, add a `## X.Y.Z` entry to `CHANGELOG.md`. The workflow refuses to run without it.
3. Commit the change and push it to `main`. Wait until CI is green.
4. Make a tag and push the tag:

   ```sh
   git tag -a dandelion-v0.1.1 -m "dandelion 0.1.1"
   git push origin dandelion-v0.1.1
   ```

5. Open the run under **Actions → Release**. Make sure that the version it printed is correct.
6. Approve the `hex` environment. The workflow runs the tests, publishes the package and its docs, and creates the GitHub release.
7. Make sure that the package is on https://hex.pm/packages/dandelion (and `dandelion_new`).

If you push a tag for a version that is already on hex, the run does not fail. The run says "already on hex" and skips all steps. This happens, for example, after you move a tag.

## Mistakes

If you find a mistake in the first hour, run `mix hex.publish --revert X.Y.Z` on your machine. After the first hour, publish the next patch version. Hex does not let you overwrite a version.

## One-time setup

1. Make a hex API key. On your machine, run:

   ```sh
   mix hex.user key generate --key-name github-actions --permission api:write
   ```

   This key can write to all your packages. To limit the key, use `--permission package:dandelion --permission package:dandelion_new`. The command prints the key one time. Save the key.

2. Make a `hex` environment. In GitHub, open Settings → Environments → New environment, and name it `hex`.
3. Under **Required reviewers**, add yourself.
4. Add the key as an **environment secret** named `HEX_API_KEY`. Do not use a repository secret. Only jobs that wait for your approval can read an environment secret.
5. Try the workflow without a publish. Open Actions → Release → Run workflow. Select the package `dandelion` and tick *dry run*. The workflow does all steps except the publish.

To revoke the key, run `mix hex.user key revoke github-actions`. You can also use hex.pm → Dashboard → Keys.
