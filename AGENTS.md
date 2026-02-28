# arsworks — Project Memory

## Overview

**arsworks** is a monorepo containing the ARS (Analysis Results Standard) R package suite
for CDISC-compliant clinical trial reporting.

| Package | Responsibility |
|---------|---------------|
| **arscore** | S7 data model, JSON I/O, validation, ARD extraction |
| **arsshells** | Shell templates, hydration (variable/group/value mapping, Mode 3 expansion) |
| **arsresult** | Method registry, `run()` execution pipeline, built-in statistical methods (`stdlib.R`) |
| **arstlf** | Table/figure rendering via tfrmt backend |
| **ars** | Convenience wrappers (`ars_pipeline()`, re-exports) |

Authoritative planning document: `MASTER_PLAN.md`

## Data

- **adsl**: `pharmaverseadam::adsl` (306 subjects, 58 columns)
- **adae**: `pharmaverseadam::adae` (adverse events)
- **adlb**: `pharmaverseadam::adlb` (lab results, 47 PARAMCDs)
- **adlb_lb01**: Subset of adlb filtered to 7 PARAMCDs: HGB, PLT, WBC, ALT, AST, CREAT, GLUC
- **adlb_lb02**: Subset of adlb filtered to 3 PARAMCDs: HGB, ALT, CREAT

Study: CDISCPILOT01 — 3 treatment arms (Placebo, Xanomeline Low Dose, Xanomeline High Dose).

### Group map (shared across all shells)

```r
grp_map <- list(
  GRP_TRT = list(
    list(id = "GRP_TRT_A", value = "Placebo",              label = "Placebo (N=xx)",              order = 1L),
    list(id = "GRP_TRT_B", value = "Xanomeline Low Dose",  label = "Xanomeline Low Dose (N=xx)",  order = 2L),
    list(id = "GRP_TRT_C", value = "Xanomeline High Dose", label = "Xanomeline High Dose (N=xx)", order = 3L)
  )
)
```

## Shell Templates

| Template | Title | Dataset | Analyses |
|----------|-------|---------|----------|
| T-DM-01 | Summary of Demographic Characteristics | ADSL | 28 |
| T-DS-01 | Subject Disposition | ADSL | 36 |
| T-AE-01 | Overview of Adverse Events | ADAE | 28 |
| T-AE-02 | TEAEs by SOC and Preferred Term | ADAE | 2 (expand path, 23 SOCs × 242 PTs) |
| T-LB-01 | Laboratory Parameters (Descriptive Stats) | ADLB | 168 (7 params × 2 timepoints × 4 stats × 3 arms) |
| T-LB-02 | Shift Table (Baseline vs Post-Baseline) | ADLB | 108 |

## Key Files

| File | Purpose |
|------|---------|
| `data_table_examples.R` | End-to-end pipeline examples for all 6 shells |
| `ars_explorer.R` | Interactive Shiny explorer app |
| `sync_and_load.R` | Loads all ars* packages via `devtools::load_all()` |
| `bootstrap.R` | Bootstraps renv from lockfile |

## Recent Changes (2026-02-28)

### Fix: Empty-data guards in `arsresult/R/stdlib.R`

`.fn_min()`, `.fn_max()`, and `.fn_median()` previously called `min()`/`max()`/`median()`
with `na.rm = TRUE` on vectors that could be empty or all-NA after data filtering. This
produced repeated warnings (`"no non-missing arguments to min; returning Inf"`) and
`Inf`/`-Inf` values in the ARD.

**Fix:** Each function now checks `length(non_na) > 0` before calling the base function,
returning `NA_real_` for empty inputs.

```r
# Example (same pattern for .fn_max and .fn_median)
.fn_min <- function(data, analysis) {
  vals <- data[[analysis@variable]]
  non_na <- vals[!is.na(vals)]
  c(OP_MIN = if (length(non_na) > 0) min(non_na) else NA_real_)
}
```

### Fix: Pre-run zero-row skip in `arsresult/R/run.R`

`.compute_analysis()` now skips analyses early when filtered data has zero rows, avoiding
unnecessary method calls on empty data. Two guards were added in the **expand path** only
(the pin path is left unguarded so that `METH_FREQ` correctly returns 0 for empty subsets):

1. **Base-data skip (expand path):** After applying the data subset filter to `base_data`,
   if `nrow(base_data) == 0`, the analysis is skipped entirely with a `cli_alert_warning`.

2. **Per-combo skip (expand path):** After applying group filters within the Cartesian
   product loop, if `nrow(combo_data) == 0`, that combination is skipped via `next`.

**Root cause:** The T-LB-01 shell template defines analyses for 47 lab parameters, but
the ADLB data only contains 7. The 40 missing parameters produce empty filtered datasets.
After hydration with `adam`, Mode 3 expansion limits to only the parameters present in
the data (7), so the issue only manifests when running against a shell hydrated without
data-driven expansion (e.g. the original 47-parameter shell).

**Impact:** For the original 47-parameter T-LB-01 shell, 1,280 of 1,504 analyses are now
skipped cleanly (zero warnings, zero Inf/-Inf values). All 4 package test suites pass
(the pin-path guard was intentionally omitted to preserve the `SEX == "X" → count 0` test
in `arsresult/tests/testthat/test-run.R`).

### Validation (2026-02-28)

All 6 shells tested end-to-end (hydrate → run → render):

| Shell | ARD Rows | Table Rows | min/max Warnings |
|-------|----------|------------|------------------|
| T-DM-01 | 72 | 16 | 0 |
| T-DS-01 | 72 | 13 | 0 |
| T-AE-01 | 56 | 9 | 0 |
| T-AE-02 | 88 | 299 | 0 |
| T-LB-01 | 1008 | 84 | 0 |
| T-LB-02 | 216 | 45 | 0 |

Test suites: arscore ✓, arsshells ✓, arsresult ✓ (1 expected warning), arstlf ✓
