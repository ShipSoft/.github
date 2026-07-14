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
    uses: ShipSoft/.github/.github/workflows/config-sync.yml@main
    with:
      base: main         # or master
```

Only files without intentional per-repo customisation belong in the default
list: `.clang-format` (include ordering) and `CPPLINT.cfg` (filters) are
repo-specific and are deliberately **not** synced. Callers that customise one
of the defaults pass a narrower `files` list.

Inputs: `base` (required), `files` (newline-separated, default `.clang-tidy`
and `cliff.toml`), `pr-branch`, `pr-label`.

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

## Versioning

Reusable workflows are referenced via `@main`. Pin to a tag (e.g.
`@v1.0.0`) for production stability once the API stabilises.
