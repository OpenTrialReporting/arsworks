# Plan: Configurable Shells — Data-Driven Groups and Sections
**Date:** 2026-02-22  
**Author:** Lovemore Gakava  
**Status:** DRAFT — Awaiting approval  
**Scope:** arscore, arsshells, arsresult, arstlf, ars (tests + docs in each)

> **Ordering constraint:** Example data (Phase C) cannot be added before
> Phase A is complete. The CDISCPILOT01 data has treatment values
> `"Placebo"`, `"Xanomeline Low Dose"`, `"Xanomeline High Dose"` — none of
> which match the current hardcoded template values. The README examples will
> serve as the **acceptance criterion for Phase A**: if they run end-to-end
> against the bundled data without errors, Phase A is done.

---

## 1. Problem Statement

All 6 installed shell templates have two classes of hardcoding problem:

**Column dimension** — Treatment arm filter values (`TRT01A == "Treatment A"`)
are baked into the template JSON. Every study has different treatment labels.
The current `hydrate()` can remap variable *names* and display *labels* but
never touches condition *values*. A study whose `TRT01A` values are `"Placebo"`
and `"Xanomeline High Dose"` will produce **empty groups** at execution time
with no error or warning.

**Row/section dimension** — Templates like T-LB-01 hardcode which lab
parameters appear (7 PARAMCDs, 168 analyses). A real study has 40+. T-AE-02
hardcodes SOCs and PTs that are entirely data-driven. T-DM-01 hardcodes
race levels that vary by study and region. These cannot be exhaustive.

Additionally, several shells (T-AE-01, T-DS-01, T-LB-01) have `groupId: null`
in analysis `orderedGroupings` — a silent execution bug where analyses carry
a grouping reference but no group identity and are never filtered.

An examination of the real ADSL data (CDISC Pilot) further reveals:
- 3 treatment arms, not 2 (`Placebo`, `Xanomeline Low Dose`, `Xanomeline High Dose`)
- `RACE` values are uppercase (`WHITE`, `BLACK OR AFRICAN AMERICAN`) — the
  template has mixed case
- `AMERICAN INDIAN OR ALASKA NATIVE` is present in the data but missing from
  the template entirely

---

## 2. The Three-Mode Model

Examining the variables across all shells, there are exactly **three distinct
modes** for any grouping or section dimension. These must not be conflated:

| Mode | Definition | Examples | Who supplies the value |
|------|-----------|----------|------------------------|
| **1 — Fixed** | Value standardised by CDISC or ADaM convention. Known at template design time. | `SAFFL == "Y"`, `SEX == "M"/"F"`, `TRTEMFL == "Y"` | Template JSON (hardcoded — correct) |
| **2 — Pre-specified** | Value is study-specific but known before data arrives — defined in protocol or SAP. | `TRT01A` levels, `AGEGR1` levels, ordered dose groups | User supplies via `hydrate()` |
| **3 — Data-driven** | Value only known once data exists. Cannot be pre-specified. | `RACE` levels, `AEBODSYS`/`AEDECOD`, `ETHNIC`, `PARAMCD` | Derived from data inside `hydrate()` |

**Key insight:** Requiring values upfront (Mode 2 behaviour) for Mode 3
variables defeats the purpose. The user cannot know `RACE` levels without data.
Equally, making treatment arms fully data-driven (Mode 3) loses the pre-specified
table structure needed for SAP review.

The previous plan version conflated Modes 2 and 3 by making `section_auto`
an afterthought. This revision makes all three modes first-class.

---

## 3. Design Principles

1. **Templates are structural specifications, not execution scripts.**  
   Templates declare shape (how many arms, what statistics, what order) but
   contain no study-specific data values.

2. **Mode is declared in the template, not discovered at runtime.**  
   The template JSON marks each grouping/section dimension with its mode.
   `hydrate()` reads the mode marker and behaves accordingly.

3. **`hydrate()` is the single point of study-specific wiring.**  
   After `hydrate()` runs, the shell is fully specified — every group has a
   condition, every section has a label, every analysis ID is deterministic.
   `run()` sees no difference between pre-specified and data-driven shells.

4. **`dataDriven: true` maps cleanly onto Mode 3.**  
   The ARS spec's `dataDriven` flag is semantically correct for Mode 3
   groupings. Mode 2 groupings use `dataDriven: false` with placeholder
   groups (no condition values).

