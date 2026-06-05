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
      tasks: '["configure","build","test"]'
      lfs: true
      env-vars: |
        QT_QPA_PLATFORM=offscreen
```

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

## Versioning

Reusable workflows are referenced via `@main`. Pin to a tag (e.g.
`@v1.0.0`) for production stability once the API stabilises.
