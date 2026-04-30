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

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/OpenTrialReporting/arsworks.git
cd arsworks
```

> Submodules do **not** need to be cloned manually. The bootstrap script in
> Step 2 handles submodule initialisation automatically, even if you forgot
> `--recurse-submodules`.

### 2. Open and set up

Open `arsworks.Rproj` in RStudio. renv activates automatically via `.Rprofile`.
Then run the one-command setup script:

```r
source("setup.R")
```

This is the recommended entry point for both fresh clones and returning
sessions. It auto-detects whether a full bootstrap is needed, then syncs,
loads, builds the example tables, and runs UAT checks.

| Phase | What it does | When it runs |
|-------|--------------|--------------|
| Bootstrap | Submodule init, `renv::restore()`, install 6 local packages | Only when the environment is stale (see below) |
| Sync & load | `devtools::document()` + `load_all()` on all 6 sub-packages | Every time |
| Examples | Builds `adsl`/`adae`/`adlb` and renders all 6 shells | Every time (skippable) |
| UAT checks | §22 ARD + render-level checks across all shells | Every time (skippable) |

**Bootstrap auto-triggers when any of the following is true:**

- A submodule directory is empty (fresh clone without `--recurse-submodules`)
- One of the six local packages is not installed
- An installed local package's version differs from its `DESCRIPTION`
  (submodule pointer was bumped — reinstall needed)
- `renv::status()` reports missing CRAN packages (environment drift)

**Fine-grained control:**

```r
source("setup.R")
setup(force_bootstrap = TRUE)   # reinstall even if env looks OK
setup(skip_examples   = TRUE)   # bootstrap + sync only
setup(skip_uat        = TRUE)   # skip UAT checks
```

> The individual scripts (`bootstrap.R`, `sync_and_load.R`,
> `data_table_examples.R`, `uat_checks.R`) remain sourceable on their own
> for advanced use. `setup.R` just orchestrates them.

### 3. Subsequent sessions

Re-running `source("setup.R")` at the start of each session is safe — it
will skip the bootstrap phase when the environment is healthy and only
re-document, re-load, and re-run the examples/UAT.

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
    ↓
arsstudio  ← Shiny UI: interactive browser for the full pipeline
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
| `arsstudio` | [OpenTrialReporting/arsstudio](https://github.com/OpenTrialReporting/arsstudio) | Interactive Shiny studio |

---

## Usage

Start each session with:

```r
source("setup.R")
```

This loads all six packages and creates `adsl`, `adae`, `adlb` in your
session (plus `ard_dm01`, …, `ard_lb02` and `gt_dm01`, …, `gt_lb02` from
the examples + UAT checks). Skip the UAT step with `setup(skip_uat = TRUE)`
if you just want the data and rendered tables.

There are two equivalent patterns for generating a table.

**Pattern A — pipe workflow** (recommended for interactive use):

```r
use_shell("T-AE-02") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     TRTEMFL = "TRTEMFL",
                     AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
    group_map = list(
      GRP_TRT = list(
        list(id = "GRP_TRT_A", value = "Treatment A", order = 1L),
        list(id = "GRP_TRT_B", value = "Treatment B", order = 2L)
      )
    )
  ) |>
  run(adam = list(ADAE = adae, ADSL = adsl)) |>
  render(backend = "tfrmt")
