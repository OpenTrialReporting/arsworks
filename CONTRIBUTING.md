# Contributing to arsworks

`arsworks` is a monorepo coordinator: the five R packages (`ars`, `arscore`,
`arsshells`, `arsresult`, `arstlf`) live in their own git repositories under
<https://github.com/OpenTrialReporting> and are included here as git
submodules.

This changes how contributions flow compared to a single-repo project.

## Where to open a PR

**Code changes go to the submodule repo, not arsworks.**

| Change touches... | Open PR against... |
|---|---|
| R code in `ars/` | `OpenTrialReporting/ars` |
| R code in `arscore/` | `OpenTrialReporting/arscore` |
| R code in `arsshells/` | `OpenTrialReporting/arsshells` |
| R code in `arsresult/` | `OpenTrialReporting/arsresult` |
| R code in `arstlf/` | `OpenTrialReporting/arstlf` |
| `ars_explorer.R`, `bootstrap.R`, `sync_and_load.R`, `renv.lock`, `README.md`, `AGENTS.md`, `MASTER_PLAN.md`, `ISSUES_AND_GAPS.md` | `OpenTrialReporting/arsworks` |

Once a submodule PR merges, open a follow-up PR against `arsworks` that bumps
the submodule pointer to the new upstream commit (`git add <submodule>` after
running `git submodule update --remote`).

## Dev setup

1. Clone with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/OpenTrialReporting/arsworks.git
   ```
2. Open `arsworks.Rproj` in RStudio / Positron.
3. Run `source("bootstrap.R")` to install dependencies and local packages in
   the correct order (`arscore` → `arsshells` / `arsresult` → `arstlf` → `ars`).
4. Run `source("sync_and_load.R")` to pull submodule updates and reload.

## Coding standards

- See [AGENTS.md](./AGENTS.md) for naming conventions, CDISC-compliance
  requirements, and the pharmaverse stack reference.
- Tests use `testthat`; run with `devtools::test()` inside the relevant
  submodule directory.
- Roxygen docs: every exported function must have `@title`, `@description`,
  `@param`, `@return`, and `@examples` (use `\dontrun{}` when the example
  requires loaded data). Run `devtools::document()` before committing.

## Version and changelog conventions

- Follow [semver](https://semver.org/). Between releases, the `Version:` field
  in `DESCRIPTION` uses the `x.y.z.9000` dev suffix.
- Add a bullet to `NEWS.md` under `# <pkg> (development version)` for every
  user-visible change.
- On release, rename the dev header to `# <pkg> x.y.z (YYYY-MM-DD)` and open
  a new `(development version)` section above it.

## Reporting issues

- Bugs and feature requests: file against the relevant **submodule** repo.
- Issues that span multiple submodules or concern the bootstrap / sync
  workflow: file against `OpenTrialReporting/arsworks`.

## License

Contributions are licensed under MIT. See [LICENSE](./LICENSE).
