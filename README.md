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

Inputs: `tasks` (JSON array, default `'["test"]'`), `lfs`, `runs-on`,
`cache`, `env-vars`.

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

```yaml
name: Lint
on:
  pull_request:
  push:
    branches: [main]   # or master
jobs:
  prek:
    uses: ShipSoft/.github/.github/workflows/prek.yml@main
```

The caller repo must define a pixi environment (default name `lint`) that
provides `prek` and the hook tools. Inputs: `environment` (default `lint`),
`runs-on`, `cache`, `extra-args`.

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

## Versioning

Reusable workflows are referenced via `@main`. Pin to a tag (e.g.
`@v1.0.0`) for production stability once the API stabilises.
