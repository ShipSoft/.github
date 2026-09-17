# ShipSoft / .github

Shared GitHub Actions reusable workflows and the organisation profile for
the [ShipSoft](https://github.com/ShipSoft) GitHub organisation.

## Reusable workflows

All workflows live in [`.github/workflows/`](.github/workflows) and are
invoked from caller workflows via `uses:
ShipSoft/.github/.github/workflows/<workflow>.yml@main`.

### `pixi-lock-update.yml`

Opens (or updates) a PR that runs `pixi update` and includes a
human-readable diff. Designed to be called from a `schedule:` trigger.

```yaml
name: Update lock files
on:
  workflow_dispatch:
  schedule:
    - cron: 0 5 1 * *
jobs:
  update:
    uses: ShipSoft/.github/.github/workflows/pixi-lock-update.yml@main
    with:
      base: main         # or master
```

Inputs: `base` (required), `add-paths`, `pr-branch`, `pr-label`.

### `pixi-cmake-build.yml`

Runs a sequence of pixi tasks with `--locked`. Use for CMake-based
projects whose build/test logic is encoded as pixi tasks.

```yaml
name: Build and test
on: [push, pull_request, workflow_dispatch]
jobs:
  build:
    uses: ShipSoft/.github/.github/workflows/pixi-cmake-build.yml@main
    with:
      tasks: '["configure","build","test","ci-sim helium"]'
      lfs: true
      env-vars: |
        QT_QPA_PLATFORM=offscreen
```

Each `tasks` element is shell word-split, so positional pixi task args
(e.g. `ci-sim helium`) work directly.

Compilation is routed through [ccache](https://ccache.dev/) by default
(`hendrikmuhs/ccache-action` installs it and persists the cache between runs;
`CMAKE_{C,CXX}_COMPILER_LAUNCHER` are exported so CMake picks it up at
configure time — no changes needed in the caller's pixi tasks). Set `ccache:
false` if a project misbehaves under ccache, and set `ccache-key` to keep
caches separate across matrix configurations.

Inputs: `tasks` (JSON array, default `'["test"]'`), `lfs`, `runs-on`,
`cache`, `env-vars`, `artifact-name`, `artifact-path`,
`artifact-retention-days`, `ccache` (default `true`), `ccache-key`.

### `doxygen-gh-pages.yml`

Generates Doxygen HTML and publishes it to the `gh-pages` branch,
preserving auxiliary directories such as `plots/`.

```yaml
name: Doxygen
on:
  push:
    branches: [master]
  workflow_dispatch:
jobs:
  deploy:
    uses: ShipSoft/.github/.github/workflows/doxygen-gh-pages.yml@main
    with:
      doxyfile: doxygen/Doxyfile
      preserve: plots
```

Inputs: `doxyfile`, `html-dir`, `preserve`.

### `prek.yml`

Runs the [prek](https://github.com/j178/prek) hooks (a drop-in pre-commit
replacement) via pixi. The hook *tools* come from a pixi `lint` environment, so
versions are tracked in `pixi.lock` and the same hooks run identically on every
platform (no per-hook toolchain downloads). Check-only: it fails on any diff.

When hooks fail on a pull request, the workflow posts the hook output as a
single sticky PR comment (updated in place on subsequent pushes, and flipped to
a "passed" note once the hooks pass). Commenting is **opt-in**: the caller job
must grant `pull-requests: write`. Without it, linting still runs normally and
the comment step is simply a no-op:

```yaml
name: Lint
on:
  pull_request:
  push:
    branches: [main]   # or master
jobs:
  prek:
    permissions:
      contents: read
      pull-requests: write   # omit to lint without PR comments
    uses: ShipSoft/.github/.github/workflows/prek.yml@main
```

> **Do not** add `pull-requests: write` to `prek.yml` itself. A reusable
> workflow that *requests* more than the caller grants fails at startup for
> every caller, so the permission must be granted by each caller instead.

Commenting is also a no-op when the token is read-only for other reasons (e.g.
pull requests from forks); set `comment-on-failure: false` to disable it
explicitly. The job status always reflects the hooks' own pass/fail regardless
of whether the comment is posted.

The caller repo must define a pixi environment (default name `lint`) that
provides `prek` and the hook tools. Inputs: `environment` (default `lint`),
`runs-on`, `cache`, `extra-args`, `comment-on-failure` (default `true`).

### `commit-check.yml`

Validates that every commit in a pull request follows
[Conventional Commits](https://www.conventionalcommits.org/), using
[commitizen](https://commitizen-tools.github.io/commitizen/) (`cz check`). Like
`prek.yml`, commitizen comes from the pixi `lint` environment, so the version is
tracked in `pixi.lock` and matches the local `commit-msg` hook — a single source
of truth, no separately-installed tool to drift. The job only runs on
`pull_request` events (a push has no commit range to check). Merge and revert
commits are skipped by commitizen's default `allowed_prefixes`.

Pair it with the local `commit-msg` hook (below) for fast feedback before push;
this workflow is the authoritative, non-bypassable server-side check.

```yaml
name: Lint
on:
  pull_request:
  push:
    branches: [main]   # or master
jobs:
  prek:
    uses: ShipSoft/.github/.github/workflows/prek.yml@main
  commit-check:
    permissions:
      contents: read
      pull-requests: write   # omit to check without PR comments
    uses: ShipSoft/.github/.github/workflows/commit-check.yml@main
```

Commenting is **opt-in** and follows the same rules as `prek.yml`: the caller
job must grant `pull-requests: write`, and a sticky comment is posted (and
flipped to a "passed" note) on pull requests. **Do not** add `pull-requests:
write` to `commit-check.yml` itself.

The caller repo must define a pixi environment (default name `lint`) that
provides `commitizen`. Inputs: `environment` (default `lint`), `runs-on`,
`cache`, `comment-on-failure` (default `true`).

To enforce the same rule locally, add the commitizen hook to the repo's
`.pre-commit-config.yaml`:

```yaml
  - repo: local
    hooks:
      - id: commitizen
        name: commitizen (conventional commits)
        language: system
        entry: cz check --commit-msg-file
        stages: [commit-msg]
```

and add `commitizen = "*"` to the pixi `[feature.lint.dependencies]`. Install
the hook with `prek install --hook-type commit-msg` (wire it into the repo's
`install-hooks` task so a single `pixi run install-hooks` sets up both the
`pre-commit` and `commit-msg` hooks).

### `release.yml`

Publishes a GitHub Release for a pushed tag. Generates the release body
from conventional commits via [git-cliff](https://git-cliff.org/) using
the caller repo's `cliff.toml`. Pairs with a local release script that
bumps the version, regenerates the changelog and pushes the tag.

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'
jobs:
  release:
    uses: ShipSoft/.github/.github/workflows/release.yml@main
    permissions:
      contents: write
```

Inputs: `cliff-config` (default `cliff.toml`).

### `config-sync.yml`

Opens (or updates) a PR that copies canonical configuration files from this
repository's [`sync/`](sync) directory into the caller repo, keeping shared
configs from drifting. Designed to be called from a `schedule:` trigger, like
`pixi-lock-update.yml`.

```yaml
name: Update shared configs
on:
  workflow_dispatch:
  schedule:
    - cron: 0 6 1 * *
jobs:
  sync:
    permissions:
      contents: write
      pull-requests: write
    uses: ShipSoft/.github/.github/workflows/config-sync.yml@main
    with:
      base: main         # or master
```

Like `prek.yml`, the workflow requests no permissions itself: the caller job
must grant `contents: write` (to push the branch) and `pull-requests: write`
(to open the sync PR). **Do not** add these to `config-sync.yml` itself.

The default `files` list is the **universal set** — currently just
`AI_POLICY.md`, which every repository carries. C++ repos additionally sync
`.clang-tidy` and `cliff.toml` by passing the **C++ set** explicitly:

```yaml
    with:
      base: main         # or master
      files: |
        AI_POLICY.md
        .clang-tidy
        cliff.toml
```

The canonical copies live in `sync/`, and that is where they must be edited.
This repository carries the policy like any other, but its root `AI_POLICY.md`
is a symlink to `sync/AI_POLICY.md`, so the source of truth cannot drift from
what is shipped to everyone else.

Only files without intentional per-repo customisation belong in these lists:
`.clang-format` (include ordering) and `CPPLINT.cfg` (filters) are repo-specific
and are deliberately **not** synced. Callers that customise one of the shared
files pass a narrower `files` list.

Inputs: `base` (required), `files` (newline-separated, default `AI_POLICY.md`),
`pr-branch`, `pr-label`.

### `physics-metrics.yml`

Stores and compares physics-metrics JSON files produced by
[ship-ci-metrics](https://github.com/ShipSoft/ship-ci-metrics)
(`ship-metrics-extract`). References live in git notes
(`refs/notes/ci/physics-metrics/<config>`), one ref per configuration, written
on pushes to the reference branch; pull requests are compared against the
newest reference on that branch and get a sticky summary comment.

The caller's CI must upload the extracted metrics as artifacts matching
`artifact-pattern` (one `metrics-<config>.json` per configuration, e.g. via
`pixi-cmake-build.yml`'s `artifact-name`/`artifact-path` inputs). The compare
job runs `ship-ci-metrics` via `pixi exec`, so it needs no caller pixi
environment — only the `config` file in the caller repo.

```yaml
jobs:
  store-metrics:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    needs: build
    permissions:
      contents: write
    uses: ShipSoft/.github/.github/workflows/physics-metrics.yml@main
    with:
      mode: store
      reference-branch: main
  compare-metrics:
    if: github.event_name == 'pull_request'
    needs: build
    permissions:
      contents: read
      pull-requests: write   # omit to compare without PR comments
    uses: ShipSoft/.github/.github/workflows/physics-metrics.yml@main
    with:
      mode: compare
      reference-branch: main
      config: ci/metrics_config.yaml
```

Like `prek.yml`, the workflow requests no permissions itself: the caller
grants `contents: write` for store and `pull-requests: write` for the compare
comment (the comment is best-effort and skipped for fork PRs).

Inputs: `mode` (required, `store` or `compare`), `reference-branch`
(required), `config` (required for compare), `artifact-pattern` (default
`metrics-*`), `notes-ref-prefix` (default `ci/physics-metrics`),
`comment-on-pr` (default `true`).

## Renovate preset

The organisation's shared [Renovate](https://docs.renovatebot.com/) config
lives in [`default.json`](default.json) at the repository root, which is where
Renovate looks for a repository's default preset. Repositories opt in with a
root `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>ShipSoft/.github"]
}
```

The preset extends `config:recommended`, enables the pre-commit manager, runs
at weekends with at most five open PRs, compares pixi conda dependencies with
conda versioning instead of the manager's pep440 default, leaves the pinned
`python` interpreter alone (`pixi-lock-update.yml` handles in-series patches),
and tracks CMake `FetchContent` `GIT_TAG`s that point at GitHub.

A repository needing an exception adds its own `packageRules` next to the
`extends`: FairShip disables Eigen updates because acts-ship requires an exact
version. This repository carries `renovate.json` too, so Renovate keeps the
actions pinned in the reusable workflows above up to date for every caller.

## Contributor setup snippet

Repositories that lint via `prek.yml` should document the matching local
setup in their `CONTRIBUTING.md`. To keep the wording consistent, copy the
canonical "Pre-commit hooks" step below (adjust the surrounding numbering
and the dependency list to the repo):

````markdown
**Pre-commit Hooks**: We use [`prek`](https://github.com/j178/prek) (a
drop-in `pre-commit` replacement) to enforce coding standards. The hook
tools come from the pixi `lint` environment, so versions are tracked in
`pixi.lock` and run identically everywhere. Install the hooks once:

```bash
pixi run install-hooks
```

Run all hooks manually at any time with `pixi run lint`.
````

Do **not** tell contributors to run `pre-commit install`: that would use
whatever tool versions are on their `PATH` rather than the pinned `lint`
environment. The full rationale lives in the
[Linting & git hooks](https://shipsoft.github.io/Documentation/dev-guide/linting-and-hooks/)
dev-guide page.

## Repository settings

Reusable workflows cover what runs *in* a repository; [`repo-config/`](repo-config)
covers the repository settings themselves: merge methods and the branch
rulesets that give every repo a merge queue, a review requirement and a linear
history.

```bash
repo-config/apply-repo-config.sh              # dry run: print the diff
repo-config/apply-repo-config.sh --apply      # write it
repo-config/apply-repo-config.sh --repo aegir # one repo at a time
```

It needs `gh` (authenticated as someone with admin on the target repos) and
`jq`, and nothing else. Re-running it is safe, and a dry run doubles as the
drift check.

This is deliberately *not* wired into a scheduled workflow: `GITHUB_TOKEN`
cannot write another repository's rulesets, so automating it would mean keeping
a PAT or App token as an org secret.

### What it sets

Each repository gets two rulesets on its default branch, following the split
FairShip already used:

- `main-1`: no deletion, no force-push. No bypass for anyone.
- `main-2`: linear history, merge queue (rebase, all-green grouping), one
  approving review, resolved conversations, and squash/rebase as the only merge
  methods. Repository admins may bypass this one.

The split matters: an admin can land an urgent fix without a second pair of
eyes, while nobody at all can rewrite or delete the default branch.

Repository-level toggles disable merge commits outright. They also enable
auto-merge, so a pull request can be handed to the queue before its checks
finish, and "update branch", so a stale branch can be refreshed from the
web UI.

### Required checks

A merge queue only works if its required checks also run on the `merge_group`
event, and the ruleset can only be identical everywhere if the check names are.
So each repository provides two aggregator jobs that gate on everything else in
their workflow. `All checks passed` in the build workflow, `Lint passed` in
the lint workflow:

```yaml
  all-checks:
    name: All checks passed
    if: always()
    runs-on: ubuntu-latest
    needs: [build, test]     # every other job in this workflow
    steps:
      - name: Check status of all jobs
        run: |
          if [[ "${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') }}" == "true" ]]; then
            echo "One or more jobs failed or were cancelled"
            exit 1
          fi
```

A skipped job counts as a pass, which matters: `commit-check.yml` only runs on
`pull_request` events, so it is skipped inside a merge group. Commit messages
are checked on the pull request, not again in the queue.

Both contexts are pinned to the GitHub Actions app (`integration_id` 15368), so
a status posted under one of those names by anything else does not satisfy the
rule. FairShip's original ruleset left this unset; ship-conda-recipes already
pinned it.

[`repos.json`](repo-config/repos.json) records a `tier` per repository for the
repos that cannot provide both contexts: `single` for repositories that build,
test and lint in one job, `none` for repositories with no pull-request CI at
all. A `none`-tier repo still gets reviews and a linear history; its queue
simply has nothing to gate.

The script will not require a check unless it has reported on the default
branch and the workflow that produced it triggers on `merge_group`. Either
gap would leave every pull request waiting on a status that never arrives, so
when one is found the repository's rulesets and branch protection are left
untouched and the run exits nonzero. The merge-method toggles are settled
earlier and are written either way. The aggregator job has to land before the
ruleset does.

### CODEOWNERS

`require_code_owner_review` follows the `codeowners` flag in `repos.json`, which
mirrors whether the repository actually has a CODEOWNERS file. When one lands,
flip the flag and re-run.

## Versioning

Reusable workflows are referenced via `@main`. Pin to a tag (e.g.
`@v1.0.0`) for production stability once the API stabilises.