5. **`run()` remains simple.**  
   Data-driven resolution happens inside `hydrate()`, not inside `run()`.
   This keeps `run()` stateless with respect to the data it hasn't seen yet.

6. **Backwards compatibility.**  
   Mode 1 templates (fully fixed) continue to work without any `hydrate()`
   call. All existing `hydrate()` calls without new arguments continue to work.

---

## 4. Proposed `hydrate()` Interface

```r
hydrate(
  shell,

  # Existing — Mode 1 corrections (variable name remapping, label cosmetics)
  variable_map = c(TRT01A = "TRTP"),
  label_map    = c("Treatment A (N=xx)" = "Placebo (N=xx)"),

  # New — Mode 2: user supplies pre-specified values explicitly
  group_map = list(
    GRP_TRT = list(
      list(id = "GRP_TRT_A", value = "Placebo",             order = 1L),
      list(id = "GRP_TRT_B", value = "Xanomeline Low Dose", order = 2L),
      list(id = "GRP_TRT_C", value = "Xanomeline High Dose",order = 3L)
    )
  ),
  section_map = list(
    PARAMCD = list(
      list(value = "HGB",   label = "Haemoglobin (g/dL)"),
      list(value = "ALT",   label = "Alanine Aminotransferase (U/L)")
    )
  ),

  # New — Mode 3: data supplied; values derived automatically
  adam = list(ADSL = adsl, ADAE = adae)
)
```

**Rules:**
- `group_map` / `section_map` → Mode 2 for the named groupings/sections
- `adam` supplied → Mode 3 for any grouping/section with `dataDriven: true`
  in the template; `hydrate()` queries `distinct()` values internally
- A single call can mix modes: `group_map` for treatment arms (Mode 2) and
  `adam` for race levels (Mode 3)
- If a Mode 3 grouping exists in the template but neither `adam` nor
  `section_map` is supplied, `hydrate()` errors with a clear message

---

## 5. Template JSON Changes

### 5.1 Mode 2 groupings — remove condition values, keep structure

Strip `condition` from arm-specific groups. Keep group IDs, labels, order.
The `dataDriven: false` flag remains (structure is pre-declared; values come
from `group_map`).

```json
// Before
{
  "id": "GRP_TRT_A", "label": "Treatment A (N=xx)", "order": 1,
  "condition": { "variable": "TRT01A", "comparator": "EQ", "value": ["Treatment A"] }
}

// After
{ "id": "GRP_TRT_A", "label": "Treatment A (N=xx)", "order": 1 }
```

The Total group (`GRP_TRT_TOT`) has no condition today and remains unchanged.
Add `"isTotal": true` to mark it explicitly (see §6).

### 5.2 Mode 3 groupings — use `dataDriven: true`, no groups list

For variables like `RACE`, `PARAMCD`, `AEBODSYS`:

```json
{
  "id": "GRP_RACE",
  "name": "Race Group",
  "dataDriven": true,
  "groupingVariable": "RACE"
}
```

No `groups` array. `hydrate()` reads `distinct(adam$ADSL, RACE)` and builds
the groups list dynamically, injecting it into the reporting event.

### 5.3 Template sections — add `templateKey`

Sections that repeat over a data-driven dimension are marked with `templateKey`:

```json
{
  "id": "SEC_PARAM_BL_TEMPLATE",
  "label": "{{PARAM_LABEL}} — Baseline",
  "templateKey": "PARAMCD",
  "cells": [
    { "rowLabel": "Count (n)", "colLabel": "Treatment A (N=xx)",
      "analysisId": "AN_PARAM_BL_A_OP_COUNT" },
    ...
  ]
}
```

- `templateKey` identifies the expansion variable
- `{{PARAM_LABEL}}` is replaced with `label` from `section_map` or from data
- `PARAM` in analysis IDs is a placeholder token replaced with a sanitised
  form of the value (e.g. `HGB`, `ALT`)
- Sections without `templateKey` are fixed and passed through unchanged

### 5.4 Fix `groupId: null` analyses

