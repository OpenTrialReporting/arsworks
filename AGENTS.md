
# arsworks — Project Memory

## Overview

**arsworks** is a monorepo containing the ARS (Analysis Results Standard) R package suite
for CDISC-compliant clinical trial reporting.

| Package | Responsibility |
|---------|---------------|
| **arscore** | S7 data model, JSON I/O, validation, ARD extraction, `enrich_ard()` |
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

## §24 Self-Describing ARD + Explorer UX — COMPLETE (2026-03-03)

### ARD enrichment

**`arsresult/R/run.R`**: `group_value` is now populated on `ars_result_group`
objects at both construction sites (expand-path combo loop and PIN-path standard
filter). The condition value (e.g. "Placebo", "F") is extracted from
`g@condition@value[[1]]`. Total groups (no condition) remain `NA_character_`.

**`arscore/R/create_ard.R`**: New exported function `enrich_ard(ard, reporting_event)`
joins self-describing metadata onto an ARD tibble:

| Column added | Source |
|-------------|--------|
| `analysis_label` | `ars_analysis@name` |
| `method_id` | `ars_analysis@method_id` |
| `dataset` | `ars_analysis@dataset` |
| `variable` | `ars_analysis@variable` |
| `analysis_set_id` | `ars_analysis@analysis_set_id` |
| `data_subset_id` | `ars_analysis@data_subset_id` |
| `group_label` (and `_1`, `_2`) | `ars_group@label` via group_id lookup |

Column ordering: metadata after `analysis_id`; each `group_label` adjacent to
its `group_id`.

### Explorer UX improvements (`ars_explorer.R`)

- **Single "Get Table" button**: Consolidated "Get ARD" + "Get Table" into one
  primary action that runs the full pipeline (hydrate → run → enrich → render).
  Graceful degradation: if render fails, navigates to ARD tab with a warning.
- **Dynamic screening arm deselection**: Treatment arm checkboxes default to
  unchecked for arms with no subjects in analysis populations. Uses CDISC flags
  (ITTFL, SAFFL, RANDFL) in priority order; falls back to all-checked if no
  flags exist. Study-agnostic.
- **Enriched ARD tab**: `enrich_ard()` is called after `run()`, so the ARD
  reactable displays all metadata columns automatically.

### Transpile test fix

Fixed 4 pre-existing test failures in `arsresult/tests/testthat/test-transpile.R`
(OI-02 numeric coercion guard tests). Root cause: `expect_error(regexp = ...)`
matched against raw condition messages containing ANSI escape codes and cli
line-wrapping characters (`│`, `\n`). Fix: capture error manually, strip ANSI
via `cli::ansi_strip()`, collapse whitespace, then match.

---

## §25 `formatted_value` via `resultPattern` — COMPLETE (2026-03-03)

`enrich_ard()` now populates the `formatted_value` column by applying each
operation's `resultPattern` (declared in the method definition) to `raw_value`.
Previously `formatted_value` was left as `NA_character_`.

### New file: `arscore/R/format_result_pattern.R`

Exported functions:
- **`format_result_pattern(raw_value, result_pattern)`** — formats a single value.
- **`format_result_patterns(raw_values, patterns)`** — vectorised wrapper.

### Formatting rules (derived from CDISC CSD v1.0 reference JSON)

1. **Case-insensitive**: `"xx.x"` and `"XX.X"` are equivalent.
2. Contiguous runs of X characters (with optional `.`) define numeric fields.
   X-count after the decimal → decimal precision; no decimal → integer.
3. **Parenthesized patterns** (`(XX.XX)`, `( XX.X)`, `(N=XX)`) are **fixed-width**:
   output is right-justified with leading spaces to match the pattern's `nchar`.
4. **Non-parenthesized patterns** (`XX`, `XX.X`, `X.XXXX`) enforce decimal
   precision only — no width padding.
5. Literal characters (parentheses, `N=`, `%`, spaces) are preserved verbatim.
6. `NA` or non-numeric `raw_value` → `NA_character_`.
7. Existing non-NA `formatted_value` entries are never overwritten.

### Pattern examples

| `resultPattern` | `raw_value` | `formatted_value` |
|-----------------|-------------|-------------------|
| `XX` | `86` | `86` |
| `XX.X` | `75.2093` | `75.2` |
| `(XX.XX)` | `8.59` | `( 8.59)` |
| `( XX.X)` | `1.16` | `(  1.2)` |
| `(N=XX)` | `86` | `(N=86)` |
| `X.XXXX` | `0.0065` | `0.0065` |

### Integration in `enrich_ard()`

After joining analysis-level metadata (step 1), `enrich_ard()` builds a
`(method_id, operation_id) → result_pattern` lookup from the reporting event's
methods, joins it to the ARD, applies `format_result_patterns()` to rows where
`formatted_value` is `NA`, then drops the transient `result_pattern` column.

### Validation against CDISC CSD

Tested against all 3,734 `formattedValue` entries in the Common Safety Displays
v1.0 reference JSON. 3,183 exact matches; the 551 mismatches are CSD data
quality issues (raw values already containing decimals under integer patterns,
inconsistent padding in one analysis, 1 banker's rounding edge case).

### Tests

New test file: `arscore/tests/testthat/test-format_result_pattern.R` (41 assertions)
covering all CSD pattern types, edge cases, vectorised wrapper, `enrich_ard()`
integration, preservation of existing `formatted_value`, and cleanup of transient
columns.

---

## Test suite (2026-03-03, post §25)

| Package | Pass | Fail | Warn |
|---------|------|------|------|
| arscore | 1409 | 0 | 0 |
| arsshells | 548 | 0 | 0 |
| arsresult | 312 | 0 | 1 (expected) |
| arstlf | 120 | 0 | 0 |
| ars | 58 | 0 | 4 (expected) |
| **Total** | **2447** | **0** | **5** |
