# arsworks

**arsworks** is a monorepo coordinator for the arsworks suite — a collection of
R packages implementing the
[CDISC Analysis Results Standard (ARS) v1.0](https://cdisc-org.github.io/analysis-results-standard/)
for reproducible, metadata-driven clinical table generation.

This repository does not contain package source code itself. It holds:

- Git submodule references pinning each package to a specific commit
- An `renv.lock` capturing the full R package environment
- Design documents and cross-package planning files

**Reproduce the full environment on a new machine:**

```bash
git clone --recurse-submodules https://github.com/OpenTrialReporting/arsworks.git
cd arsworks
Rscript -e "renv::restore()"
```

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

## Usage

The examples below use the synthetic ADaM datasets in `data_table_examples.R`
(60 subjects, 3 arms). Run that script first to create `adsl`, `adae`, and
`adlb` in your session, then load `ars`.

```r
source("data_table_examples.R")
library(ars)
```

There are two equivalent patterns for generating a table.

**Pattern A — pipe workflow** (recommended when you need the shell object for
further inspection or custom rendering):

```r
shell <- use_shell("T-AE-02") |>
  hydrate(variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                            TRTEMFL = "TRTEMFL",
                            AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"))

ard <- run(shell, adam = list(ADAE = adae, ADSL = adsl))
render(ard, shell, backend = "tfrmt")
```

**Pattern B — `ars_pipeline()`** (simpler for scripts):

```r
ars_pipeline(
  shell        = "T-AE-02",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL",
                   AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
  backend      = "tfrmt"
)
```

> **Note:** `run()` returns only the ARD; the shell object is not carried
> through the pipe. Always assign the hydrated shell to a variable before
> calling `run()`, then pass it explicitly to `render()`. `ars_pipeline()`
> handles this internally.

### Available shells

| Shell ID | Table | Key datasets | Key variables |
|---|---|---|---|
| `T-DM-01` | Demographic characteristics | ADSL | `TRT01A`, `SAFFL`, `AGE`, `SEX`, `RACE` |
| `T-DS-01` | Subject disposition | ADSL | `TRT01A`, `RANDFL`, `SAFFL`, `COMPLFL`, `DCSREAS` |
| `T-AE-01` | Overview of adverse events | ADAE, ADSL | `TRT01A`, `SAFFL`, `TRTEMFL`, `AEREL`, `AESER`, `AETOXGR`, `AEACN`, `AEOUT` |
| `T-AE-02` | TEAEs by SOC and PT | ADAE, ADSL | `TRT01A`, `SAFFL`, `TRTEMFL`, `AEBODSYS`, `AEDECOD` |
| `T-LB-01` | Summary of laboratory parameters | ADLB, ADSL | `TRT01A`, `SAFFL`, `PARAMCD`, `ANL01FL`, `ABLFL`, `AVAL`, `CHG` |
| `T-LB-02` | Shift table (baseline vs. worst post-baseline) | ADLB, ADSL | `TRT01A`, `SAFFL`, `PARAMCD`, `ANL01FL`, `BNRIND`, `WGRNRIND` |

Browse all available shells programmatically:

```r
browse_shells()
```

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

## Keeping submodules in sync

When changes are pushed to an individual package repo, `arsworks` does not
update automatically — it still points to the old commit. Syncing is a
deliberate two-step: pull the new commits into the submodule, then record the
updated pointer in `arsworks`.

```bash
cd arsworks

# Update one specific package
git submodule update --remote arsresult

# Or update all packages at once
git submodule update --remote

# Commit the new pointers
git add arsresult        # or git add -A to catch all updated submodules
git commit -m "Bump arsresult to latest"
git push
```

To check whether any submodules are ahead of what `arsworks` has pinned:

```bash
git submodule status
```

A `+` prefix on a line means that submodule has commits not yet recorded in
`arsworks`. The deliberate manual bump is intentional — it ensures `arsworks`
always reflects a set of package versions known to work together.

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