T-AE-01, T-DS-01, T-LB-01 have analyses referencing `GRP_TRT` with
`groupId: null`. Fix by inferring `groupId` from the analysis ID suffix:
- `_TRT_A` → `GRP_TRT_A`
- `_TRT_B` → `GRP_TRT_B`
- `_TOT` → `GRP_TRT_TOT`

---

## 6. `arscore` Changes — `is_total` on `ars_group`

Add a non-breaking optional boolean property to `ars_group`:

```r
is_total = new_property(class_logical, default = FALSE)
```

Serialised as `"isTotal"` in JSON. Default `FALSE`; existing objects
unaffected.

**Purpose:** Allows `arsresult::run()` to distinguish "Total = conditionless
by design" from "arm group = missing condition because hydrate() was not
called". Without this marker, both look identical (conditionless group,
`dataDriven: false`).

---

## 7. `hydrate()` Internal Logic

### Phase 1 — Variable and label substitution (existing, unchanged)

### Phase 2 — Group expansion (`group_map`, Mode 2)

For each grouping factor ID in `group_map`:
1. Look up the `ars_grouping_factor` in the reporting event.
2. For each entry in the user list:
   - **Update** existing group: inject condition value (`EQ` for scalar,
     `IN` for vector), update order.
   - **Create** new group: build `ars_group` with condition from the grouping
     factor's `groupingVariable`.
3. **Remove** template groups absent from `group_map` (excluding Total).
4. Rebuild `ars_grouping_factor` with resolved group list.
5. Clone/drop `ars_analysis` objects: find analyses by grouping factor
   reference, group by base ID (strip arm suffix), clone for new arms,
   drop for removed arms.
6. Rebuild `colHeaders` and `ShellCell` col_labels to match.

**ID conventions:**
- New group ID: user-supplied `id` field (explicit, not derived)
- New analysis ID: `<baseId>_<last segment of group id>` (e.g. `AN_AGE_C`)

### Phase 3 — Data-driven group resolution (`adam`, Mode 3)

For each `ars_grouping_factor` in the reporting event with `dataDriven: true`:
1. Identify the source dataset from `groupingDataset` (or infer from analyses
   referencing this grouping factor).
2. Query `distinct(adam[[dataset]], groupingVariable)` — filtered by the
   analysis set condition if one exists.
3. For each distinct value, build an `ars_group` with:
   - `id`: sanitised from value (e.g. `GRP_RACE_WHITE`)
   - `label`: the raw value as label (user can override via `label_map`)
   - `order`: frequency-descending by default, alphabetical as fallback
   - `condition`: `variable == value`
   - `is_total`: FALSE
4. Set `dataDriven: false` on the rebuilt grouping factor — after hydration,
   the shell is fully specified and must not attempt runtime discovery.
5. Clone analyses and ShellCells as per Phase 2.

### Phase 4 — Section expansion (`section_map` or `adam`, Modes 2+3)

For each `ShellSection` with `templateKey`:
1. If `section_map` supplied for this key → use those items (Mode 2).
2. If `adam` supplied and no `section_map` for this key → query
   `distinct()` from data for the `templateKey` variable (Mode 3).
3. For each item: clone section, replace `{{PARAM_LABEL}}` token,
   replace `PARAM` token in analysis IDs, clone/update data subsets
   with the item's condition value.
4. Remove the template prototype section from the shell.

### Reporting

After all phases, `hydrate()` emits a structured summary:
- How many groups were resolved per grouping factor (and by which mode)
- How many sections were expanded
- Which `variable_map` / `label_map` keys were unused (warning)
- Which Mode 3 groupings derived their values from data (informational)

---

## 8. `arsresult` — Bug Fixes and Safety

### 8.1 Unhydrated arm group warning

In `.resolve_grouping_filter()`: if a group has `dataDriven = FALSE`,
`is_total = FALSE`, and no condition — warn the user. This is the "forgot
to call hydrate()" safety net.

### 8.2 `analysis_set_n` denominator bug (CRITICAL)

**Current flaw:** For non-ADSL datasets (ADAE, ADLB), the denominator is
computed by filtering ADSL by the grouping condition. But the code does NOT
intersect with `unique(data$USUBJID)` from the event dataset. If a subject
appears in the ADSL arm but has no events, they are counted in the
denominator but not in the cell — this is correct for safety frequencies.
However, the current implementation can produce wrong denominators when
ADSL grouping filters fail silently (the `tryCatch` swallows filter errors
and falls back to unfiltered ADSL).

