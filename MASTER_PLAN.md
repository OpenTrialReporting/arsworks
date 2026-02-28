# arsworks MASTER PLAN
**Date:** 2026-02-22 (updated 2026-02-28, Phase C **COMPLETE** — test hardening + performance fixes 2026-02-28; §22 UAT added + **COMPLETE** 2026-02-28; §23 CSD compact pattern migration **COMPLETE** 2026-02-28; OI-06 `referencedOperationRelationships` **COMPLETE** 2026-02-28)  
**Author:** Lovemore Gakava  
**Status:** ACTIVE  
**Scope:** arscore, arsshells, arsresult, arstlf, ars (tests + docs in each)  
**Version:** 3 (consolidated from PLAN_DATA_DRIVEN_GROUPS.md, ARS_DEVELOPMENT_PLAN.md, ARSSHELLS_PLAN.md, NEXT_STEPS.md)  
**File:** `MASTER_PLAN.md` — the single authoritative orchestration document for the arsworks suite

> All per-package planning files (`ARS_DEVELOPMENT_PLAN.md`, `ARSSHELLS_PLAN.md`,
> `NEXT_STEPS.md`, `format_improvement_plan.md`) have been merged here and replaced
> with redirect notices. Do not maintain separate planning files in sub-packages.

---

## SPRINT COMPLETE — 2026-02-28 (Session 5)

### ✅ OI-07 — `resultsByGroup: false` comparison analyses — COMPLETE

Implemented the full comparison-analysis execution path across arscore and
arsresult, enabling chi-square, ANOVA, and Fisher's exact test methods in the
stdlib.

**What was done:**

| Component | Change |
|-----------|--------|
| `arscore/R/ars_result_group.R` | Relaxed validator: `group_id` and `group_value` may both be `NA` (matches CDISC ARS v1.0 spec; both are optional). Added `@section Grouping-only result groups` roxygen docs. |
| `arsresult/R/run.R` — `.resolve_grouping_filter()` | When `group_id = NA`: returns a groupingId-only `ars_result_group` instead of `no_result`. No data filter applied (full analysis-set passes through). |
| `arsresult/R/run.R` — PIN + EXPAND paths | Added `.comparison_vars_from_factors()` helper; sets `attr(data, "comparison_vars")` before method call so comparison methods know the grouping variable. |
| `arsresult/R/stdlib.R` | Added `METH_CHISQ` (`OP_CHISQ_STAT`, `OP_CHISQ_PVAL`, `OP_CHISQ_DF`), `METH_ANOVA` (`OP_ANOVA_F`, `OP_ANOVA_PVAL`), `METH_FISHER` (`OP_FISHER_PVAL`). Added `.comparison_grouping_var()` shared helper. |
| `arstlf/R/prep_ard.R` | No change needed — `.extract_result_groups()` already returns `character(0)` when `group_id = NA`, and the row is gracefully skipped in `.expand_geom_to_tfrmt()`. |

**How comparison analyses work:**
1. Set `resultsByGroup: false` on the treatment grouping factor with NO `groupId`.
2. `run()` passes the full analysis-set-filtered dataset (all arms combined).
3. `attr(data, "comparison_vars")` is set with the treatment variable name.
4. The method function reads `comparison_vars[[1]]$grouping_variable` to know which column to group by.
5. A single result row is produced carrying `grouping_id = "GRP_TRT"`, `group_id = NA`.

**Test additions:**

| File | Tests added |
|------|-------------|
| `arscore/tests/testthat/test-ars_result_group.R` | +3: groupingId-only construction, format, JSON serialisation |
| `arsresult/tests/testthat/test-run.R` | +3 (Tests 9–11): comparison path no-filter, METH_CHISQ via run(), METH_ANOVA via run() |
| `arsresult/tests/testthat/test-stdlib.R` | +4: METH_CHISQ known data, all-NA when attrs absent, METH_ANOVA known data, METH_FISHER known data |

**Test totals after OI-07:**

| Package | Pass | Fail | Warn |
|---------|------|------|------|
| arscore | 1346 | 0 | 0 |
| arsshells | 534 | 0 | 0 |
| arsresult | 299 | 0 | 1 (expected) |
| arstlf | 115 | 0 | 0 |
| ars | 54 | 0 | 16 (expected) |
| **Total** | **2348** | **0** | **17** |

---

## SPRINT COMPLETE — 2026-02-28 (Session 4)

### ✅ OI-06 — `referencedOperationRelationships` formal denominator — COMPLETE

Added full NUMERATOR + DENOMINATOR `referencedOperationRelationships` declarations to all
four templates that use categorical/frequency `%` operations, and added a formal
`AN_HDR_N` denominator analysis to each.

**What was done:**

| Template | Method | ROR IDs added | Analyses wired |
|---|---|---|---|
| T-DM-01 | METH_CAT | `ROR_CAT_NPCT_NUM`, `ROR_CAT_NPCT_DEN` | AN_SEX, AN_RACE |
| T-AE-01 | METH_AE_FREQ | `ROR_AE_NPCT_NUM`, `ROR_AE_NPCT_DEN` | 7 AE analyses |
| T-DS-01 | METH_FREQ | `ROR_FREQ_NPCT_NUM`, `ROR_FREQ_NPCT_DEN` | 8 disposition analyses |
| T-AE-02 | METH_AE_FREQ | Added `ROR_NPCT_DENOMINATOR` (NUMERATOR already existed) | AN_SOC_TEAE, AN_PT_TEAE |

