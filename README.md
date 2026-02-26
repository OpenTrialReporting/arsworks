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

### 2. Open and bootstrap

Open `arsworks.Rproj` in RStudio. renv activates automatically via `.Rprofile`.
Then run the one-shot bootstrap script:

```r
source("bootstrap.R")
```

This script does four things in order:

| Step | What it does |
|------|--------------|
| 1 | Initialises git submodules (`git submodule update --init --recursive`) |
| 2 | Patches `renv.lock` so the local `ars` package is not fetched from CRAN¹ |
| 3 | Runs `renv::restore()` to install all pinned CRAN dependencies |
| 4 | Installs the five local sub-packages in dependency order |

> ¹ An unrelated package on CRAN is also named `ars`. Without the patch,
> `renv::restore()` tries to download it and fails on a version mismatch.
> The bootstrap fixes this automatically.

### 3. Start working

```r
source("sync_and_load.R")      # document + load all five packages
source("data_table_examples.R") # creates adsl, adae, adlb in your session
```

Run `source("sync_and_load.R")` at the start of every session, or after
pulling changes to any sub-package.

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

Start each session by sourcing the loader script — it documents and loads all
five packages in one step:

```r
source("sync_and_load.R")
```

Then load the example data:

```r
source("data_table_examples.R")  # creates adsl, adae, adlb in your session
```

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

The five packages must be installed in dependency order. The bootstrap script
handles this. If you are installing manually, use this order:

```r
devtools::install("arscore")
devtools::install("arsshells")
devtools::install("arsresult")
devtools::install("arstlf")
devtools::install("ars")
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
├── bootstrap.R           ← one-shot setup script (run once after cloning)
├── sync_and_load.R       ← session loader (run at the start of each session)
├── data_table_examples.R ← test data generator
├── MASTER_PLAN.md
└── MAKE_TEST_DATA.md
```

---

## Contributing

Development happens in the individual package repositories. Open issues and
pull requests there. Use `arsworks` to test that changes across packages work
together by updating submodule pointers and running the full suite.
