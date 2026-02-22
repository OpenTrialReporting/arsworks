# arsworks

**arsworks** is a monorepo coordinator for the arsworks suite — a collection of
R packages implementing the
[CDISC Analysis Results Standard (ARS) v1.0](https://cdisc-org.github.io/analysis-results-standard/)
for reproducible, metadata-driven clinical table generation.

This repository does not contain package source code itself. It holds:

- Git submodule references pinning each package to a specific commit
- An `renv.lock` capturing the full R package environment
- Design documents and cross-package planning files

---

## Package architecture

```
arscore    ← S7 data model (41 classes), JSON I/O, validation, ARD extraction
    ↓
arsshells  ← Template library (shells) + hydration DSL
arsresult  ← Execution engine: WhereClause transpiler + method registry
    ↓
arstlf     ← Translator: ARS metadata + ARD → publication TLFs
    ↓
ars        ← Orchestrator: pipe-friendly workflow API
```

Each package lives in its own GitHub repository under the
[OpenTrialReporting](https://github.com/OpenTrialReporting) organisation and
can be used independently. `arsworks` pins the versions that are known to work
together.

| Package | Repository | Role |
|---|---|---|
| `arscore` | [OpenTrialReporting/arscore](https://github.com/OpenTrialReporting/arscore) | Data model & validation |
| `arsshells` | [OpenTrialReporting/arsshells](https://github.com/OpenTrialReporting/arsshells) | Shell templates |
| `arsresult` | [OpenTrialReporting/arsresult](https://github.com/OpenTrialReporting/arsresult) | Execution engine |
| `arstlf` | [OpenTrialReporting/arstlf](https://github.com/OpenTrialReporting/arstlf) | Rendering backends |
| `ars` | [OpenTrialReporting/ars](https://github.com/OpenTrialReporting/ars) | Workflow API |

---

## Getting started (new contributors)

### 1. Clone the repo with all submodules

```bash
git clone --recurse-submodules https://github.com/OpenTrialReporting/arsworks.git
cd arsworks
```

If you already cloned without `--recurse-submodules`, initialise them now:

```bash
git submodule update --init --recursive
```

### 2. Restore the R package environment

Open the project in RStudio by double-clicking `arsworks.Rproj`. renv will
activate automatically via `.Rprofile`. Then restore the pinned packages:

```r
renv::restore()
```

This installs every dependency at the exact versions recorded in `renv.lock`.

### 3. Install the arsworks packages from local source

Install the packages in dependency order:

```r
devtools::install("arscore")
devtools::install("arsshells")
devtools::install("arsresult")
devtools::install("arstlf")
devtools::install("ars")
```

### 4. Verify

```r
library(ars)

use_shell("T-AE-02") |>
  hydrate(variable_map) |>
  run(adam) |>
  render(backend = "tfrmt")
```

---

## Keeping submodules up to date

Each package evolves in its own repo. To pull the latest commit from one or
all submodules into `arsworks`:

```bash
# Update a single package
git submodule update --remote arscore

# Update all packages
git submodule update --remote

# Commit the updated pointers
git add arscore   # or git add -A
git commit -m "Bump arscore to latest"
```

---

## Repository structure

```
arsworks/
├── ars/                  ← submodule → OpenTrialReporting/ars
├── arscore/              ← submodule → OpenTrialReporting/arscore
├── arsshells/            ← submodule → OpenTrialReporting/arsshells
├── arsresult/            ← submodule → OpenTrialReporting/arsresult
├── arstlf/               ← submodule → OpenTrialReporting/arstlf
├── .gitmodules           ← submodule URL registry
├── renv.lock             ← pinned R package environment
├── renv/                 ← renv activation scripts
├── arsworks.Rproj        ← RStudio project file
├── PLAN_DATA_DRIVEN_GROUPS.md
├── MAKE_TEST_DATA.md
└── data_table_examples.R
```

---

## Contributing

Development happens in the individual package repositories. Open issues and
pull requests there. Use `arsworks` to test that changes across packages work
together by updating submodule pointers and running the full suite.