**Fix:** Remove the silent `tryCatch` fallback in denominator calculation.
Replace with an explicit check: if ADSL grouping filter fails, error loudly.
Log the denominator calculation step so it can be audited.

### 8.3 Silent filter failure in denominator (CRITICAL)

The `tryCatch` blocks in denominator calculation silently return unfiltered
ADSL on any error. This means a missing variable in ADSL produces a
denominator that is too large, with no warning.

**Fix:** Replace silent fallback with explicit warnings at minimum;
errors for structural failures (missing variable).

### 8.4 `.make_c()` single-value `IN` bug (HIGH)

In `transpile.R`, `.make_c()` optimises single-value lists to bare scalars:
```r
if (length(vals) == 1L) return(vals[[1L]])  # returns bare value, not c(value)
```
For `IN` comparator with one value, this produces `x %in% value` which
evaluates to `x %in% <bare string>` — correct by accident in R, but
semantically wrong and fragile. Should return `c(vals[[1L]])` explicitly.

### 8.5 Unnamed function return values silently dropped

In `run()`, if a registered method function returns an unnamed vector, no
results are captured (the `for (nm in names(vals))` loop is a no-op on
unnamed vectors). This is a silent data loss.

**Fix:** Add validation that method functions return a named numeric vector.
Warn if unnamed values are returned.

---

## 9. `arsshells` — Validation Gaps

### 9.1 `validate_shell()` incomplete reference chain

`validate_shell()` checks that `analysisId` and `operationId` in ShellCells
resolve to valid analyses and operations. But it does **not** check:
- `analysis@analysis_set_id` exists in `@analysis_sets`
- `analysis@data_subset_id` exists in `@data_subsets`
- `analysis@ordered_groupings[*]@grouping_id` exists in `@analysis_groupings`
- `analysis@ordered_groupings[*]@group_id` exists in the grouping's `@groups`

These are cross-package referential integrity checks that belong in
`validate_reporting_event()` in arscore, but `validate_shell()` should
call it or perform equivalent checks.

### 9.2 Unused map keys not reported

`hydrate()` currently gives no feedback on which `variable_map` or
`label_map` keys were not found in the template. A user who typos a variable
name gets no indication their substitution did nothing.

**Fix:** After Phase 1, compare used keys against supplied map. Warn for
any keys that matched nothing.

### 9.3 `validate_shell()` crashes on empty `@analyses`

If `re@analyses` is empty, `vapply(re@analyses, ...)` in `validate_shell()`
crashes rather than reporting a clean error.

**Fix:** Guard with `if (length(re@analyses) == 0L)` before index building.

### 9.4 `use_shell()` case-sensitive ID matching

`use_shell("t-dm-01")` fails to find `T-DM-01.json`. IDs should be
normalised (trimmed, uppercased) before file matching.

---

## 10. Implementation Order

Bottom-up dependency chain. Phase A (group expansion) ships and is tested
before Phase B (section expansion) begins.

### Phase A — Group (column) expansion + critical bug fixes

```
Step A1: arscore    — add is_total to ars_group; JSON round-trip
Step A2: arsshells  — update 6 JSON templates:
                       remove arm condition values; add isTotal;
                       fix null groupId; mark dataDriven groupings
Step A3: arsshells  — implement group_map (Mode 2) in hydrate()
Step A4: arsshells  — implement Mode 3 group resolution (adam arg)
Step A5: arsshells  — report unused map keys; validate_shell() gaps
Step A6: arsresult  — fix analysis_set_n denominator tryCatch
Step A7: arsresult  — fix .make_c() single-value IN bug
Step A8: arsresult  — add unhydrated arm warning
Step A9: All        — tests and docs for Phase A
```

### Phase B — Section (row) expansion

```
Step B1: arsshells  — add template_key to ShellSection class
Step B2: arsshells  — refactor T-LB-01/02 JSONs to template sections
Step B3: arsshells  — refactor T-AE-02 JSON to template sections
Step B4: arsshells  — refactor T-DM-01 Race section to template section
Step B5: arsshells  — implement section_map (Mode 2) in hydrate()
Step B6: arsshells  — implement Mode 3 section resolution (adam arg)
Step B7: All        — tests and docs for Phase B
```

