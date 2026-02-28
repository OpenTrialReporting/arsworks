
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

All six templates use the CSD `resultsByGroup: true` expand-path pattern.
Analysis counts are pre-hydration (template level).

| Template | Title | Dataset | Analyses | Pattern |
|----------|-------|---------|----------|---------|
| T-DM-01 | Summary of Demographic Characteristics | ADSL | 3 | CSD compact |
| T-DS-01 | Subject Disposition | ADSL | 9 | CSD compact |
| T-AE-01 | Overview of Adverse Events | ADAE | 7 | CSD compact |
| T-AE-02 | TEAEs by SOC and Preferred Term | ADAE | 2 | CSD (GRP_TRT × GRP_SOC/PT) |
| T-LB-01 | Laboratory Parameters (Descriptive Stats) | ADLB | 24 → expands per PARAMCD | Prototype section |
| T-LB-02 | Shift Table (Baseline vs Post-Baseline) | ADLB | 27 → expands per PARAMCD | Prototype section |

### CSD compact pattern (T-DM-01, T-AE-01, T-DS-01)

One analysis per row variable; GRP_TRT has `resultsByGroup: true`; all arm columns
come from the ARD result-group columns at render time. Cell `colLabel` is always `""`.

- **T-DM-01**: `AN_AGE` (METH_CONT, GRP_TRT only), `AN_SEX` (METH_CAT, GRP_TRT × GRP_SEX),
  `AN_RACE` (METH_CAT, GRP_TRT × GRP_RACE). GRP_SEX is Mode 1 (fixed M/F in template);
  GRP_RACE is Mode 3 (data-driven from ADSL).
- **T-AE-01**: 7 analyses (`AN_ANY_TEAE` … `AN_TEAE_DEATH`), each GRP_TRT only.
  Row label comes from `cell_row_label` in `prep_ard.R`.
- **T-DS-01**: 9 analyses (`AN_RAND` + 8 subset analyses). `AN_RAND` has no `dataSubsetId`.
  SEC_DISC_REASON cells have `indent: 1`.

All analyses in all three templates carry `"reason": "SPECIFIED IN SAP"` and
`"purpose": "PRIMARY OUTCOME MEASURE"` (required by `ars_analysis` S7 validator).

## Key Files

| File | Purpose |
|------|---------|
| `data_table_examples.R` | End-to-end pipeline examples for all 6 shells |
| `ars_explorer.R` | Interactive Shiny explorer app |
| `sync_and_load.R` | Loads all ars* packages via `devtools::load_all()` |
| `bootstrap.R` | Bootstraps renv from lockfile |

## OI-07 `resultsByGroup: false` comparison analyses — COMPLETE (2026-02-28)

`run()` now supports the comparison-analysis pattern: `resultsByGroup=false` with
no `groupId` on an ordered grouping factor. Data is passed unfiltered (full
analysis-set); the method receives `attr(data, "comparison_vars")` with the
grouping variable name. Each result carries a groupingId-only `ars_result_group`
(`group_id = NA`).

**New stdlib methods:** `METH_CHISQ` (OP_CHISQ_STAT, OP_CHISQ_PVAL, OP_CHISQ_DF),
`METH_ANOVA` (OP_ANOVA_F, OP_ANOVA_PVAL), `METH_FISHER` (OP_FISHER_PVAL).

**`ars_result_group` validation relaxed** — both `group_id` and `group_value` may
be NA simultaneously (matches CDISC ARS v1.0 spec).

**arstlf**: comparison ARD rows (`group_id = NA`) are already gracefully skipped
by `.extract_result_groups()` — no code change needed. Rendering a dedicated
p-value column is deferred to the `gt` backend / T-EF-01 sprint.

**Test totals:** arscore 1346, arsshells 534, arsresult 299, arstlf 115, ars 54
(**total 2348**, 0 failures, 17 expected warnings).

---

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

## PIN-path pre-filter cache — COMPLETE (2026-02-28)