```

**Pattern B — `ars_pipeline()`** (simpler for scripts):

```r
ars_pipeline(
  shell        = "T-AE-02",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL",
                   AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
  group_map    = list(
    GRP_TRT = list(
      list(id = "GRP_TRT_A", value = "Treatment A", order = 1L),
      list(id = "GRP_TRT_B", value = "Treatment B", order = 2L)
    )
  ),
  backend      = "tfrmt"
)
```

### Available shells

| Shell ID | Table | Key datasets | Key variables |
|---|---|---|---|
| `T-DM-01` | Demographic characteristics | ADSL | `TRT01A`, `SAFFL`, `AGE`, `SEX`, `RACE` |
| `T-DS-01` | Subject disposition | ADSL | `TRT01A`, `RANDFL`, `SAFFL`, `COMPLFL`, `DCSREAS` |
| `T-AE-01` | Overview of adverse events | ADAE, ADSL | `TRT01A`, `SAFFL`, `TRTEMFL`, `AEREL`, `AESER`, `AETOXGR`, `AEACN`, `AEOUT` |
| `T-AE-02` | TEAEs by SOC and PT | ADAE, ADSL | `TRT01A`, `SAFFL`, `TRTEMFL`, `AEBODSYS`, `AEDECOD` |
| `T-LB-01` | Summary of laboratory parameters | ADLB, ADSL | `TRT01A`, `SAFFL`, `PARAMCD`, `ANL01FL`, `ABLFL`, `AVAL`, `CHG` |
| `T-LB-02` | Shift table (baseline vs. worst post-baseline) | ADLB, ADSL | `TRT01A`, `SAFFL`, `PARAMCD`, `ANL01FL`, `BNRIND`, `WGRNRIND` |

> **Note:** All 6 installed shells use Mode 2 (pre-specified) treatment arm
> groupings. You must always supply a `group_map` to `hydrate()` mapping your
> study's treatment arm values (e.g. `"Placebo"`, `"Xanomeline Low Dose"`) to
> group IDs. Without it, all arms will return identical results (the full
> dataset, unfiltered).

Browse all available shells programmatically:

```r
browse_shells()
```

---

## Troubleshooting

### Submodule directories are empty after cloning

Run the bootstrap script — it calls `git submodule update --init --recursive`
automatically. If bootstrap itself fails at the submodule step, run the git
command directly and check for network or proxy errors:

```bash
git submodule update --init --recursive
```

If you are behind a corporate proxy, configure git first:

```bash
git config --global http.proxy http://proxy.example.com:8080
```

### `renv::restore()` fails with "failed to retrieve package 'ars@0.1.0'"

This means `renv.lock` still has `ars` listed as `"Source": "Repository"`.
Re-run the bootstrap script — it patches this automatically. Or fix it manually
by opening `renv.lock`, finding the `"ars"` block, and changing
`"Source": "Repository"` to `"Source": "unknown"`.

### A sub-package fails to install with "dependencies not available"

The six packages must be installed in dependency order. The bootstrap script
handles this. If you are installing manually, use this order:

```r
devtools::install("arscore")
devtools::install("arsshells")
devtools::install("arsresult")
devtools::install("arstlf")
devtools::install("ars")
devtools::install("arsstudio")
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
├── arscore/                  ← submodule → OpenTrialReporting/arscore   (data model)
├── arsshells/                ← submodule → OpenTrialReporting/arsshells (templates + hydration)
├── arsresult/                ← submodule → OpenTrialReporting/arsresult (execution engine)
├── arstlf/                   ← submodule → OpenTrialReporting/arstlf    (rendering)
├── ars/                      ← submodule → OpenTrialReporting/ars       (workflow API)
├── arsstudio/                ← submodule → OpenTrialReporting/arsstudio (Shiny UI)
├── model/
│   └── ars_ldm.json          ← CDISC ARS v1.0 JSON schema (used by arscore audit)
├── Common Safety Displays.json ← CSD reference data (used by template work)
├── .gitmodules               ← submodule URL registry
├── renv.lock                 ← pinned R package environment
├── renv/                     ← renv activation scripts
├── arsworks.Rproj            ← RStudio project file
├── Dockerfile                ← reproducible build image
├── setup.R                   ← smart entry point: auto-bootstrap + sync + examples + UAT
├── bootstrap.R               ← one-shot setup (called by setup.R when needed)
├── sync_and_load.R           ← session loader (called by setup.R)
├── data_table_examples.R     ← test data + all 6 tables (called by setup.R)
├── uat_checks.R              ← §22 UAT checks (called by setup.R)
├── README.md                 ← this file
├── AGENTS.md                 ← context guide for AI / human contributors
├── CONTRIBUTING.md           ← where PRs go (submodule repos vs. arsworks)
├── ISSUES_AND_GAPS.md        ← live tracker of known issues + workarounds
├── MASTER_PLAN.md            ← cross-package design + sprint log
└── LICENSE                   ← MIT
```

---

## Contributing

Development happens in the individual package repositories. Open issues and
pull requests there. Use `arsworks` to test that changes across packages work
together by updating submodule pointers and running the full suite.