### Phase C — Example data and complete README
**Prerequisite: Phase A must be complete.**

```
Step C1: ars  — add CDISCPILOT01 datasets as bundled package data
Step C2: ars  — document datasets with roxygen2
Step C3: ars  — update README with complete, runnable examples
Step C4: ars  — add DESCRIPTION Suggests entry for data sourcing
```

---

## 11. File Change Inventory

### Phase A

| Package | File | Change |
|---------|------|--------|
| arscore | `R/ars_group.R` | Add `is_total` property (default `FALSE`) |
| arscore | `R/ars_json.R` | Serialise/deserialise `isTotal` ↔ `is_total` |
| arscore | `tests/testthat/test-ars_group.R` | Tests for new property |
| arsshells | `inst/templates/tables/T-DM-01.json` | Remove arm conditions; add `isTotal`; mark RACE as `dataDriven: true` |
| arsshells | `inst/templates/tables/T-AE-01.json` | Remove arm conditions; add `isTotal`; fix null groupIds |
| arsshells | `inst/templates/tables/T-AE-02.json` | Remove arm conditions; add `isTotal` |
| arsshells | `inst/templates/tables/T-DS-01.json` | Remove arm conditions; add `isTotal`; fix null groupIds |
| arsshells | `inst/templates/tables/T-LB-01.json` | Remove arm conditions; add `isTotal`; fix null groupIds |
| arsshells | `inst/templates/tables/T-LB-02.json` | Remove arm conditions; add `isTotal` |
| arsshells | `R/hydrate.R` | Add `group_map`, `adam` args; Phase 2+3 logic; unused key reporting |
| arsshells | `R/validate_shell.R` | Complete reference chain validation; empty-analyses guard; ID normalisation in `use_shell()` |
| arsshells | `tests/testthat/test-hydrate.R` | Tests for group_map (Mode 2) and adam (Mode 3) |
| arsresult | `R/run.R` | Fix denominator tryCatch; add unhydrated arm warning |
| arsresult | `R/transpile.R` | Fix `.make_c()` single-value IN bug |
| arsresult | `tests/testthat/test-run.R` | Test denominator correctness; warning tests |
| arsresult | `tests/testthat/test-transpile.R` | Test single-value IN fix |
| ars | `README.md` | Update workflow example |

### Phase B

| Package | File | Change |
|---------|------|--------|
| arsshells | `R/shell_classes.R` | Add `template_key` to `ShellSection` |
| arsshells | `inst/templates/tables/T-LB-01.json` | Refactor to 2 prototype sections + prototype analyses |
| arsshells | `inst/templates/tables/T-LB-02.json` | Refactor to 3 prototype sections |
| arsshells | `inst/templates/tables/T-AE-02.json` | Refactor to 1 prototype SOC section |
| arsshells | `inst/templates/tables/T-DM-01.json` | Race section → template section |
| arsshells | `R/hydrate.R` | Add `section_map` (Phase 4 logic) |
| arsshells | `R/validate_shell.R` | Validate template section prototype structure |
| arsshells | `tests/testthat/test-hydrate.R` | Tests for section_map and Mode 3 section expansion |
| ars | `README.md` | Update with section_map examples |

### Phase C — Example data *(requires Phase A)*

| Package | File | Change |
|---------|------|--------|
| ars | `data-raw/cdiscpilot01.R` | Script to prepare CDISCPILOT01 datasets from source |
| ars | `data/adsl.rda` | Bundled ADSL (254 rows, CDISCPILOT01) |
| ars | `data/adae.rda` | Bundled ADAE (1,191 rows, CDISCPILOT01) |
| ars | `data/adlb.rda` | Bundled ADLB (minimal subset for lab shells) |
| ars | `R/data.R` | Roxygen2 documentation for all three datasets |
| ars | `DESCRIPTION` | Add `LazyData: true`; note data source and licence |
| ars | `README.md` | Full rewrite of Quick Start using `ars::adsl`, `ars::adae` |
| ars | `vignettes/getting-started.Rmd` | New vignette: end-to-end pipeline with bundled data |

---

## 12. Test Coverage Plan

### arscore (Phase A)
- `ars_group` with `is_total = TRUE` constructs, serialises, round-trips

