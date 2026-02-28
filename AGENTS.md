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

## §21 Composite Ops Refactor — COMPLETE (verified 2026-02-28)

All components of the flat operations refactor (§21) are in place and verified:

- **`arsresult/R/stdlib.R`**: Flat scalars only — `OP_MEAN`, `OP_SD`, `OP_MIN`, `OP_MAX`.
  No `OP_MEAN_SD` or `OP_RANGE`.
- **Template JSONs** (`T-DM-01`, `T-LB-01`): Method ops declared flat; cell `operationId`s
  use `OP_MEAN` (Mean+SD anchor) and `OP_MIN` (Min+Max anchor).
- **`arstlf/R/prep_ard.R`**: `.combined_ops` maps `OP_MEAN→[OP_MEAN,OP_SD]`,
  `OP_MIN→[OP_MIN,OP_MAX]`.
- **`arstlf/R/render_tfrmt.R`**: `frmt_combine()` keyed on `OP_MIN` and `OP_MEAN`.
- **`ars_explorer.R`**: `.embed_ard_into_re()` pre-filter removed; no longer needed.

---

## Observed-combos fast path — COMPLETE (2026-02-28)

`arsresult/R/run.R` expand path now uses `.observed_combos()` before falling back to
`.cartesian_product()`. Significant speedup for large AE and lab tables.

### Decision logic

`.observed_combos()` returns a combo list (fast path) when all of these hold:
- Every expand factor has `grouping_variable` present in `base_data`
- All non-Total groups use simple EQ conditions
- Every declared EQ group value is present in `base_data` (no orphans)

Returns `NULL` → Cartesian fallback when any condition fails.

### T-AE-02 production requirement

**Pre-filter ADAE to TEAE rows before `hydrate()` / `run()`.** The full `adae` includes
non-TEAE rows; Mode 3 expansion derives PT groups from those rows too, creating ~12 orphan
PTs that are absent from `base_data` after the TRTEMFL filter. Those orphans trigger the
Cartesian fallback (~96 s, 21,160 combos). Pre-filtering ensures all derived PT groups are
actually observed, activating the fast path (~4 s, ~230 combos).

```r
adae_teae <- adae[!is.na(adae$TRTEMFL) & adae$TRTEMFL == "Y", ]
hydrate(..., adam = list(ADAE = adae_teae, ADSL = adsl))
run(adam = list(ADAE = adae_teae, ADSL = adsl))
```

### ARD column-naming quirk for orphaned-group rows

When the Cartesian path processes an orphaned combo (e.g. TRT=A × SOC=Nervous with no
Nervous TEAEs), the fi-loop fires `next` before appending the SOC group to
`combo_result_groups`. The result has only 1 result_group (the TRT group).

`arscore::create_ard()` (`create_ard.R:64`) uses **no suffix** when
`length(result_groups) == 1`, so the TRT group lands in the **unnumbered** `group_id` /
`grouping_id` columns, not `group_id_1`. Zero-count rows therefore have:

```
group_id_1  = NA        # no _1 result_group
group_id    = "GRP_A"   # TRT group in unnumbered column
group_id_2  = NA        # SOC never appended
raw_value   = "0"
```

---

## End-to-end validation (2026-02-28)

All 6 shells clean (hydrate → run → render). Full sprint notes in `MASTER_PLAN.md`.

| Shell | ARD Rows | Table Rows | Warnings |
|-------|----------|------------|----------|
| T-DM-01 | 72 | 16 | 0 |
| T-DS-01 | 72 | 13 | 0 |
| T-AE-01 | 56 | 9 | 0 |
| T-AE-02 | 88 | 299 | 0 |
| T-LB-01 | 1008 | 84 | 0 |
| T-LB-02 | 216 | 45 | 0 |

Test suites: arscore ✓ (1335), arsshells ✓ (552), arsresult ✓ (266, 1 expected warning),
arstlf ✓ (112), ars ✓ (95). **Total: 2360 expectations, 0 failures.**