`arsresult/R/run.R` PIN path now caches the analysis-set + pin-group filtered
dataset and the pre-computed `analysis_set_n` on first use, keyed by
`"<ds_name>\x1F<as_id>\x1F<pin_group_ids>"`.

### Benchmarks (83,652-row ADLB × 47 PARAMCDs = 1,504 analyses)

| Version | Time |
|---------|------|
| Before cache | ~112 s |
| After cache  | ~6.5 s |

For the 7-param installed shell (224 analyses, same 83k ADLB): ~6.5 s before,
~1.5 s after.

### Missing statistics in the ARD

When a data-subset filter yields 0 rows, the stdlib functions return explicit `NA_real_`:

```r
# stdlib.R  (.fn_max, .fn_min, .fn_median, .fn_sd)
non_na <- vals[!is.na(vals)]
c(OP_MAX = if (length(non_na) > 0) max(non_na) else NA_real_)
```

`OP_COUNT` returns `0` (not NA); all other continuous statistics return NA.
`prep_ard.R` converts `"NA"` string via `suppressWarnings(as.numeric("NA")) = NA_real_`,
and `tfrmt::frmt("xx.x")` renders `NA_real_` as an empty string (default `missing = ""`).

---

## §23 CSD Compact Pattern Migration — COMPLETE (2026-02-28)

Migrated T-DM-01, T-AE-01, and T-DS-01 from PIN-path (one analysis per arm per row)
to the CSD expand-path pattern (one analysis per row, all arms via `resultsByGroup: true`).

### Analysis count reduction

| Template | Before | After |
|----------|--------|-------|
| T-DM-01 | 18 analyses, 21 cells | 3 analyses, 6 cells |
| T-AE-01 | 21 analyses, 21 cells | 7 analyses, 7 cells |
| T-DS-01 | 27 analyses, 27 cells | 9 analyses, 9 cells |

### prep_ard.R: cell_row_label fix

`.expand_geom_to_tfrmt()` uses the shell cell's explicit `row_label` when no
row-dimension GF provides a label (e.g. analyses with only GRP_TRT as column GF).
This is essential for T-AE-01 / T-DS-01 row labels and T-DM-01 Age stat rows.

### Bug fixed during migration

The new analyses were missing `reason` and `purpose` fields required by the
`ars_analysis` S7 validator. Added `"reason": "SPECIFIED IN SAP"` and
`"purpose": "PRIMARY OUTCOME MEASURE"` to all 19 analyses across the three templates.

### Tests updated

- `arsshells/tests/testthat/test-use_shell.R`: 3 assertions (12→3 analyses; 12→4 cells;
  sex cell indent 1→0)
- All other test files were already correct for the new structure.

---

## End-to-end validation (2026-02-28, source packages)

All 6 shells clean (hydrate → run → render) using source packages loaded via
`sync_and_load.R`.

| Shell | ARD Rows | Table Rows | Warnings | Notes |
|-------|----------|------------|----------|-------|
| T-DM-01 | 72 | 16 | 0 | CSD compact, 3 analyses |
| T-DS-01 | 72 | 13 | 0 | CSD compact, 9 analyses |
| T-AE-01 | 56 | 9 | 0 | CSD compact, 7 analyses |
| T-AE-02 | 1334 | 276 | 0 | CSD expand, 2 analyses, 230 PTs |
| T-LB-01 | 1344 | 84 | 0 | NA min/max fix verified — 0 -Inf values in ARD |
| T-LB-02 | 216 | 45 | 0 | |

## Test suite (2026-02-28, post §23 migration)

| Package | Pass | Fail | Warn |
|---------|------|------|------|
| arscore | 1343 | 0 | 0 |
| arsshells | 534 | 0 | 0 |
| arsresult | 272 | 0 | 1 (expected) |
| arstlf | 115 | 0 | 0 |
| ars | 54 | 0 | 16 (expected) |
| **Total** | **2318** | **0** | **17** |