### arsshells — hydrate() group tests (Phase A)
1. **Mode 2, 2-arm** — condition values injected; Total unchanged
2. **Mode 2, reorder** — `order` controls col_header sequence
3. **Mode 2, 3-arm** — new arm cloned; analyses created; IDs deterministic
4. **Mode 2, drop arm** — arm B removed cleanly from analyses and cells
5. **Mode 3, from data** — distinct values derived; groups built; dataDriven
   reset to false after hydration
6. **Mixed mode** — group_map for TRT, adam for RACE, in same call
7. **Unused keys warned** — variable_map key that matches nothing triggers warning
8. **group_map omitted** — Mode 2 grouping without group_map → error on hydrate
9. **Invalid inputs** — missing value, unknown grouping_id → clear errors

### arsshells — hydrate() section tests (Phase B)
1. **Mode 2, flat** — section_map expands T-LB-01 prototype to N sections
2. **Mode 3, flat** — adam-derived PARAMCD levels expand T-LB-01
3. **Mode 2, hierarchy** — SOC/PT nested structure in T-AE-02
4. **Fixed + template mix** — Age/Sex fixed; Race expands in T-DM-01
5. **Order control** — order field respected

### arsresult (Phase A)
- Unhydrated conditionless non-Total group fires warning
- Conditionless Total (`is_total = TRUE`) does not fire warning
- Denominator uses correct filtered ADSL (not silently falling back)
- Single-value `IN` condition transpiles and filters correctly
- Unnamed method return value triggers warning, not silent drop

### ars — example data (Phase C)
- `ars::adsl`, `ars::adae`, `ars::adlb` load correctly after `library(ars)`
- Dataset dimensions match source (adsl: 254 × 48, adae: 1,191 × 55)
- **Acceptance criterion:** The following pipeline runs end-to-end without
  error or warning, producing a rendered gt table:

```r
library(ars)

use_shell("T-DM-01") |>
  hydrate(
    group_map = list(
      GRP_TRT = list(
        list(id = "GRP_TRT_A", value = "Placebo",             order = 1L),
        list(id = "GRP_TRT_B", value = "Xanomeline Low Dose", order = 2L),
        list(id = "GRP_TRT_C", value = "Xanomeline High Dose",order = 3L)
      )
    ),
    adam = list(ADSL = adsl)
  ) |>
  run(adam = list(ADSL = adsl)) |>
  render(backend = "tfrmt")
```

---

## 13. Backwards Compatibility

- `hydrate()` without new args works unchanged (Mode 1 shells unaffected)
- `is_total` defaults to `FALSE`; all existing `ars_group` objects unaffected
- Template JSON changes (Phase A) mean un-hydrated Mode 2 shells warn at
  `run()` but do not crash
- Phase B JSON refactors (lab, AE shells) will break snapshot tests against
  raw JSON — expected and intentional; test counts will change significantly
- The 1,812 existing tests should pass after Phase A; snapshot updates needed
  for Phase B

---

## 14. Known Flaws Deferred (Not In Scope)

These were identified during review but are lower priority and do not block
the configurability work:

| Flaw | Package | Severity | Notes |
|------|---------|----------|-------|
| `run()` returns ARD only — shell lost in pipe, breaking `render()` | ars/arsresult | Medium | `render()` requires both `ard` and `shell`; the natural 4-step pipe fails with "argument shell is missing". Fix: have `run()` return an S7 result object carrying both ARD and shell, with `render()` dispatching on it. Workaround: assign hydrated shell to a variable and pass explicitly. `ars_pipeline()` unaffected. |
| `OP_MEAN_SD` returns mean, not composite | arsresult stdlib | Medium | Downstream formatter compensates; fix in separate PR |
| Case-sensitive method registry keys | arsresult | Low | Convention enforcement; add normalisation helper |
| Compound expression empty sub-clause returns `TRUE` silently | arsresult | Low | Acceptable for now; add explicit error in future |
| `sub_clause_id` resolution not implemented | arsresult | Medium | Rare use case; log as known limitation |
| Duplicate IDs in reporting event silently overwrite | arsresult | Low | Add dedup check in `validate_reporting_event()` |
| `hydrate()` shares `sections`/`col_headers` references | arsshells | Low | S7 immutability protects this; document the assumption |
| Numeric coercion in `.extract_values()` hides type errors | arsresult | Medium | Add `suppressWarnings = FALSE` mode |