Each template gains a new **`AN_HDR_N`** analysis (dataset: ADSL, variable: USUBJID,
analysis set: the template's primary AS, method: same as other analyses, GRP_TRT only).
`AN_HDR_N` is a real executed analysis — its `OP_N` results per arm appear in the ARD,
making the column-N denominator explicit in the model rather than an internal side-channel.
No ShellCell references `AN_HDR_N`, so it does not affect the rendered table.

**arscore model was already complete** — `ars_referenced_operation_relationship`,
`ars_referenced_analysis_operation`, and `validate_reporting_event()` referential integrity
checks were all in place. This was purely template JSON work.

**Note on Task 3 (2026-02-27 sprint):** The original Task 3 completion note ("present in
T-AE-01.json, T-AE-02.json, T-DM-01.json") referred to a partial implementation — only
NUMERATOR ROR was present in T-AE-02; T-AE-01 and T-DM-01 had no RORs at all. Full
NUMERATOR + DENOMINATOR + `AN_HDR_N` + `referencedAnalysisOperations` wiring is the
complete implementation delivered here.

**Test impact:** 12 count assertions updated across 5 test files (analysis counts: T-DM-01
3→4, T-AE-01 7→8, T-DS-01 9→10, T-AE-02 2→3). T-DS-01 `dataSubsetId` assertion tightened
to exempt `AN_HDR_N` alongside `AN_RAND`. **Total: 2332 tests, 0 failures.**

---

## SPRINT COMPLETE — 2026-02-28 (Session 3)

### ✅ §23 CSD Compact Pattern Migration — T-DM-01, T-AE-01, T-DS-01 — COMPLETE

Migrated three templates from the PIN-path "one analysis per arm per row" structure
to the CSD `resultsByGroup: true` expand-path pattern. Each row variable now has a
single analysis that produces results for all arms via the expand path in `run()`.

#### Template changes

| Template | Analyses (before → after) | Cells (before → after) |
|----------|--------------------------|------------------------|
| T-DM-01 | 18 → 3 (`AN_AGE`, `AN_SEX`, `AN_RACE`) | 21 → 6 |
| T-AE-01 | 21 → 7 (one per AE category) | 21 → 7 |
| T-DS-01 | 27 → 9 (one per disposition row) | 27 → 9 |

All three templates:
- All analyses use `GRP_TRT` with `resultsByGroup: true`; column dimension driven by
  the ARD result-group columns, not the cell's `colLabel`.
- All cell `colLabel` values are `""` — column values come from the ARD.
- All analyses carry `"reason": "SPECIFIED IN SAP"` and
  `"purpose": "PRIMARY OUTCOME MEASURE"` (required by `ars_analysis` validator).

**T-DM-01 specifics:**
- `GRP_SEX` (Mode 1, fixed M/F conditions) is the row-dimension GF for `AN_SEX`.
- `GRP_RACE` (Mode 3, data-driven) is the row-dimension GF for `AN_RACE`.
- `AN_AGE` has only `GRP_TRT` (column dimension only); row labels ("n", "Mean (SD)",
  "Median", "Min, Max") come from `cell_row_label` in `prep_ard.R`.

**T-AE-01 specifics:**
- `AN_ANY_TEAE` through `AN_TEAE_DEATH` each have `GRP_TRT` only; row label
  comes from `cell_row_label` (e.g. "Subjects with any TEAE").

**T-DS-01 specifics:**
- `AN_RAND` has no `dataSubsetId`; all other 8 analyses reference a data subset.
- SEC_DISC_REASON cells use `indent: 1` (rendered by `prep_ard.R` space-padding).

#### `prep_ard.R` fix — cell row_label preserved in expand path (already in place)

`.expand_geom_to_tfrmt()` accepts `cell_row_label = ""` parameter. When no
row-dimension GF exists (only `GRP_TRT` as a column GF), the cell's explicit
`row_label` is used as the tfrmt `label` rather than falling back to `section_label`.
This is essential for T-AE-01 and T-DS-01 (single GF, column-only) and for the
T-DM-01 Age rows.

`prep_ard_for_tfrmt()` includes `"label"` in `unique_cells` and passes
`cell_row_label = row$label` to `.expand_geom_to_tfrmt()`.

#### Test changes

| File | Change |
|------|--------|
| `arsshells/tests/testthat/test-use_shell.R` | 3 assertions updated: 12 → 3 analyses; 12 → 4 cells for SEC_AGE; sex cell indent 1 → 0 |
| `arsshells/tests/testthat/test-template-T-DS-01.R` | Already correct (9 analyses, 4/5 cells) |
| `arsshells/tests/testthat/test-hydrate.R` | Already correct (expand-path arm injection tests) |
| `arstlf/tests/testthat/test-prep_ard.R` | Already correct (cell_row_label regression tests) |

**Test totals after migration:** arscore 1343, arsshells 534, arsresult 272, arstlf 115,
ars 54 — **total 2318, 0 failures**.

---

## SPRINT COMPLETE — 2026-02-28 (Session 2)

### ✅ §21 composite ops refactor — verified COMPLETE (2026-02-28)

Confirmed all components of the §21 flat operations refactor are in place:

- `arsresult/R/stdlib.R`: Returns flat scalars only (`OP_MEAN`, `OP_SD`, `OP_MIN`,
  `OP_MAX`). No `OP_MEAN_SD` or `OP_RANGE` composite ops.
- `T-DM-01.json`: Method ops declared as flat; cell `operationId`s use `OP_MEAN`
  (anchor for Mean+SD) and `OP_MIN` (anchor for Min+Max).
- `T-LB-01.json`: Same flat declarations and cell refs. Analysis IDs contain
  `OP_MEAN_SD`/`OP_RANGE` in the name segment only (cosmetic; not functional).
- `arstlf/R/prep_ard.R`: `.combined_ops` registry maps `OP_MEAN→[OP_MEAN,OP_SD]`
  and `OP_MIN→[OP_MIN,OP_MAX]`; `expand_combined_params()` exported.
- `arstlf/R/render_tfrmt.R`: `frmt_combine()` keyed on `OP_MIN` and `OP_MEAN`.
- `ars_explorer.R` `.embed_ard_into_re()`: Pre-filter removed; comment confirms
  "No pre-filter needed" since all ops are now formally declared.

**End-to-end validation:** T-LB-01 hydrated (7 PARAMCDs, 3 arms) → run → render
produces 1,344 ARD rows with operation IDs `{OP_COUNT, OP_MAX, OP_MEAN, OP_MEDIAN,
OP_MIN, OP_SD}` and renders cleanly to a `gt_tbl`. Zero warnings.

---

## SPRINT COMPLETE — 2026-02-28

Full pipeline validation and test hardening session.  All 6 templates pass
end-to-end; all 2329 tests pass (0 failures, 1 skip).

### ✅ Test hardening — cli line-wrap regex fixes (3 packages)

`cli::cli_abort()` / `cli_warn()` wrap long messages with `\n`, breaking
`expect_error` / `expect_warning` regexes that matched literal phrases split
across lines (e.g. `"missing\nrequired"`, `"data\nframe"`, `"Mode\n  2"`).

| File | Old regex | New regex |
|------|-----------|-----------|
| `arscore/tests/testthat/test-create_ard.R:131` | `"missing required"` | `"is missing"` |
| `arstlf/tests/testthat/test-prep_ard.R:348` | `"data frame"` | `"must be a data"` |
| `arstlf/tests/testthat/test-prep_ard.R:354` | `"missing required columns"` | `"is missing"` |
| `arsshells/tests/testthat/test-hydrate.R:391` | `"Mode 2"` | `"GRP_TRT"` |

### ✅ Test fixture fix — `__NONE__` sentinel → `NA` (3 files)

Test fixtures for T-AE-02 used `AEBODSYS = "__NONE__"` and `AEDECOD = "__NONE__"`
on sentinel rows.  Mode 3 expansion picked these up as real SOC/PT values,
inflating section and group counts.  Changed to `NA_character_` so they are
excluded by the `!is.na()` filter in `hydrate()`.

- `arsshells/tests/testthat/test-hydrate.R` (`.ae02_adae()`)
- `arsshells/tests/testthat/test-template-T-AE-02.R` (`.adae_ae02()`)
- `ars/tests/testthat/test-integration-T-AE-02.R` (`.adae_ae02()`)

### ✅ Test update — T-AE-02 template restructure (arsresult)

`arsresult/tests/testthat/test-transpile.R`: T-AE-02 template now has a single
`DS_TEAE` data subset with a simple `ars_where_clause_condition` (TRTEMFL EQ "Y")
instead of the old `DS_SOC_CARDIAC` compound expression.  Updated test to use
`transpile_condition()` instead of `transpile_compound()`.

### ✅ Test rewrite — pipe tests (ars)

`ars/tests/testthat/test-pipe.R`: Rewrote all pipe tests with shared fixture
helpers (`.pipe_adsl()`, `.pipe_adae()`, `.pipe_shell()`) that properly pass
`adam` to `hydrate()` for data-driven group resolution.  The old tests hydrated
T-AE-02 without `adam`, leaving GRP_SOC / GRP_PT unresolved.

`ars/tests/testthat/setup.R`: Added `run <- ars::run; render <- ars::render`
to ensure ars wrappers shadow `arsresult::run` / `arstlf::render` regardless
of `devtools::load_all()` search path ordering.

### ✅ Performance fix — lab template PARAMCD scoping

`data_table_examples.R`: Full pharmaverseadam ADLB has 47 PARAMCDs; Mode 3
expansion created 1504–1692 analyses, taking 2–3.5 minutes per lab template.
Scoped ADLB to curated subsets before passing to `hydrate()` / `run()`:

| Template | PARAMCDs | Before | After | Speedup |
|----------|----------|--------|-------|---------|
| T-LB-01 | 7 (HGB, PLT, WBC, ALT, AST, CREAT, GLUC) | ~2m 30s (1504 analyses) | 5.3s (224 analyses) | ~28× |
| T-LB-02 | 3 (HGB, ALT, CREAT) | ~3m 30s (1692 analyses) | 1.8s (108 analyses) | ~117× |

The full `adlb` object is preserved for other uses; only the `adam` argument to
`hydrate()` / `run()` receives the filtered subset.

---

## SPRINT COMPLETE — 2026-02-27

All four tasks from the 2026-02-27 sprint are done.  Verified by code inspection
and test runs on 2026-02-27.

### ✅ Task 1 — `dataSubsetId` filtering in `arsresult::run()` — DONE

Filter was already implemented (`run.R` step 4, lines 333–345).  Confirmed
working: zero-row subset test added at `test-run.R:420` ("Task 1 confirmation:
dataSubsetId filter is applied").  All 228 arsresult tests pass.

### ✅ Task 2 — §21 Flat operations refactor — DONE

`stdlib.R` — `OP_MEAN_SD`/`OP_RANGE` removed; flat `OP_MEAN`, `OP_SD`, `OP_MIN`,
`OP_MAX` registered individually.  `T-DM-01.json` and `T-LB-01.json` updated to
use flat operation IDs in cell references.  `ars_explorer.R`
`.embed_ard_into_re()` pre-filter removed (comment: "No pre-filter is needed").

**Leftover (arstlf tests):** 3 tests in `arstlf/tests/testthat/test-prep_ard.R`
were not updated when `OP_MEAN` became a combined display anchor.  They expect
`nrow(geom) == 2` and `result$value` length 1 but now get 3 and 2 respectively
(because `expand_combined_params("OP_MEAN")` → `c("OP_MEAN", "OP_SD")` expands
to two geometry rows).  These 3 tests need to be fixed — see §NEXT below.

### ✅ Task 3 — `referencedOperationRelationships` on percentage operations — DONE

`referencedOperationRelationships` present in `T-AE-01.json`, `T-AE-02.json`,
and `T-DM-01.json`.  JSON round-trips pass; validation passes.

### ✅ Task 4 — `validate_ordered_groupings` reference check — DONE

`validate_reporting_event.R` lines 139–167 check that every
`ordered_grouping@grouping_id` exists in `re@analysis_groupings` AND that
`group_id` (when set) resolves to a real group in that factor (tagged "Task 4").
Test added: `test-validate_reporting_event.R:1076`
"validate catches dangling group_id that does not exist in grouping factor".
All 1335 arscore tests pass.

---

### ✅ Task 5 — Fix 3 failing arstlf tests — DONE

Fixed `arstlf/tests/testthat/test-prep_ard.R`:
- "geometry extraction handles multiple sections": updated expected `nrow` from
  2 → 3 and `geom$group` to `c("Section A", "Section B", "Section B")` to
  reflect that `OP_MEAN` expands to 2 param rows under `expand_combined_params`.
- "prep_ard_for_tfrmt coerces raw_value to numeric": supplied both `OP_MEAN` and
  `OP_SD` ARD rows; asserts each param value independently.

All 112 arstlf tests pass.

### ✅ Task 6 — Fix `ars` package test failures — DONE

Root cause: `ars/tests/testthat/setup.R` computed `.ars_root` three directory
levels above `tests/` instead of two, landing in `Downloads/` rather than
`arsworks/`.  The `.try_load()` calls all silently no-op'd; sibling packages
stayed on renv-installed versions; under `devtools::test()` that caused both
`use_shell()` template lookup and `local_mocked_bindings` to fail.

Fix: changed `"..", "..", ".."` → `"..", ".."` so `.ars_root` correctly resolves
to the arsworks workspace root and all sibling packages load from source.

All 55 ars tests pass (1 expected warning about unhydrated grouping factor).

---

## SPRINT COMPLETE — 2026-02-27 (Session 2)

Phase B — section (row) expansion — is done.  Verified by code inspection and
full test run on 2026-02-27.

### ✅ Step B1 — `template_key` on `ShellSection` — DONE

`shell_section.R`: added `template_key = new_property(class_character, default = "")`.
Constructor, format(), and `.parse_shell_section()` in `use_shell.R` all updated.
JSON field is `"templateKey"`.

### ✅ Step B2 — T-LB-01.json prototype refactor — DONE

Replaced 5008-line hardcoded template (7 params × 2 timepoints) with a
168-line prototype containing:
- 2 prototype dataSubsets: `DS___PARAM___BL`, `DS___PARAM___CHG`
- 24 prototype analyses (4 stats × 3 arms × 2 timepoints)
- 2 prototype sections (`SEC___PARAM___BL`, `SEC___PARAM___CHG`) with `templateKey: "PARAMCD"`

### ✅ Step B3 — T-LB-02.json prototype refactor — DONE

Replaced 3670-line hardcoded template (7 params × 3 BL categories) with a
prototype containing:
- 9 prototype dataSubsets (3 BL × 3 POST categories)
- 27 prototype analyses (3 BL × 3 POST × 3 arms)
- 3 prototype sections (`SEC___PARAM___BLLow/Normal/High`) with `templateKey: "PARAMCD"`

### ✅ Step B5 — Phase 6: `section_map` (Mode 2) in `hydrate()` — DONE

`hydrate.R`: removed Phase B placeholder message; added Phase 6 block that
calls `.hydrate_section_map()`; added `section_map` to `nothing_to_do` check;
added unused-key warning and summary bullet.

`.hydrate_section_map()` and helpers (`.clone_ds_with_param()`,
`.sub_param_cond()`, `.sub_param_compound()`) added to `hydrate.R`.

Placeholder `__PARAM__` is substituted in section IDs, analysis IDs, and
data subset IDs. `__PARAM_LABEL__` is substituted in labels.

### ✅ Step B6 — Mode 3 section resolution from `adam` — DONE

When `adam` is supplied and the shell has prototype sections not covered by
`section_map`, `hydrate()` auto-derives distinct values from the named dataset
column and builds `section_map` entries automatically.

### ✅ Step B7 — Tests for Phase B — DONE

14 new tests in `arsshells/tests/testthat/test-hydrate.R` covering:
- `template_key` parsed from JSON
- T-LB-01 and T-LB-02 prototype shells pass `validate_shell()` before hydration
- Mode 2 section expansion: section count, labels, cell IDs, analyses, data subsets
- Mode 2: PARAMCD condition value substituted in data subsets
- Mode 2: validate_shell() passes on expanded shell
- Order control via `order` field in section_map entries
- Unused section_map key emits warning
- Mode 3: distinct PARAMCD values derived from adam
- Mode 3: no `__PARAM__` strings remain after expansion

**All 2360 tests pass (arscore 1335, arsshells 552, arsresult 266, arstlf 112,
ars 95). 0 failures, 1 skip (group ID sanitisation). Test fixes: cli line-wrap
regex hardening, `__NONE__` → `NA` sentinel fix, T-AE-02 transpile test updated,
pipe tests rewritten with proper data-driven hydration.**

### ✅ Fast-path expand tests added to arsresult — 2026-02-28

Two new unit tests in `arsresult/tests/testthat/test-run.R` targeting the
`.observed_combos()` fast path:

- **Test 6** `"fast path: observed_combos yields same ARD as Cartesian when all
  declared group combos have data"` — 2 TRT × 2 SOC dataset with all 4 cross-combos
  present; asserts `.observed_combos()` is non-NULL, length equals
  `.cartesian_product()`, group-ID signatures match, and ARD has 4 rows with n=1
  per cell.

- **Test 7** `"fast path: Total group on one factor produces EQ + Total combo
  variants"` — mirrors the T-AE-02 production pattern (GRP_TRT with EQ + is_total
  groups, GRP_SOC with EQ groups); asserts `.observed_combos()` powerset enumeration
  produces 6 combos (4 EQ + 2 Total), Total appears in exactly 2 combos, and ARD
  has correct n per cell (n=1 per arm/SOC, n=2 for Total/SOC).

- **Test 8** `"Cartesian fallback: orphaned SOC emits zero-count rows; TRT group
  recorded, SOC group absent"` — GRP_SOC declares Nervous with no matching data;
  `.observed_combos()` returns NULL (Cartesian active); ARD has 6 rows (2×3);
  covered combos have n=1; Nervous combos have n=0 with `group_id_1 = NA` because
  the SOC filter returns 0 rows causing the fi-loop to fire `next` before appending
  the SOC group; TRT group is recorded in the unnumbered `group_id` column
  (`create_ard.R:64` uses no suffix when `length(result_groups) == 1`).

### `.observed_combos()` decision logic

`.observed_combos()` returns a combo list (fast path) when **all** of these hold:

- Every expand factor has `grouping_variable` present in `base_data`
- All non-Total groups use simple EQ conditions
- Every declared EQ group value is present in `base_data` (no orphans)

Returns `NULL` (Cartesian fallback) when any condition fails.

### T-AE-02 production requirement — pre-filter ADAE before `hydrate()`/`run()`

**Pre-filter ADAE to TEAE rows before `hydrate()` / `run()`.** The full `adae`
includes non-TEAE rows; Mode 3 expansion derives PT groups from those rows too,
creating ~12 orphan PTs that are absent from `base_data` after the `TRTEMFL=Y`
filter. Those orphans trigger the Cartesian fallback (~96 s, 21,160 combos).
Pre-filtering ensures all derived PT groups are actually observed, activating
the fast path (~4 s, ~230 combos).

```r
adae_teae <- adae[!is.na(adae$TRTEMFL) & adae$TRTEMFL == "Y", ]
hydrate(..., adam = list(ADAE = adae_teae, ADSL = adsl))
run(adam = list(ADAE = adae_teae, ADSL = adsl))
```

### Bug fix — `template_key` not preserved through Phase 2/3 group expansion

`hydrate.R` `.hydrate_group_map()` and `.hydrate_adam_groups()` both rebuild
`ShellSection` objects without passing `template_key`. Fixed by adding
`template_key = sec@template_key` to both `new_shell_section()` calls.

---

## NEXT SESSION

### Recommended priorities

| Priority | Item | Notes |
|----------|------|-------|
| **1** | **New template batch** (T-VS-01, T-AE-03, T-AE-04, T-AE-05, T-EF-01, T-EX-01) | All blockers resolved; T-EF-01 can now include p-value rows (OI-07 ✅); highest-leverage work |
| **2** | **`gt` backend in arstlf** | High priority in §20; removes tfrmt dependency for direct gt assembly |
| **3** | **p-value column rendering in arstlf** | Enable tfrmt/gt layout for comparison ARD rows (group_id=NA) — needed before T-EF-01 renders correctly |
| — | ~~`resultsByGroup: false` for comparison analyses~~ | ✅ **COMPLETE** — 2026-02-28; OI-07. METH_CHISQ, METH_ANOVA, METH_FISHER in stdlib. groupingId-only result_groups. 2348 tests, 0 failures. |
| — | ~~`referencedOperationRelationships` formal denominator~~ | ✅ **COMPLETE** — 2026-02-28; OI-06. NUMERATOR + DENOMINATOR RORs + `AN_HDR_N` in all 4 templates. 2332 tests, 0 failures. |
| — | ~~**§21 composite ops refactor**~~ | ✅ **COMPLETE** — verified 2026-02-28. |
| — | ~~**§22 User Acceptance Testing (UAT)**~~ | ✅ **COMPLETE** — verified 2026-02-28. See §22 for results. |
| — | ~~**§23 CSD compact pattern migration**~~ (T-DM-01, T-AE-01, T-DS-01) | ✅ **COMPLETE** — 2026-02-28. See §23 for details. |

### Parking lot — resolved items

| Item | Status |
|------|--------|
| OI-06 `referencedOperationRelationships` formal denominator | ✅ **COMPLETE** — 2026-02-28; all 4 templates; `AN_HDR_N` added; 2332 tests |
| T-AE-02 → CSD migration (data-driven SOC/PT groupings) | ✅ **COMPLETE** — T-AE-02 uses `resultsByGroup:true` with data-driven GRP_SOC/GRP_PT; 276 table rows, 0 warnings |
| T-DM-01, T-AE-01, T-DS-01 → CSD compact pattern | ✅ **COMPLETE** — 2026-02-28; 3/7/9 analyses; expand path for all arm columns |
| Phase C — bundled CDISCPILOT01 data + getting-started vignette | ✅ **COMPLETE** — C1–C5 all done |
| Test hardening (cli line-wrap, `__NONE__` sentinels, pipe namespace) | ✅ **COMPLETE** — 2026-02-28; 2318 tests, 0 failures |
| Lab template performance (`data_table_examples.R`) | ✅ **COMPLETE** — ADLB scoped to curated PARAMCDs; 28–117× speedup |

---

## 0. Current State (as of 2026-02-22, updated 2026-02-28 — §23 CSD compact pattern migration complete)

### Suite overview

```
arscore    ← Foundation: S7 classes, JSON I/O, validation, ARD extraction
    ↓
arsshells  ← Builder/Factory: DSL that constructs arscore objects from templates
    ↓                   ↘
arsresult  ← Executor: Method Registry + WhereClause transpiler → ARD from ADaM
    ↓                   ↙
arstlf     ← Translator: arscore display metadata + ARD → tfrmt / gt → TLF files
    ↓
ars        ← Orchestrator: pipe-friendly workflow API, selective re-exports
```

### Per-package status

| Package | Version | Tests | Status |
|---------|---------|-------|--------|
| arscore | v0.1.0 | 1343 pass | ✅ All tasks complete; `validate_ordered_groupings` reference check added (Task 4) |
| arsshells | v0.1.0 | 534 pass | ✅ Phase A1–A7 + Phase B1–B7 complete; T-LB-01/02 refactored to prototypes; section_map (Mode 2+3) in hydrate(); T-DM-01/T-AE-01/T-DS-01 migrated to CSD compact pattern (§23); test-use_shell.R updated for new analysis/cell counts |
| arsresult | v0.1.0 | 272 pass (1 expected warn) | ✅ Phase A8–A11 complete; flat ops, expand path, PIN-path cache; fast-path tests 6–8 |
| arstlf | v0.1.0 | 115 pass | ✅ `cell_row_label` fix in `prep_ard.R` (§23); regression tests for expand-path row label preservation |
| ars | v0.1.0 | 54 pass | ✅ Task 6 complete; `setup.R` path fixed; test-pipe.R rewritten; **Phase C complete** — bundled datasets, `R/data.R`, `LazyData: true`, README Quick Start, getting-started vignette |

### Completed work by package

**arscore** — all 41 ARS v1.0 S7 entities, JSON round-trip, referential integrity
validation, ARD extraction, `group_id` on `ars_ordered_grouping_factor`,
`is_total` property on `ars_group` (Step A1),
document/terminology/programming code/compound expression/categorisation/
global display section/list-of-contents classes, vignettes, pkgdown, GitHub Actions.

**arsshells** — `Shell`/`ShellSection`/`ShellCell` S7 classes wrapping
`ars_reporting_event`, `validate_shell()`, `use_shell()`, `browse_shells()`,
`hydrate()` with full Phase A interface (`variable_map`, `label_map`,
`group_map` (Phase 2), `adam` (Phase 3), `subset_map` (Phase 4),
`metadata` (Phase 5), `section_map` placeholder (Phase 6)),
`hydrate_helpers.R` with `._hydrate_outputs()` bottom-up rebuild,
55-shell index.json, JSON schema,
6 Priority 1 templates (T-DM-01, T-DS-01, T-AE-01, T-AE-02, T-LB-01, T-LB-02)
updated for Phase A (arm conditions stripped, `isTotal` added, `groupId: null`
fixed, `dataDriven` markers set, top-level decorative arrays removed),
vignette, pkgdown, GitHub Actions.

**arsresult** — WhereClause transpiler (all 8 comparators, compound AND/OR),
method registry with `register_method()`, stdlib (METH_CONT, METH_FREQ,
METH_CAT, METH_AE_FREQ), `run()` pipeline (analysis-set filter → arm filter →
denominator → data-subset filter → method dispatch → ARD), `ArsResult` bundle
enabling pipe (`run() |> render()`),
Phase A bug fixes complete: denominator `tryCatch` now warns instead of silent
fallback (A8), `.make_c()` always wraps single values in `c()` (A9),
unhydrated non-Total conditionless groups warn at `run()` time (A10),
unnamed method return values warn and are discarded (A11),
vignette, pkgdown, GitHub Actions.

**arstlf** — `render()` with tfrmt backend, `render_mock()`, `build_tfrmt()`,
`prep_ard_for_tfrmt()`, ARS→tfrmt mapping spec, N=xx column header resolution
at render time, vignette, pkgdown, GitHub Actions.

**ars** — `ars_pipeline()`, selective re-exports of the full workflow API,
`ArsResult` S3 class enabling the clean pipe pattern, unit + integration tests,
vignettes, pkgdown, GitHub Actions.

### Installed templates (6 / 55)

All six templates use the CSD `resultsByGroup: true` expand-path pattern.
Analysis counts are template-level (pre-hydration); run-time expand path produces
results for all arms from each single analysis.

| ID | Name | Dataset | Analyses | Pattern |
|----|------|---------|----------|---------|
| T-DM-01 | Summary of Demographic Characteristics | ADSL | 4 (3 + AN_HDR_N) | CSD compact (§23, OI-06) |
| T-DS-01 | Subject Disposition | ADSL | 10 (9 + AN_HDR_N) | CSD compact (§23, OI-06) |
| T-AE-01 | Overview of Adverse Events | ADAE | 8 (7 + AN_HDR_N) | CSD compact (§23, OI-06) |
| T-AE-02 | TEAEs by SOC and PT | ADAE | 3 (2 + AN_HDR_N) | CSD (GRP_TRT × GRP_SOC/PT, expand, OI-06) |
| T-LB-01 | Summary of Laboratory Parameters | ADLB | 24 prototype → expands per PARAMCD | Prototype section (Phase B) |
| T-LB-02 | Shift Table — Lab Values | ADLB | 27 prototype → expands per PARAMCD | Prototype section (Phase B) |

### GitHub Pages

All 5 repos are currently **private**. pkgdown workflows build the site and
upload it as a downloadable Actions artifact on every push to `main`.

To enable live hosting when repos go public:
1. In each repo Settings → Pages, set Source to `gh-pages` branch.
2. Uncomment the deploy step in `.github/workflows/pkgdown.yml`.
3. Use an org-scoped PAT secret — `GITHUB_TOKEN` only has access to the
   current repo, not sibling private repos.

| Package | URL (once public) |
|---------|-------------------|
| arscore | https://opentrialreporting.github.io/arscore/ |
| arsshells | https://opentrialreporting.github.io/arsshells/ |
| arsresult | https://opentrialreporting.github.io/arsresult/ |
| arstlf | https://opentrialreporting.github.io/arstlf/ |
| ars | https://opentrialreporting.github.io/ars/ |

### Developer quick reference

```r
# Load and test any package
devtools::load_all("arscore")
devtools::test("arscore")

# Test a specific file
testthat::test_file("arsresult/tests/testthat/test-stdlib.R")

# Document and install
devtools::document("ars")

# Full suite install (dependency order)
for (pkg in c("arscore", "arsresult", "arsshells", "arstlf", "ars")) {
  install.packages(file.path("path/to/arsworks", pkg), repos = NULL, type = "source")
}

# Build pkgdown site locally
withr::with_dir("ars", pkgdown::build_site(preview = FALSE, new_process = FALSE))
```

---

> **Ordering constraint — template staging:**  
> The 6 JSON template updates (Step A2) strip hardcoded arm condition values.
> Once merged, existing `hydrate()` calls without `group_map` will produce
> empty groups — a **breaking change** for current users.  
> Template changes must be **merged on a feature branch** and held until either:
> (a) Phase C bundled data is ready and the README examples are updated, or  
> (b) the README examples are simultaneously updated to use `group_map` with
> the synthetic test-data values (`"Treatment A"`, `"Treatment B"`).  
> All other Phase A steps can merge independently.

> **Architecture decision confirmed:**  
> Display metadata (titles, footnotes, abbreviations) uses **Option A —
> inline `ars_display_sub_section` objects only**. Global display sections
> (`sub_section_id` references) are deferred to a future release and passed
> through unchanged by `._hydrate_outputs()`.

---

## 1. Problem Statement

All 6 installed shell templates have **three classes** of hardcoding problem:

### 1.1 Column dimension — grouping filter values

Treatment arm filter values (`TRT01A == "Treatment A"`) are baked into the
template JSON. Every study has different treatment labels. The current
`hydrate()` can remap variable *names* and display *labels* but never touches
condition *values*. A study whose `TRT01A` values are `"Placebo"` and
`"Xanomeline High Dose"` will produce **empty groups** at execution time with
no error or warning.

### 1.2 Row/section dimension — data-subset filter values and section coverage

Templates like T-LB-01 hardcode which lab parameters appear (7 PARAMCDs, 168
analyses). A real study has 40+. T-AE-02 hardcodes SOCs and PTs that are
entirely data-driven. T-DM-01 hardcodes race levels that vary by study and
region.

**Additionally**, data-subset filter *values* are hardcoded. Conditions such
as `AEREL IN ["PROBABLE", "POSSIBLE", "RELATED"]` or `AETOXGR GE ["3"]` are
specific to the coding conventions of a given study. A study that codes drug
relationship as `"YES"` / `"NO"` will produce empty results from `DS_TEAE_REL`
with no error. This is the same class of silent failure as the arm filter
problem.

### 1.3 Display metadata — titles, footnotes, abbreviations

Titles, footnotes, and abbreviations are buried **seven levels deep** in the
ARS class hierarchy:

```
ars_reporting_event → ars_output → ars_ordered_display
  → ars_output_display → ars_display_section
    → ars_ordered_display_sub_section → ars_display_sub_section@text
```

The current `hydrate()` explicitly passes the outputs subtree through
unchanged. There is no mechanism to set or override display text at the
`hydrate()` call. Developers either leave template boilerplate titles in place
or must manually construct the full seven-level hierarchy from scratch.

Additionally, the JSON templates contain top-level `"titles"`, `"footnotes"`,
and `"abbreviations"` arrays that `use_shell()` never reads. They are
maintenance hazards — edits to the display sections in `reportingEvent` must
be reflected manually in the top-level arrays or they silently diverge.

### 1.4 Other known issues

Several shells (T-AE-01, T-DS-01, T-LB-01) have `groupId: null` in analysis
`orderedGroupings` — a silent execution bug where analyses carry a grouping
reference but no group identity and are never arm-filtered.

CDISC Pilot data examination reveals:
- 3 treatment arms, not 2 (`Placebo`, `Xanomeline Low Dose`, `Xanomeline High Dose`)
- `RACE` values are uppercase (`WHITE`, `BLACK OR AFRICAN AMERICAN`) — templates
  have mixed case
- `AMERICAN INDIAN OR ALASKA NATIVE` is present in the data but absent from
  the template

---

## 2. The Three-Mode Model

All grouping, section, and filter dimensions in any shell fall into exactly
**three modes**:

| Mode | Definition | Examples | Who supplies the value |
|------|-----------|----------|------------------------|
| **1 — Fixed** | Value standardised by CDISC / ADaM convention. Known at template design time. | `SAFFL == "Y"`, `SEX == "M"/"F"`, `TRTEMFL == "Y"` | Template JSON (hardcoded — correct) |
| **2 — Pre-specified** | Study-specific but known before data arrives — defined in protocol or SAP. | `TRT01A` levels, `AGEGR1` levels, `AEREL` coding, dose groups | User supplies via `hydrate()` |
| **3 — Data-driven** | Only knowable once data exists. | `RACE` levels, `AEBODSYS`/`AEDECOD`, `ETHNIC`, `PARAMCD` | Derived from data inside `hydrate()` |

---

## 3. Design Principles

1. **Templates are structural specifications, not execution scripts.**
   They declare shape and statistics but contain no study-specific values.

2. **Mode is declared in the template, not discovered at runtime.**
   The JSON marks each dimension with its mode. `hydrate()` reads it and acts
   accordingly.

3. **`hydrate()` is the single point of study-specific wiring.**
   After `hydrate()` runs the shell is fully specified: every group has a
   condition, every section a label, every display text is set. `run()` sees
   no difference between pre-specified and data-driven shells.

4. **`dataDriven: true` maps cleanly onto Mode 3.**
   The ARS spec flag is semantically correct. Mode 2 groupings use
   `dataDriven: false` with placeholder groups (no condition values).

5. **`run()` remains simple.**
   Data-driven resolution happens inside `hydrate()`, not `run()`. `run()` is
   stateless with respect to data it has not yet seen.

6. **Backwards compatibility.**
   Mode 1 templates work without any `hydrate()` call. Existing `hydrate()`
   calls without new arguments continue to work unchanged.

7. **Display metadata is study-time, not template-time.**
   Templates carry placeholder text. `hydrate()` replaces it. Template authors
   do not manage study-specific titles.

8. **Inline display sections only (Option A confirmed).**
   Only inline `ars_display_sub_section` objects are rebuilt by
   `._hydrate_outputs()`. Global `sub_section_id` references are passed
   through unchanged and deferred to a future release.

---

## 4. Proposed `hydrate()` Interface

```r
hydrate(
  shell,

  # Existing — variable name remapping and label cosmetics (unchanged)
  variable_map = c(TRT01A = "TRTP"),
  label_map    = c("Treatment A (N=xx)" = "Placebo (N=xx)"),

  # New — Mode 2: pre-specified group values (treatment arms, dose levels)
  group_map = list(
    GRP_TRT = list(
      list(id = "GRP_TRT_A", value = "Placebo",              order = 1L),
      list(id = "GRP_TRT_B", value = "Xanomeline Low Dose",  order = 2L),
      list(id = "GRP_TRT_C", value = "Xanomeline High Dose", order = 3L)
    )
  ),

  # New — Mode 2: override specific condition values inside named data subsets
  subset_map = list(
    DS_TEAE_REL = list(variable = "AEREL",   comparator = "IN",
                       value    = c("YES")),
    DS_TEAE_GR3 = list(variable = "AETOXGR", comparator = "GE",
                       value    = c("2"))
  ),

  # New — Mode 2/3: pre-specified section values (lab params, etc.)
  # Phase B only — not implemented in Phase A
  section_map = list(
    PARAMCD = list(
      list(value = "HGB", label = "Haemoglobin (g/dL)"),
      list(value = "ALT", label = "Alanine Aminotransferase (U/L)")
    )
  ),

  # New — Mode 3: data supplied; distinct values derived automatically
  adam = list(ADSL = adsl, ADAE = adae),

  # New — Display metadata: titles, footnotes, abbreviations
  metadata = list(
    title        = c(
      "Table 14.1.1 Summary of Demographic Characteristics",
      "Safety Population"
    ),
    footnote     = c(
      "Age and weight are summarised as mean (SD), median, and range.",
      "Abbreviations: n = number of subjects; SD = Standard Deviation."
    ),
    footnote_append = FALSE,   # FALSE = replace template footnotes (default)
                               # TRUE  = append after existing footnotes
    abbreviation = c(
      "n = number of subjects",
      "SD = Standard Deviation"
    ),
    output_name   = "Table 14.1.1",  # ars_output@name
    display_title = "Table 14.1.1"   # ars_output_display@display_title
  ),

  quiet = FALSE
)
```

**Rules:**
- `group_map` → Mode 2 for the named grouping factors
- `subset_map` → Mode 2 value override for named data subsets; only the listed
  variable's `comparator` and `value` are replaced; all other sub-clauses and
  the subset ID are unchanged
- `adam` → Mode 3 for any grouping factor with `dataDriven: true`; `hydrate()`
  queries `distinct()` values internally
- `metadata` → rebuilds the outputs subtree with the supplied display text;
  NULL (default) passes the subtree through unchanged
- `section_map` → Phase B only; accepted in Phase A but no-op with a message
- A single call can mix modes freely
- If a Mode 3 grouping exists in the template but neither `adam` nor
  `section_map` is supplied, `hydrate()` errors with a clear message
- Unused keys in any map emit a warning after that phase completes

---

## 5. Template JSON Changes

### 5.1 Mode 2 groupings — strip condition values, keep structure

```json
// Before
{
  "id": "GRP_TRT_A", "label": "Treatment A (N=xx)", "order": 1,
  "condition": { "variable": "TRT01A", "comparator": "EQ", "value": ["Treatment A"] }
}

// After
{ "id": "GRP_TRT_A", "label": "Treatment A (N=xx)", "order": 1 }
```

The Total group (`GRP_TRT_TOT`) has no condition today; add `"isTotal": true`
to mark it explicitly (see §6).

### 5.2 Mode 3 groupings — `dataDriven: true`, no groups list

```json
{
  "id": "GRP_RACE",
  "name": "Race Group",
  "dataDriven": true,
  "groupingVariable": "RACE"
}
```

`hydrate()` reads `distinct(adam$ADSL, RACE)` and builds the groups list.

### 5.3 Fix `groupId: null` analyses

T-AE-01, T-DS-01, T-LB-01: infer `groupId` from the analysis ID suffix:
- `_TRT_A` → `GRP_TRT_A`
- `_TRT_B` → `GRP_TRT_B`
- `_TOT` → `GRP_TRT_TOT`

### 5.4 Remove top-level decorative arrays

The top-level `"titles"`, `"footnotes"`, and `"abbreviations"` arrays are
never read by `use_shell()`. Remove them from all 6 templates. The canonical
source of display text is `reportingEvent.outputs`.

### 5.5 Staging note

All template changes (§5.1–5.4) are implemented in a **dedicated feature
branch**. They must not be merged to main until Phase C is ready or the README
examples are simultaneously updated to pass `group_map` with the synthetic
test-data arm values.

---

## 6. `arscore` Changes — `is_total` on `ars_group`

```r
is_total = new_property(class_logical, default = FALSE)
```

Serialised as `"isTotal"` in JSON. Default `FALSE`; existing objects
unaffected.

**Purpose:** Allows `arsresult::run()` to distinguish "Total = conditionless
by design" (`is_total = TRUE`) from "arm group missing condition because
`hydrate()` was not called" (`is_total = FALSE`, no condition).

---

## 7. `hydrate()` Internal Logic

Execution is a linear six-phase pipeline. Phases execute sequentially in the
order below; each phase receives the reporting event (or shell) rebuilt by the
previous phase.

### Phase 1 — Variable and label substitution (existing, unchanged)

Walks the reporting event tree substituting variable names and label strings.
Skips entirely if both maps are NULL.

### Phase 2 — Group expansion (`group_map`, Mode 2)

For each grouping factor ID in `group_map`:
1. Look up the `ars_grouping_factor` in the reporting event.
2. For each entry in the user list:
   - **Update** existing group: inject condition value (`EQ` for scalar,
     `IN` for vector), update order.
   - **Create** new group: build `ars_group` with condition derived from the
     grouping factor's `groupingVariable`.
3. **Remove** template groups absent from `group_map` (Total is never removed).
4. Rebuild `ars_grouping_factor` with the resolved group list.
5. Clone/drop `ars_analysis` objects: find analyses referencing this grouping
   factor, group by base ID (strip arm suffix), clone for new arms, drop for
   removed arms.
6. Rebuild `colHeaders` and `ShellCell` col_labels to match.

**ID conventions:**
- New group ID: user-supplied `id` field (explicit, never derived)
- New analysis ID: `<baseId>_<last segment of group id>` (e.g. `AN_AGE_C`)
- Total group is always preserved; cannot be removed via `group_map`

### Phase 3 — Data-driven group resolution (`adam`, Mode 3)

For each `ars_grouping_factor` with `dataDriven: true`:
1. Identify source dataset from `groupingDataset` (or infer from analyses
   referencing this grouping factor).
2. Query `distinct(adam[[dataset]], groupingVariable)`.
3. For each distinct value, build `ars_group` with:
   - `id`: sanitised from value (e.g. `GRP_RACE_WHITE`)
   - `label`: raw value; user can override via `label_map`
   - `order`: frequency-descending; alphabetical as tie-break
   - `condition`: `variable EQ value`
   - `is_total`: FALSE
4. Set `dataDriven: false` on the rebuilt grouping factor — the shell is now
   fully specified.
5. Clone analyses and ShellCells as per Phase 2.

### Phase 4 — Data-subset value override (`subset_map`, Mode 2)

For each data subset ID in `subset_map`:
1. Look up the `ars_data_subset` in the reporting event by ID.
2. Recursively walk its `condition` / `compound_expression` tree to find the
   sub-clause whose `variable` matches the entry's `variable` field.
   Traversal is **fully recursive** — nested compound expressions are walked
   to any depth.
3. Replace `comparator` and `value` on that sub-clause only. All sibling
   sub-clauses (e.g. the `TRTEMFL == "Y"` anchor) are preserved unchanged.
4. Rebuild the data subset bottom-up into a new `ars_data_subset`.
5. Named subset not found in reporting event → **warning** (not error).
6. Named `variable` not found in the subset's condition tree → **error** with
   the subset ID and variable name in the message.

**Example:**

```
Template: DS_TEAE_REL → AND(TRTEMFL EQ ["Y"], AEREL IN ["PROBABLE","POSSIBLE","RELATED"])

subset_map = list(DS_TEAE_REL = list(variable = "AEREL", comparator = "IN", value = "YES"))

Result:   DS_TEAE_REL → AND(TRTEMFL EQ ["Y"], AEREL IN ["YES"])
```

### Phase 5 — Display metadata (`metadata`, outputs subtree)

If `metadata` is NULL, skip entirely — outputs subtree is passed through
unchanged with zero performance cost.

Otherwise delegate to `._hydrate_outputs()` (see §8).

### Phase 6 — Section expansion (`section_map` / `adam`, Modes 2+3)

**Phase B only.** In Phase A, if `section_map` is supplied, emit an
informational message (`"section_map is reserved for Phase B"`) and continue.
Sections are passed through unchanged.

### Reporting

After all phases, `hydrate()` emits a structured `cli` summary:
- Groups resolved per grouping factor (mode and count)
- Data subsets overridden
- Display sections updated (title / footnote / abbreviation)
- Unused keys in `variable_map`, `label_map`, `subset_map` → **warning**
- Mode 3 groupings and their data-derived value counts → informational

---

## 8. `._hydrate_outputs()` — Bottom-up Immutable Rebuild

Extracted into a dedicated **`hydrate_helpers.R`** file in `arsshells/R/`,
following the same bottom-up immutable rebuild pattern as the rest of
`hydrate()`.

### Call chain (leaf → root)

```
Level 7 (leaf)
._hydrate_display_sub_section(x, new_text)
  → new_ars_display_sub_section(id = x@id, text = new_text)

Level 6
._hydrate_ordered_sub_section(x, new_text)
  → If x@sub_section_id is set (global reference): return x unchanged.
  → Otherwise:
    new_ars_ordered_display_sub_section(
      order       = x@order,
      sub_section = ._hydrate_display_sub_section(x@sub_section, new_text)
    )

Level 5
._hydrate_display_section(x, metadata)
  → If x@section_type not in {Title, Footnote, Abbreviation} or
     the corresponding metadata field is NULL: return x unchanged.
  → Determine new_texts and append flag from metadata.
  → Replace mode: build new ordered_sub_sections from new_texts,
    with order = seq_along(new_texts) and generated IDs
    paste0(x@section_type, "_", seq_along(new_texts)).
  → Append mode (footnote only): keep existing ordered_sub_sections,
    append new ones with order continuing from max(existing order) + 1.
  → new_ars_display_section(
      section_type         = x@section_type,
      ordered_sub_sections = rebuilt_sub_sections
    )

Level 4
._hydrate_output_display(x, metadata)
  → new_ars_output_display(
      id             = x@id,
      name           = x@name,
      description    = x@description,
      label          = x@label,
      version        = x@version,
      display_title  = metadata$display_title %||% x@display_title,
      display_sections = lapply(x@display_sections,
                           \(s) ._hydrate_display_section(s, metadata))
    )

Level 3
._hydrate_ordered_display(x, metadata)
  → new_ars_ordered_display(
      order   = x@order,
      display = ._hydrate_output_display(x@display, metadata)
    )

Level 2
._hydrate_output(x, metadata)
  → new_ars_output(
      id       = x@id,
      name     = metadata$output_name %||% x@name,
      # all remaining properties (file_specifications, category_ids,
      # document_refs, programming_code) passed through unchanged
      displays = lapply(x@displays,
                   \(d) ._hydrate_ordered_display(d, metadata))
    )

Level 1 (entry point)
._hydrate_outputs(outputs, metadata)
  → lapply(outputs, \(o) ._hydrate_output(o, metadata))
```

### Metadata field → display section mapping

| `metadata` field | Target | Behaviour |
|---|---|---|
| `title` | `section_type = "Title"` | Replace (always) |
| `footnote` | `section_type = "Footnote"` | Replace or append per `footnote_append` |
| `abbreviation` | `section_type = "Abbreviation"` | Replace (always) |
| `output_name` | `ars_output@name` | Direct property override |
| `display_title` | `ars_output_display@display_title` | Direct property override |

**Multi-output shells:** `metadata` is applied to all outputs uniformly.
Targeting a specific output by ID is deferred (see §16).

---

## 9. `arsresult` — Bug Fixes and Safety ✅ ALL COMPLETE

### 9.1 Unhydrated arm group warning ✅

In `.resolve_grouping_filter()`: if a group has no condition and `is_total`
is not `TRUE`, `run()` emits a `cli::cli_warn()` naming the analysis and
group, indicating `hydrate()` was likely not called. Total groups
(`is_total = TRUE`) pass through silently as intended. Uses `tryCatch` on
`grp_obj@is_total` for backwards compatibility with older `ars_group` objects.

### 9.2 Denominator `tryCatch` silent fallback ✅ (was CRITICAL)

**Was:** `tryCatch` swallowed filter errors and fell back to unfiltered ADSL.

**Fix applied:** All three denominator `tryCatch` blocks (analysis-set filter
on ADSL, grouping condition filter on ADSL, grouping compound expression
filter on ADSL) now emit `cli::cli_warn()` with the analysis ID, error
message, and a note that the denominator may be incorrect. The fallback to
unfiltered data is preserved (to avoid blocking the entire pipeline on one
analysis), but the issue is now visible.

### 9.3 Silent filter failure in denominator ✅ (was CRITICAL)

Same fix as §9.2 — all three `tryCatch` blocks now warn.

### 9.4 `.make_c()` single-value `IN` bug ✅ (was HIGH)

```r
# Before — returned bare scalar; x %in% value works by accident
if (length(vals) == 1L) return(vals[[1L]])

# After — always wraps in c(); semantically correct
rlang::call2("c", !!!vals)
```

Single-value IN now transpiles to `SEX %in% c("M")` instead of `SEX %in% "M"`.
Existing test updated to expect the new form. Two new tests verify single-value
IN and NOTIN filter correctly at the data level.

### 9.5 Unnamed method return values silently dropped ✅ (was MEDIUM)

In `run()`, after calling the method function, the return value is now
validated. If `length(vals) > 0` and `names(vals)` is `NULL`, a
`cli::cli_warn()` is emitted naming the method, operation, and analysis.
The unnamed return is discarded (`next`) and the operation gets `NA`.
Previously the `for (nm in names(vals))` loop was silently a no-op.

---

## 10. `arsshells` — Validation Gaps

### 10.1 `validate_shell()` incomplete reference chain

Currently checks `ShellCell@analysis_id` and `@operation_id` only. Missing:
- `analysis@analysis_set_id` → exists in `@analysis_sets`
- `analysis@data_subset_id` → exists in `@data_subsets`
- `analysis@ordered_groupings[*]@grouping_id` → exists in `@analysis_groupings`
- `analysis@ordered_groupings[*]@group_id` → exists in grouping's `@groups`

**Fix:** Call `arscore::validate_reporting_event()` from within
`validate_shell()`, or implement the four checks directly.

### 10.2 Crash on empty `@analyses`

`vapply(re@analyses, ...)` crashes if `@analyses` is empty.

**Fix:** Guard with `if (length(re@analyses) == 0L)` before index building.

### 10.3 `use_shell()` case-sensitive ID matching

`use_shell("t-dm-01")` fails to find `T-DM-01.json`.

**Fix:** Normalise the input ID (trim, uppercase) before file matching.

### 10.4 Unused map keys not reported

`hydrate()` gives no feedback when a `variable_map`, `label_map`, or
`subset_map` key matches nothing. Typos silently do nothing.

**Fix:** After each phase, compare used keys against the supplied map and warn
for any keys that matched nothing.

---

## 11. Implementation Order

### Phase A — Group expansion, display metadata, bug fixes

Implemented across packages in dependency order. The template changes (Step A2)
are staged on a feature branch (see §5.5).

```
Step A1:  arscore    — add is_total to ars_group; JSON serialisation round-trip  ✅ DONE
Step A2:  arsshells  — update 6 JSON templates:                                 ✅ DONE (merged to main)
                        strip arm condition values; add isTotal to Total groups;
                        fix groupId: null; mark dataDriven groupings;
                        remove top-level decorative arrays
Step A3:  arsshells  — implement Phase 2: group_map (Mode 2) in hydrate()       ✅ DONE
Step A4:  arsshells  — implement Phase 3: adam Mode 3 group resolution          ✅ DONE
Step A5:  arsshells  — implement Phase 4: subset_map in hydrate()               ✅ DONE
Step A6:  arsshells  — implement Phase 5: metadata + hydrate_helpers.R          ✅ DONE
Step A7:  arsshells  — unused map key warnings; validate_shell() gaps (§10);    ✅ DONE (unused key warnings done;
                        use_shell() case normalisation                                   validate_shell() and case
                                                                                         normalisation need verification)
Step A8:  arsresult  — fix denominator tryCatch (§9.2/9.3)                      ✅ DONE (warns, no silent fallback)
Step A9:  arsresult  — fix .make_c() single-value IN (§9.4)                     ✅ DONE (always c())
Step A10: arsresult  — unhydrated arm group warning (§9.1)                      ✅ DONE (checks is_total)
Step A11: arsresult  — unnamed method return warning (§9.5)                     ✅ DONE (warns + discards)
Step A12: All        — tests and docs for Phase A                               ✅ DONE
                        Templates merged to main. All ars tests pass
                        (0 fail, 0 warn, 54 pass).
```

### Phase B — Section (row) expansion

```
Step B1: arsshells  — add template_key to ShellSection class              ✅ DONE
Step B2: arsshells  — refactor T-LB-01/02 JSONs to prototype sections     ✅ DONE
Step B3: arsshells  — refactor T-AE-02 JSON to prototype SOC section           ✅ DONE — template has `templateKey: "AEBODSYS"` prototype section; Mode 3 section expansion tested in test-hydrate.R B3 suite (8 tests)
Step B4: arsshells  — refactor T-DM-01 Race section to template section        (deferred — Race is already Mode 3 via adam)
Step B5: arsshells  — implement Phase 6: section_map (Mode 2) in hydrate() ✅ DONE
Step B6: arsshells  — implement Mode 3 section resolution (adam arg)       ✅ DONE
Step B7: All        — tests and docs for Phase B                           ✅ DONE
```

### Phase C — Bundled example data and complete README
**Prerequisite: Phase A template branch must be merged. ✅ Done (templates live on arsshells/main).**

```
Step C1: ars  — add CDISCPILOT01 datasets as bundled package data         ✅ DONE (commit 4a60a6d)
Step C2: ars  — document datasets with roxygen2                            ✅ DONE (commit 4a60a6d)
Step C3: ars  — update README with complete, runnable examples             ✅ DONE (commit f6b5e2d)
Step C4: ars  — add DESCRIPTION LazyData: true; data source note          ✅ DONE (commit 4a60a6d)
Step C5: ars  — getting-started vignette                                   ✅ DONE (commit 6dcc479)
```

---

## 12. File Change Inventory

### Phase A

| Package | File | Change |
|---------|------|--------|
| arscore | `R/ars_group.R` | Add `is_total` property (default `FALSE`) |
| arscore | `R/ars_json.R` | Serialise/deserialise `isTotal` ↔ `is_total` |
| arscore | `tests/testthat/test-ars_group.R` | Construct, serialise, round-trip with `is_total` |
| arsshells | `inst/templates/tables/T-DM-01.json` | Strip arm conditions; add `isTotal`; RACE → `dataDriven: true`; remove top-level arrays *(feature branch)* |
| arsshells | `inst/templates/tables/T-AE-01.json` | Strip arm conditions; add `isTotal`; fix null groupIds; remove top-level arrays *(feature branch)* |
| arsshells | `inst/templates/tables/T-AE-02.json` | Strip arm conditions; add `isTotal`; remove top-level arrays *(feature branch)* |
| arsshells | `inst/templates/tables/T-DS-01.json` | Strip arm conditions; add `isTotal`; fix null groupIds; remove top-level arrays *(feature branch)* |
| arsshells | `inst/templates/tables/T-LB-01.json` | Strip arm conditions; add `isTotal`; fix null groupIds; remove top-level arrays *(feature branch)* |
| arsshells | `inst/templates/tables/T-LB-02.json` | Strip arm conditions; add `isTotal`; remove top-level arrays *(feature branch)* |
| arsshells | `R/hydrate.R` | Add `group_map`, `subset_map`, `adam`, `metadata` args; Phases 2–5 logic; Phase 6 placeholder; unused key warnings |
| arsshells | `R/hydrate_helpers.R` | **NEW** — `._hydrate_outputs()` and all sub-functions (Levels 1–7) |
| arsshells | `R/validate_shell.R` | Full reference chain; empty-analyses guard; `use_shell()` ID normalisation |
| arsshells | `tests/testthat/test-hydrate.R` | Group, subset_map, metadata, Mode 3, mixed-mode tests (see §13) |
| arsresult | `R/run.R` | ✅ Denominator `tryCatch` warns (3 blocks); unhydrated arm warning in `.resolve_grouping_filter()`; unnamed method return validation + discard |
| arsresult | `R/transpile.R` | ✅ `.make_c()` always wraps in `c()` |
| arsresult | `tests/testthat/test-run.R` | ✅ +7 tests: denom resilience, sub_clause_id error, A10 warn/no-warn, A11 unnamed return; GRP_TOT fixture updated to `is_total = TRUE` |
| arsresult | `tests/testthat/test-transpile.R` | ✅ Updated single-value IN expectation; +2 tests: single-value IN/NOTIN data-level filtering |
| ars | `tests/testthat/test-integration-T-AE-02.R` | ✅ All `run()` calls now hydrate with `group_map` first; `ars_pipeline()` test suppresses A10 warnings |
| ars | `tests/testthat/test-pipe.R` | ✅ Rewritten: replaced fragile `local_mocked_bindings` with real minimal-data tests for ArsResult, render() unpacking, and full pipe |
| ars | `README.md` | Update workflow example (coordinate with template branch merge) |

### Phase B

| Package | File | Change |
|---------|------|--------|
| arsshells | `R/shell_classes.R` | Add `template_key` to `ShellSection` |
| arsshells | `inst/templates/tables/T-LB-01.json` | Refactor to 2 prototype sections + prototype analyses |
| arsshells | `inst/templates/tables/T-LB-02.json` | Refactor to 3 prototype sections |
| arsshells | `inst/templates/tables/T-AE-02.json` | Refactor to 1 prototype SOC section |
| arsshells | `inst/templates/tables/T-DM-01.json` | Race section → template section |
| arsshells | `R/hydrate.R` | Implement Phase 6: section_map and Mode 3 section expansion |
| arsshells | `R/hydrate_helpers.R` | Section expansion helpers |
| arsshells | `R/validate_shell.R` | Validate template section prototype structure |
| arsshells | `tests/testthat/test-hydrate.R` | Section expansion tests |
| ars | `README.md` | Update with `section_map` examples |

### Phase C

| Package | File | Change |
|---------|------|--------|
| ars | `data-raw/create_package_data.R` | ✅ Provenance and preparation script (synthetic CDISCPILOT01-style data) |
| ars | `data/adsl.rda` | ✅ Bundled ADSL (60 subjects × 12 cols; 40-subject safety population, 2 arms) |
| ars | `data/adae.rda` | ✅ Bundled ADAE (125 rows; covers all 6 Priority-1 AE analyses) |
| ars | `data/adlb.rda` | ✅ Bundled ADLB (840 rows; covers T-LB-01 and T-LB-02) |
| ars | `R/data.R` | ✅ Roxygen2 documentation for all three datasets |
| ars | `DESCRIPTION` | ✅ `LazyData: true` added |
| ars | `README.md` | ✅ Full rewrite of Quick Start using bundled data (C3 — commit f6b5e2d) |
| ars | `vignettes/getting-started.Rmd` | ✅ End-to-end pipeline walkthrough (C5 — commit 6dcc479) |

---

## 13. Test Coverage Plan

### arscore (Phase A)
- `ars_group(is_total = TRUE)` constructs and prints correctly
- `is_total` serialises to `"isTotal": true` in JSON
- JSON round-trip preserves `is_total` for both `TRUE` and `FALSE`
- Default `FALSE` — existing objects unaffected

### arsshells — hydrate() group tests (Phase A)
1. **Mode 2, 2-arm** — condition values injected; Total group unchanged
2. **Mode 2, reorder** — `order` field controls col_header sequence
3. **Mode 2, 3-arm** — new arm cloned; analyses created; IDs deterministic
4. **Mode 2, drop arm** — arm B removed cleanly from analyses and cells
5. **Mode 3, from data** — distinct values derived; groups built; `dataDriven`
   reset to `FALSE` after hydration
6. **Mixed mode** — `group_map` for TRT, `adam` for RACE, in same call
7. **Unused keys warned** — `variable_map` key that matches nothing → warning
8. **Mode 2 without group_map** — Mode 2 grouping present but no `group_map`
   supplied → error with clear message at `hydrate()` time
9. **Invalid inputs** — unknown grouping ID, missing `value` field → errors

### arsshells — hydrate() subset_map tests (Phase A)
1. **Simple override** — single condition value replaced; subset ID unchanged
2. **Compound override** — target sub-clause replaced; sibling clauses untouched
3. **Nested compound** — target variable in nested compound; recursive traversal
   finds and replaces it
4. **Unused subset ID** — key not in template → warning (not error)
5. **Missing variable** — variable not found in named subset → error with
   subset ID and variable name
6. **Multi-override** — two entries in `subset_map`; both applied independently

### arsshells — hydrate() metadata tests (Phase A)
1. **Title replace** — new title lines replace template; sub-section count matches
2. **Footnote replace** — new footnotes replace template footnotes
3. **Footnote append** — `footnote_append = TRUE` keeps existing, appends new
4. **Abbreviation replace** — abbreviation list replaced
5. **output_name** — `ars_output@name` updated
6. **display_title** — `ars_output_display@display_title` updated
7. **Partial metadata** — only `title` supplied; footnote and abbreviation
   sections passed through unchanged
8. **NULL metadata** — outputs subtree identical to original (no rebuild)
9. **Global sub_section_id** — inline sub-sections rebuilt; global
   `sub_section_id` references passed through unchanged

### arsshells — hydrate() section tests (Phase B)
1. **Mode 2, flat** — `section_map` expands T-LB-01 prototype to N sections
2. **Mode 3, flat** — `adam`-derived PARAMCD levels expand T-LB-01
3. **Mode 2, hierarchy** — SOC/PT nested structure in T-AE-02
4. **Fixed + template mix** — Age/Sex fixed; Race expands in T-DM-01
5. **Order control** — `order` field respected

### arsresult (Phase A) ✅ ALL TESTS WRITTEN AND PASSING
- ✅ Unhydrated non-Total conditionless group fires warning at `run()` time
- ✅ Conditionless Total (`is_total = TRUE`) does not fire warning
- ✅ Denominator resilience when ADSL lacks grouping variable (completes, no crash)
- ✅ Hard error surfaced for unresolvable `sub_clause_id` (not swallowed)
- ✅ Single-value `IN` condition transpiles to `c(value)` and filters correctly
- ✅ Single-value `NOTIN` condition filters correctly at data level
- ✅ Unnamed method return value triggers warning; result is NA (not silently dropped)
- ✅ Existing Total group fixture updated to use `is_total = TRUE`

### Verification — manual (Phase A)
- Audit snapshot test changes from JSON template updates. Changes are expected
  but must be reviewed to confirm structural integrity is preserved (no
  analyses dropped, no ID changes outside the arm condition removals).

### ars — Phase C acceptance criterion

```r
library(ars)

use_shell("T-DM-01") |>
  hydrate(
    group_map = list(
      GRP_TRT = list(
        list(id = "GRP_TRT_A", value = "Placebo",              order = 1L),
        list(id = "GRP_TRT_B", value = "Xanomeline Low Dose",  order = 2L),
        list(id = "GRP_TRT_C", value = "Xanomeline High Dose", order = 3L)
      )
    ),
    adam = list(ADSL = adsl),
    metadata = list(
      title    = c("Table 14.1.1 Summary of Demographic Characteristics",
                   "Safety Population"),
      footnote = c("Age and weight are summarised as mean (SD), median, and range.")
    )
  ) |>
  run(adam = list(ADSL = adsl)) |>
  render(backend = "tfrmt")
```

Must run without error or warning, producing a rendered gt table with three
arm columns (Placebo, Xanomeline Low Dose, Xanomeline High Dose), data-derived
RACE rows, and the custom title.

---

## 14. Backwards Compatibility

- `hydrate()` without new args → unchanged (Mode 1 shells unaffected)
- `is_total` defaults to `FALSE` → all existing `ars_group` objects unaffected
- `metadata = NULL` (default) → outputs subtree passed through; no rebuild
- `subset_map = NULL` (default) → data subsets passed through unchanged
- Template JSON changes are staged on a feature branch; main branch behaviour
  is unchanged until the branch is merged alongside updated README examples
- Removing top-level decorative arrays is non-breaking (`use_shell()` already
  ignores them)
- Phase B JSON refactors will invalidate snapshot tests — expected and
  intentional; all snapshot changes must be manually audited

---

## 15. Resolved Design Decisions

| Question | Decision |
|---|---|
| Display metadata option | **Option A confirmed** — inline `ars_display_sub_section` objects only; global `sub_section_id` references deferred |
| Total group in `group_map` | Always auto-preserved; cannot be removed via `group_map` |
| Multi-value arm conditions | `value = c("Dose A", "Dose B")` → `IN` comparator; supported in both `group_map` and `subset_map` |
| Mode 3 group ordering | Frequency-descending by default; alphabetical as tie-break; `order` override per item in `section_map` (Phase B) |
| `dataDriven` reset after hydration | Reset to `FALSE` — the hydrated shell must be a fully-specified, self-contained ARS object |
| `subset_map` traversal depth | **Fully recursive** — walks compound expressions to any depth; avoids a future breaking change |
| Decorative JSON arrays | Removed from all 6 templates in Step A2 |
| `hydrate_helpers.R` | `._hydrate_outputs()` and all Level 1–7 sub-functions extracted to a separate file for maintainability |
| Template staging | Feature branch; merged only when Phase C data or updated README examples are ready simultaneously |

---

## 16. Known Flaws Deferred (Not In Scope)

| Flaw | Package | Severity | Notes |
|------|---------|----------|-------|
| `OP_MEAN_SD` returns mean only, not composite string | arsresult stdlib | Medium | Downstream formatter compensates; separate PR |
| Case-sensitive method registry keys | arsresult | Low | Add normalisation helper separately |
| Compound expression empty sub-clause returns `TRUE` silently | arsresult | Low | Add explicit error in future |
| `sub_clause_id` resolution not implemented | arsresult | Medium | Rare use case; documented limitation |
| Duplicate IDs in reporting event silently overwrite | arscore | Low | Add dedup check in `validate_reporting_event()` |
| Numeric coercion in `.extract_values()` hides type errors | arsresult | Medium | Add `suppressWarnings = FALSE` mode |
| `metadata` targets all outputs in multi-output shells | arsshells | Low | Future: allow targeting by output ID |
| Section auto-ordering by frequency (Mode 3) | arsshells | Low | Alphabetical default for Phase B; frequency opt-in later |
| CDISCPILOT01 ADLB scope | ars | Low | Curated subset (HGB, ALT, CREAT minimum); full ADLB deferred |

---

## 17. Open Questions

1. **CDISCPILOT01 licence:** The data is publicly available under the CDISC
   licence for non-commercial use and is used by `admiral`, `tfrmt`, and
   `pharmaverseadam`. The `data-raw/cdiscpilot01.R` script will document
   provenance. **Confirm this is acceptable before Phase C begins.**

---

## 18. Summary

### Three-mode, three-dimensional configurability model

**The three modes**

| Mode | Template marker | User action |
|------|----------------|-------------|
| Fixed | `dataDriven: false` + full condition | None |
| Pre-specified | `dataDriven: false` + no condition | Supply via `group_map` / `subset_map` / `section_map` / `metadata` |
| Data-driven | `dataDriven: true` | Supply `adam` data to `hydrate()` |

**The three dimensions**

| Dimension | Mechanism | Controls |
|-----------|-----------|----------|
| **Columns** | `group_map` + `adam` | Treatment arms: values, count, order, labels |
| **Rows/Sections** | `section_map` + `adam` *(Phase B)* | Lab params, SOCs/PTs, demographic levels |
| **Display metadata** | `metadata` | Titles, footnotes, abbreviations, output name |

**Data-subset value flexibility**

| Mechanism | Controls |
|-----------|----------|
| `subset_map` | Override specific condition values inside named data subsets |

### Bug fixes bundled in Phase A ✅ ALL FIXED

| Bug | Severity | Status | Impact |
|-----|----------|--------|--------|
| Denominator `tryCatch` silent fallback | CRITICAL | ✅ Fixed (A8) | Now warns with analysis ID and error details |
| `groupId: null` in 3 shells | HIGH | ✅ Fixed (A2) | Templates updated; null groupIds resolved |
| `.make_c()` single-value `IN` | HIGH | ✅ Fixed (A9) | Always wraps in `c()` |
| Unhydrated arm group (no condition, not Total) | HIGH | ✅ Fixed (A10) | Warns at `run()` time |
| Unnamed method returns silently dropped | MEDIUM | ✅ Fixed (A11) | Warns and discards; result is NA |
| `validate_shell()` incomplete reference chain | MEDIUM | ⚠️ Needs verification | Part of A7 |
| Unused `hydrate()` map keys not reported | MEDIUM | ✅ Fixed (A7) | Warns for unused keys |
| Decorative JSON arrays never read | LOW | ✅ Fixed (A2) | Removed from all 6 templates |

### Separation of concerns after this work

| Layer | Responsibility |
|-------|---------------|
| **Templates** | Structural blueprint: shape, statistics, mode markers |
| **`hydrate()`** | Study-specific wiring: group values, subset overrides, section expansion, display metadata |
| **`run()`** | Execution against fully-specified shell; no discovery |
| **`ars::adsl/adae/adlb`** | Reference data for examples, vignettes, and tests |

---

## 19. ARS Explorer — App Architecture

`ars_explorer.R` is a self-contained Shiny module (`arsExplorerUI` / `arsExplorerServer`) that exposes the full pipeline interactively.

### 19.1 Execution pipeline

```
use_shell(id)
    ↓
hydrate(shell, variable_map, group_map, value_map, adam)   ← all user inputs
    ↓
ars::run(hydrated_shell, adam)                              ← returns ArsResult
    ↓
ard_result() reactiveVal                                    ← stores ArsResult
    ↓
render(ard_result(), backend = "tfrmt")                    ← gt table
```

`ars::run()` receives a `Shell` object, not a bare `ars_reporting_event`.  It dispatches using `S7::S7_inherits(re, arsshells::Shell)` — **not** `inherits()`, which is S3-only and returns `FALSE` for S7 objects.  On match, it extracts `shell@reporting_event`, calls `arsresult::run()`, and wraps the result in an `ArsResult` bundle `list(ard = ..., shell = ...)`.

### 19.2 Validation pipeline (Validate button)

Three independent layers; each layer's result is stored in `validate_result()`.

| Layer | What it checks | Tool |
|-------|----------------|------|
| **1 — Referential integrity** | All IDs in results resolve; no orphan operation_ids | `arscore::validate_reporting_event()` on re-embedded RE |
| **2 — CDISC JSON Schema** | Serialised JSON matches the official ARS v1.0 Draft-07 schema | `jsonvalidate::json_validate()` with AJV engine |
| **3 — JSON round-trip** | `to_json → from_json → validate` produces a valid RE | `arscore::reporting_event_to_json()` + `json_to_reporting_event()` |

Layer 1 is prerequisite for Layers 2 and 3; both are skipped if Layer 1 fails.

### 19.3 Re-embedding ARD into the reporting event (Layer 1)

`.embed_ard_into_re(re, ard)` writes ARD rows back into `re@analyses[*]@results` as `ars_operation_result` objects.

**Critical filter:** `arsresult::run()` appends *component scalar* rows to the ARD beyond the method's declared operations (see §19.4).  These extra rows must be stripped before embedding or `validate_reporting_event()` will reject them.  `.embed_ard_into_re()` pre-filters the ARD to formal operation IDs only:

```r
# For each analysis, keep only rows whose operation_id is declared in the method
formal_ops <- list()
for (an in re@analyses) {
  mt <- methods_by_id[[an@method_id]]
  if (!is.null(mt))
    formal_ops[[an@id]] <- vapply(mt@operations, \(op) op@id, character(1L))
}
ard <- ard[keep_rows_matching_formal_ops, ]
```

### 19.4 Component scalars in the ARD

`METH_CONT::OP_MEAN_SD` returns a named numeric vector with three elements: `OP_MEAN`, `OP_SD`, `OP_MEAN_SD`.  `METH_CONT::OP_RANGE` returns `OP_MIN`, `OP_MAX`, `OP_RANGE`.  The extra scalars (OP_MEAN, OP_SD, OP_MIN, OP_MAX) are appended to `analysis@results` — and therefore appear in the ARD — because `arstlf`'s `frmt_combine()` needs the individual values to build composite formatted cells.

**Two consumers, two views of the ARD:**

| Consumer | Needs component scalars? | Reason |
|----------|--------------------------|--------|
| `arstlf::render()` | **Yes** | `frmt_combine()` reads OP_MEAN and OP_SD separately to format "xx.x (xx.x)" |
| `.embed_ard_into_re()` | **No** | Validation requires operation_ids to match the method's declared operations |

The ARD is therefore not a simple 1-to-1 mirror of the method operations; it is a superset.  Any code that re-embeds results must filter to the formal operation list.

### 19.5 `strip_ars_extensions()` — what is stripped for Layer 2

The CDISC ARS JSON Schema uses `additionalProperties: false`.  arscore adds fields beyond the v1 model.  `.strip_ars_extensions()` removes or normalises them before schema validation:

| Extension | Location | Treatment |
|-----------|----------|-----------|
| `isTotal` | Every `group` in `analysisGroupings` | Field removed (`NULL`) |
| `groupId` | Every `orderedGrouping` in `analyses` | Field removed (`NULL`) |
| `IS_NULL` / `NOT_NULL` comparator | Any `condition` anywhere in the tree | Replaced with `EQ ""`  / `NE ""` (see §ISSUES_AND_GAPS) |

The normalisation is applied to the JSON **copy used for schema validation only**.  The actual `ArsResult` and all Layer 1/3 checks use the unmodified arscore objects.

### 19.6 ANSI colour codes in Shiny notifications

`cli` error and warning messages contain ANSI escape sequences (e.g. `\033[38;5;232m`).  Shiny renders these as raw text in `showNotification()` and `tags$pre()`.

All notification and card message sites in `ars_explorer.R` wrap `conditionMessage()` with `.strip_ansi()`:

```r
.strip_ansi <- function(x) cli::ansi_strip(x)
```

Applied to: `showNotification` (5 call sites) and `tags$pre` in the validation layer cards (2 sites).

---

## 20. Backlog (Post Phase A/B/C)

Items carried forward from per-package planning files. Not in scope for the
current rework but must not be lost. Grouped by package.

### arscore

| Item | Priority | Notes |
|------|----------|-------|
| Warn on unreferenced methods and unused groupings | Medium | `validate_reporting_event()` enhancement |
| Validate `ordered_groupings` reference valid reporting event groupings | Medium | Currently unchecked |
| Integration test: realistic multi-analysis RE round-trip (build → validate → JSON → reimport → equality) | Medium | End-to-end confidence |
| Property-based / fuzzing tests for validators | Low | Long-term robustness |
| Coverage measurement with `covr` | Low | Identify untested paths |
| `format()` improvements for `ars_method`, `ars_output`, `ars_analysis` | Low | Show operation IDs / display names inline; pattern set by `ars_document_reference` |
| Package logo | Low | Cosmetic |
| Emit `@type: "ReportingEvent"` from `reporting_event_to_json()` | Low | CSD root object carries `@type` as metadata. Confirmed **not** a source of Layer 2 schema failures: `@type` does not appear anywhere in the CDISC JSON Schema, and the root schema sets `additionalProperties: true` so the field is harmless either way. Add for completeness / CSD alignment only. |

### arsshells — template library expansion

> **T-AE-02 is now on the CSD pattern — use it as the reference for new AE templates.**
>
> T-AE-02 uses two analyses (`AN_SOC_TEAE`, `AN_PT_TEAE`) with `resultsByGroup: true`
> across `GRP_TRT × GRP_SOC` and `GRP_TRT × GRP_SOC × GRP_PT` respectively.
> `GRP_SOC` and `GRP_PT` are `dataDriven: true`; their groups are resolved from
> `adae_teae` at `hydrate()` time (Mode 3 section expansion).  A single `DS_TEAE`
> data subset (`TRTEMFL=Y`) is the only record-level filter.  The `groupId` arm-pin
> extension is not used.
>
> End-to-end result (CDISCPILOT01): 230 PT groups, 1334 ARD rows, 276 table rows, 0 warnings.

**Priority 2 — next batch (6 templates):**

| ID | Name | Dataset |
|----|------|---------|
| T-VS-01 | Summary of Vital Signs | ADVS |
| T-AE-03 | Adverse Events by Severity (CTCAE Grade) | ADAE |
| T-AE-04 | Adverse Events by Relationship to Study Drug | ADAE |
| T-AE-05 | Serious Adverse Events | ADAE |
| T-EF-01 | Primary Efficacy Endpoint Summary | ADEFF |
| T-EX-01 | Summary of Study Drug Exposure | ADEX |

**Priority 3 — remaining tables, figures, listings (43 templates):**

See `arsshells/REFERENCE.md` for the full 55-shell inventory.

### arsresult

| Item | Priority | Notes |
|------|----------|-------|
| Additional stdlib methods: geometric mean, Kaplan–Meier, Cox HR | Medium | Needed for T-EF-04, survival tables |
| Arrow / DuckDB integration tests | Medium | Backend-agnostic transpiler needs backend tests |
| `IS_NULL` / `NOT_NULL` comparator support | Low | Rare in CDISC standards; log as known limitation until needed |
| ~~**Support `resultsByGroup: false` / no-`groupId` result pattern for comparison analyses**~~ | ~~Medium~~ | ✅ **COMPLETE — 2026-02-28 (OI-07)**. `ars_result_group` validator relaxed; `.resolve_grouping_filter()` returns groupingId-only result_group; `comparison_vars` attr set on data; METH_CHISQ, METH_ANOVA, METH_FISHER in stdlib. **Rendering** comparison rows in a dedicated p-value column is deferred to the arstlf `gt` backend / T-EF-01 sprint. |
| **`dataSubsetId` runtime filtering in `arsresult::run()`** | Medium | CSD attaches a named `dataSubset` to each analysis as a record-level pre-filter (e.g. `Dss01_TEAE`: `TRTEMFL=Y`); `run()` must apply this filter before executing the method. Note: T-AE-02 already sets `dataSubsetId` on every analysis, but its subsets bake in hardcoded SOC/PT terms as a workaround for missing data-driven grouping support — so `dataSubsetId` filtering may currently be silently ignored and T-AE-02 still passes tests via the `groupId` arm-pin.  Verify whether `run()` applies the filter at all before implementing. Once `dataSubsetId` filtering works, T-AE-02 can be migrated to the CSD pattern (single `TRTEMFL=Y` subset + data-driven groupings). |
| ~~**`referencedOperationRelationships` — formal denominator declaration for percentage operations**~~ | ~~Medium~~ | ✅ **COMPLETE — 2026-02-28 (OI-06).** NUMERATOR + DENOMINATOR RORs declared on `OP_N_PCT` in all four methods (METH_CAT, METH_AE_FREQ ×2, METH_FREQ). `AN_HDR_N` denominator analysis added to each template; all analyses with `OP_N_PCT` wired with `referencedAnalysisOperations`. The denominator is still computed from `analysis_set_n` inside stdlib — driving computation from the declared relationship is a future enhancement. |

### arstlf

| Item | Priority | Notes |
|------|----------|-------|
| `gt` backend (direct assembly without tfrmt) | High | Simpler path for sponsors not using tfrmt |
| `rtables` backend | Medium | Roche framework; common in oncology sponsors |
| `ggplot2` backend for F-* figure templates | Medium | Required before any figure template can render |
| RTF / PDF export quality testing | Medium | tfrmt backend produces HTML reliably; RTF/PDF needs audit |

### ars

| Item | Priority | Notes |
|------|----------|-------|
| Optional Shiny app (`R/ars_app.R`) | Low | Interactive shell selection, hydration, mock preview |
| Enable pkgdown GitHub Pages deployment when repos go public | Low | Uncomment deploy step; use org-scoped PAT |

### Cross-cutting

| Item | Priority | Notes |
|------|----------|-------|
| `AGENTS.md` / memory files — keep in sync with MASTER_PLAN.md §0 | Ongoing | Run `/memory` update after any §0 change |
| arscore vignette: "JSON Round-Trip and Validation" | Low | Currently missing; `complete-reporting-event` vignette exists |

---

## 21. Refactor: Split Composite Operations into Separate Declared Operations

### Background

The CSD reference file (`Common Safety Displays.json`) defines Min and Max as two
independent, first-class operations on `Mth02_ContVar_Summ_ByGrp`:

```json
{ "id": "Mth02_ContVar_Summ_ByGrp_7_Min", "name": "Minimum", "order": 7, "resultPattern": "XX" },
{ "id": "Mth02_ContVar_Summ_ByGrp_8_Max", "name": "Maximum", "order": 8, "resultPattern": "XX" }
```

Each has its own result row in every analysis that uses the method.

### Current arsshells / arsresult approach (problem)

`METH_CONT` currently models range as a **composite operation** `OP_RANGE` whose
R function returns a named vector with three elements: `OP_MIN`, `OP_MAX`, and
`OP_RANGE`.  `arsresult::run()` appends all three as result rows — but the method
only *declares* `OP_RANGE`.  The undeclared scalar rows (`OP_MIN`, `OP_MAX`) are
spurious from the ARS model's perspective and cause cascading issues:

| Affected area | Problem |
|---|---|
| `validate_reporting_event()` | Rejects result rows whose `operation_id` is not in the method |
| `.embed_ard_into_re()` | Requires a pre-filter to strip undeclared rows before Layer 1 validation |
| CDISC JSON Schema (Layer 2) | Same undeclared IDs cause schema failures if not stripped |
| `frmt_combine()` in arstlf | Relies on the scalar rows being *present* in the ARD — contradicts the filter |

The same pattern exists for `OP_MEAN_SD` (emits `OP_MEAN`, `OP_SD`, `OP_MEAN_SD`).

### Target design (aligned with CSD)

Declare every scalar that the method produces as a **formal operation**.  Remove
composite operations entirely.

#### `METH_CONT` — proposed operation list

| ID | Label | Pattern |
|----|-------|---------|
| `OP_N` | n | `xx` |
| `OP_MEAN` | Mean | `xx.x` |
| `OP_SD` | SD | `(xx.xx)` |
| `OP_MEDIAN` | Median | `xx.x` |
| `OP_Q1` | Q1 | `xx.x` |
| `OP_Q3` | Q3 | `xx.x` |
| `OP_MIN` | Min | `xx` |
| `OP_MAX` | Max | `xx` |

`OP_MEAN_SD` and `OP_RANGE` are **removed**.  `arstlf`'s `frmt_combine()` calls
are updated to compose `OP_MEAN + OP_SD` and `OP_MIN + OP_MAX` at render time
rather than expecting pre-composed operation IDs.

### Affected files

| Package | File | Change |
|---------|------|--------|
| `arsresult` | `R/stdlib.R` (METH_CONT handler) | Return individual scalars only; remove composite vectors |
| `arsshells` | `inst/templates/tables/T-DM-01.json` | Replace `OP_MEAN_SD` / `OP_RANGE` with flat operation list |
| `arsshells` | `inst/templates/tables/T-VS-01.json` (and any new templates) | Define flat from the start |
| `arsshells` | `R/hydrate.R` shell cell linking | Update any cell → operation links that reference composite IDs |
| `arstlf` | `R/render.R` / tfrmt spec builder | Replace `frmt_combine()` references to `OP_MEAN_SD` / `OP_RANGE` with two-scalar compose |
| `ars_explorer.R` | `.embed_ard_into_re()` | Pre-filter becomes unnecessary once all operations are declared; can be simplified or removed |
| Tests | All packages | Update expected operation IDs and ARD shapes |

### Migration notes

- `.embed_ard_into_re()` pre-filter logic can be **removed** after this refactor
  because there will be no undeclared operation IDs to strip.
- The `arsresult` warning for unresolved data-driven groupings is unrelated and
  should be retained.
- Shell cell references in JSON templates that currently point to `OP_MEAN_SD`
  or `OP_RANGE` must be updated to the new scalar IDs; the `validate_shell()`
  step will catch any that are missed.
- Any existing integration tests that assert on ARD column counts or operation
  ID sets will need updating — run the full test suite across all packages after
  the change.

---

## 22. User Acceptance Testing (UAT)

**Added:** 2026-02-28  
**Priority:** High (Priority 1 in NEXT SESSION table)

Three interlocking concerns identified during output review:

1. **Missing-category display inconsistency** — the literal string `"NA"` appears in
   some rendered cells instead of a blank.
2. **Forced small-dataset scoping** — `adlb_lb01` (7 PARAMCDs) and `adlb_lb02`
   (3 PARAMCDs) exist as performance workarounds; the underlying run loop should be
   fast enough for full ADLB (47 PARAMCDs).
3. **End-to-end output correctness** — structured review of all 6 shells against
   clinical expectations.

---

### §22.1 — Diagnose and fix blank vs "NA" rendering inconsistency

#### Root cause candidates

| Source | Mechanism | Symptom |
|--------|-----------|---------|
| `stdlib.R` scalar fns on empty data | `mean(numeric(0), na.rm=TRUE)` → `NaN` stored as `"NaN"` in raw_value | `"NaN"` or `"NA"` in cell |
| `prep_ard.R` zero-row filter | `return(NULL)` → row absent from tfrmt input | Correct blank ✓ |
| tfrmt `frmt("xx.x")` on numeric `NA` | tfrmt renders blank | Correct blank ✓ |
| `raw_value = "NA"` string in non-combined format | tfrmt may emit literal `"NA"` if frmt doesn't absorb it | **Likely culprit** |

#### Steps

1. Run `data_table_examples.R` end-to-end; capture all 6 gt tables; flag any cell
   containing `"NA"`, `"NaN"`, or unexpected blank.
2. For each flagged cell, filter the ARD to the originating `raw_value` to determine
   whether `"NA"` is arriving as character string vs. numeric `NA_real_`.
3. Audit stdlib edge cases: `OP_SD` (n=1 → `NA` ✓), `OP_MEAN`/`OP_MEDIAN`/`OP_MIN`/
   `OP_MAX` (n=0 → `NA_real_` ✓). Verify `NaN` cannot reach `raw_value`.
4. Audit `prep_ard.R` value path: confirm `as.numeric("NA")` / `as.numeric("NaN")`
   → `NA_real_` propagates cleanly to tfrmt with no literal text leaking.
5. **Fix:** Add `NaN → NA_real_` guard in `stdlib.R` or `run.R` before `raw_value`
   is written. Add regression tests in `arstlf/tests/` for n=0 and n=1 cells.

#### Deliverables

- [x] Root cause identified: `mean()`/`sd()` on empty vectors return `NaN`; min/max/median guarded with explicit `NA_real_`. `NaN` is absorbed by tfrmt's `missing = ""` handler since `is.na(NaN) == TRUE`.
- [x] Guard added: `.fn_min`, `.fn_max`, `.fn_median` use `non_na` guard returning `NA_real_` on empty data. `NaN` from `mean`/`sd` renders blank via tfrmt.
- [x] All 6 rendered tables free of `"NA"` / `"NaN"` text — confirmed 0 warnings, 0 -Inf/Inf values in ARD (2026-02-28).
- [x] Missing-statistics behaviour documented: when a data-subset filter yields 0 rows, `OP_COUNT` returns `0` (not NA); all other continuous statistics (`OP_MEAN`, `OP_SD`, `OP_MIN`, `OP_MAX`, `OP_MEDIAN`) return explicit `NA_real_`. `prep_ard.R` converts the character string `"NA"` via `suppressWarnings(as.numeric("NA"))` = `NA_real_`; `tfrmt::frmt("xx.x")` renders `NA_real_` as an empty string (default `missing = ""`).

  ```r
  # stdlib.R  (.fn_max, .fn_min, .fn_median, .fn_sd)
  non_na <- vals[!is.na(vals)]
  c(OP_MAX = if (length(non_na) > 0) max(non_na) else NA_real_)
  ```

---

### §22.2 — Full-dataset performance: remove forced scoping

#### Current state

| Dataset | PARAMCDs | Analyses | Time | Speedup |
|---------|----------|----------|------|---------|
| Full ADLB | 47 | 1504–1692 | 2–3.5 min | baseline |
| `adlb_lb01` | 7 | 224 | 5.3 s | 28× |
| `adlb_lb02` | 3 | 108 | 1.8 s | 117× |

The `.observed_combos()` fast path exists (added in the observed-combos sprint) but
the full 47-PARAMCD ADLB still hits 2–3.5 min, suggesting either the fast path is not
firing, or the loop body itself is the bottleneck.

#### Investigation

Profile T-LB-01 on full `adlb`:

```r
Rprof(tmp <- tempfile())
run(sh_lb01, adam = list(ADLB = adlb, ADSL = adsl))
Rprof(NULL); summaryRprof(tmp)
```

Hypotheses (in order of likelihood):

| Hypothesis | Mitigation |
|------------|------------|
| `.observed_combos()` not firing — Cartesian fallback due to orphan PARAMCDs or non-EQ conditions | Audit fast-path conditions; remove orphans or fix template |
| Fast path fires but loop body slow (1500+ analyses × 6 ops) | Vectorise filter-and-count; consider `data.table` or `dtplyr` |
| ADSL denominator re-filtered per analysis (1500 redundant calls) | Memoize: compute denom once per unique `(analysis_set_id, group_combo)` |

#### Target

Full 47-PARAMCD ADLB completes T-LB-01 in **< 30 seconds** (currently 2–3.5 min).

#### Deliverables

- [x] Root cause fixed: PIN-path pre-filter cache added to `arsresult/R/run.R` — analysis-set + pin-group filter computed once per unique `(ds_name, as_id, pin_group_ids)` key rather than once per analysis.
- [x] T-LB-01 benchmark on full ADLB (83,652-row × 47 PARAMCDs = 1,504 analyses): ~112 s → ~6.5 s. Well under 30 s target. 7-param installed shell (224 analyses, same 83k ADLB): ~6.5 s → ~1.5 s.

  | Version | Analyses | Time |
  |---------|----------|------|
  | Before cache (full ADLB, 47 PARAMCDs) | 1,504 | ~112 s |
  | After cache (full ADLB, 47 PARAMCDs)  | 1,504 | ~6.5 s |
  | After cache (7-param subset)           | 224   | ~1.5 s |

- [x] `data_table_examples.R` scoped subsets (`adlb_lb01`, `adlb_lb02`) retained as semantic clarity; full ADLB runs within target time.
- [x] Fast-path tests added to arsresult (Tests 6, 7, 8 in `test-run.R`).

---

### §22.3 — End-to-end UAT review (all 6 shells)

#### Review checklist (per shell)

| Check | Pass criteria |
|-------|---------------|
| Row count | Matches hand-counted expectation from clinical spec |
| Column N headers | Show actual N values, not `"N=xx"` placeholder |
| All expected categories present | Shell sections fully reflected in rendered rows |
| No `"NA"` / `"NaN"` text in cells | String scan of gt object |
| Zero-count cells show `"0"` not blank (where appropriate) | Frequency rows for arms with no events |
| Percentages suppressed when N=0 (shows `"0"` not `"0 (0.0%)"`) | AE and disposition tables |
| Totals / subtotals arithmetically consistent | Spot check |
| Section headers / indentation correct | Visual review |

#### Shell-specific focus

| Shell | Key UAT focus |
|-------|---------------|
| T-DM-01 | SD undefined for n=1 subjects → should be blank not `"NA"` |
| T-DS-01 | All disposition categories present even at 0 count |
| T-AE-01 | Value-map override (AEREL/AEACN) produces expected counts |
| T-AE-02 | All SOCs represented; zero-event SOC/PT rows show `"0"` |
| T-LB-01 | Baseline vs. CHG rows clearly distinguished; NaN guards active |
| T-LB-02 | Shift categories (Low/Normal/High) complete across all arms |

#### Results (2026-02-28)

| Shell | ARD Rows | Table Rows | Warnings | Notes |
|-------|----------|------------|----------|-------|
| T-DM-01 | 72 | 16 | 0 | |
| T-DS-01 | 72 | 13 | 0 | |
| T-AE-01 | 56 | 9 | 0 | |
| T-AE-02 | 1334 | 276 | 0 | pivot_wider warning resolved; 69→276 rows |
| T-LB-01 | 1344 | 84 | 0 | NA min/max fix verified; 0 -Inf/Inf in ARD |
| T-LB-02 | 216 | 45 | 0 | |

- [x] UAT checklist completed for all 6 shells — 0 defects found.
- [x] No `"NA"` / `"NaN"` / `-Inf` text in any rendered cell.

---

### §22.4 — Execution order

1. ✅ MASTER_PLAN.md updated (this section + priority table) — 2026-02-28
2. ✅ §22.3 — All 6 shells run; UAT checklist complete — 2026-02-28
3. ✅ §22.1 — NA/NaN rendering confirmed clean; stdlib guards in place — 2026-02-28
4. ✅ §22.2 — PIN-path cache implemented; full ADLB ~6.5 s — 2026-02-28
5. ✅ All packages green: arscore 1335, arsshells 552, arsresult 272, arstlf 112, ars 95 (0 failures)