---

## 15. Open Questions

1. **Total group in `group_map`:** Always auto-appended (proposed) or
   user-controllable? Auto-append keeps the Total convention consistent.

2. **Multi-value arm conditions:** `value = c("Dose A", "Dose B")` in
   `group_map` → `IN` comparator. Confirm this is needed before implementing.

3. **Mode 3 ordering:** Default ordering for data-derived groups — frequency
   descending, or alphabetical? Proposed: frequency descending, with
   `order` override available per item in `section_map`.

4. **`dataDriven` reset after hydration:** After Mode 3 resolution,
   `dataDriven` is set to `FALSE` on the rebuilt grouping factor. This means
   the hydrated shell is fully specified and serialisable as a normal
   ARS reporting event. Is this the right behaviour, or should the flag
   remain `TRUE` as a provenance marker?
   **Proposed:** Reset to `FALSE` — the output of `hydrate()` should be a
   fully-specified, self-contained ARS object.

5. **Section auto-ordering by frequency:** For Mode 3 section expansion
   (e.g. AEBODSYS), ordering by frequency is clinically sensible. Should
   this be the default, or should alphabetical be the default with frequency
   as an opt-in?

6. **CDISCPILOT01 data source and licence:** The CDISC Pilot Study data is
   widely used in R clinical packages (admiral, tfrmt, pharmaverseadam).
   The data is publicly available from CDISC and is distributed under the
   CDISC licence for non-commercial use. The `data-raw/cdiscpilot01.R`
   script will document the provenance. Confirm this is acceptable before
   Phase C begins.

7. **ADLB scope for bundled data:** ADLB for CDISCPILOT01 is large
   (~10,000 rows). Proposed: bundle a curated subset — the lab parameters
   used in the T-LB-01/02 prototype shells (HGB, ALT, CREAT at minimum) —
   to keep the package size reasonable.

---

## 16. Summary

This plan introduces a **three-mode, two-dimensional configurability** model:

### The three modes

| Mode | Template marker | User action |
|------|----------------|-------------|
| Fixed | `dataDriven: false` + full condition | None |
| Pre-specified | `dataDriven: false` + no condition | Supply via `group_map` / `section_map` |
| Data-driven | `dataDriven: true` | Supply `adam` data to `hydrate()` |

### The two dimensions

| Dimension | Mechanism | Controls |
|-----------|-----------|----------|
| **Columns** | `group_map` + `adam` | Treatment arms: values, count, order, labels |
| **Rows/Sections** | `section_map` + `adam` | Lab params, SOCs/PTs, demographic levels |

### Additional bug fixes bundled in Phase A

| Bug | Impact |
|-----|--------|
| Denominator `tryCatch` silent fallback | Wrong percentages with no warning |
| `groupId: null` in 3 shells | Analyses never filtered to their arm |
| `.make_c()` single-value `IN` | Transpiler produces fragile expressions |
| Unnamed method returns silently dropped | Silent data loss |
| `validate_shell()` incomplete reference chain | Invalid shells pass validation |
| Unused `hydrate()` map keys not reported | Silent no-op substitutions |

### Phase C: example data and complete README

| Deliverable | Detail |
|-------------|--------|
| `ars::adsl` | CDISCPILOT01 ADSL, 254 × 48 |
| `ars::adae` | CDISCPILOT01 ADAE, 1,191 × 55 |
| `ars::adlb` | CDISCPILOT01 ADLB, curated subset |
| `data-raw/cdiscpilot01.R` | Provenance and preparation script |
| Updated README | Self-contained Quick Start, runnable after `library(ars)` |
| Getting-started vignette | Full pipeline walkthrough with bundled data |

**Phase C acceptance criterion:** `use_shell("T-DM-01") |> hydrate(...) |> run(adam = list(ADSL = adsl)) |> render()` runs without error against `ars::adsl`.

The separation of concerns after this work:
- **Templates** → structural blueprint (shape, statistics, mode markers)
- **`hydrate()`** → study-specific wiring (values from SAP or from data)
- **`run()`** → execution against real data (fully-specified shell, no discovery)
- **`ars::adsl/adae/adlb`** → reference data for examples, vignettes, and tests
