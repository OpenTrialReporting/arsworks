# arsworks — Known Issues and Gaps

**Maintained by:** Lovemore Gakava  
**Last updated:** 2026-02-26  
**Scope:** Issues confirmed against the live codebase; workarounds in place unless marked otherwise.

Each entry is tagged:

- `[CDISC-GAP]` — gap in the CDISC ARS v1.0 specification itself; cannot be fixed in arscore without diverging from the standard
- `[BUG-FIXED]` — confirmed bug, fix already merged
- `[DEFERRED]` — known issue, not yet fixed, tracked for a future release
- `[DESIGN]` — intentional design constraint with documented rationale

---

## 1. CDISC Spec Gaps

### 1.1 `IS_NULL` / `NOT_NULL` comparators not in the CDISC v1 schema  `[CDISC-GAP]`

**Symptom:** Layer 2 (CDISC JSON Schema) validation fails with:
```
/dataSubsets/N/condition/comparator: must be equal to one of the allowed values
```

**Cause:** The CDISC ARS v1.0 `ConditionComparatorEnum` only includes:
`EQ`, `NE`, `GT`, `GE`, `LT`, `LE`, `IN`, `NOTIN`.

arscore adds `IS_NULL` and `NOT_NULL` as extensions to support null-value checks in analysis set and data subset conditions (e.g., "exclude subjects with missing baseline"). These are semantically necessary but not part of the v1 spec.

**Workaround in `ars_explorer.R`:** `.strip_ars_extensions()` replaces `IS_NULL` with `EQ ""` and `NOT_NULL` with `NE ""` in the JSON copy used for schema validation. The actual arscore objects and Layers 1/3 are unaffected.

**Affected shells:** Any shell with a data subset or analysis set condition that uses `IS_NULL` or `NOT_NULL`. Currently observed in T-LB-01 and T-LB-02.

**Recommended action:** Raise with the CDISC ARS working group. The v2 spec should accommodate null checks explicitly. Until then, the schema validation normalisation stands.

---

### 1.2 `mainListOfContents` required by schema but optional in arscore  `[CDISC-GAP]`

**Symptom:** Layer 2 may fail with a `mainListOfContents` missing error if the reporting event is serialised without one.

**Cause:** The CDISC JSON Schema (Draft-07) marks `mainListOfContents` as required at the root of every `ReportingEvent`. arscore treats it as optional (consistent with the human-readable spec text, which says "should").

**Workaround in `ars_explorer.R`:** `.auto_main_loc(re)` generates a flat `ListOfContents` enumerating all analyses before schema validation and before the "Full ARS with results" export.

---

### 1.3 `isTotal` and `groupId` extensions not in the CDISC v1 schema  `[DESIGN]`

**Cause:** arscore adds two fields beyond the v1 model:
- `isTotal` on `ars_group` — distinguishes Total groups (conditionless by design) from unhydrated arm groups (missing condition by mistake). Used by `arsresult::run()` to suppress false warnings.
- `groupId` on `ars_ordered_grouping_factor` — pre-resolves the active group for the one-analysis-per-group pattern. Enables correct grouping filter application without analysis ID parsing.

The CDISC schema uses `additionalProperties: false`, so these fields cause Layer 2 failures.

**Workaround in `ars_explorer.R`:** `.strip_ars_extensions()` removes both fields from the JSON copy before schema validation.

**Recommended action:** Propose `isTotal` and `groupId` as additions to the v2 spec. Both fill genuine gaps in the v1 model.

---

## 2. arsresult Design Constraints

### 2.1 Component scalar rows in the ARD exceed the method's declared operations  `[DESIGN]`

**Context:** `METH_CONT::OP_MEAN_SD` is registered as a single operation but its implementation returns three named values: `OP_MEAN`, `OP_SD`, `OP_MEAN_SD`. Similarly, `OP_RANGE` returns `OP_MIN`, `OP_MAX`, `OP_RANGE`. `arsresult::run()` appends the extra "component scalars" (OP_MEAN, OP_SD, OP_MIN, OP_MAX) to `analysis@results` and to the ARD.

**Why:** `arstlf`'s `frmt_combine()` reads OP_MEAN and OP_SD as separate values to assemble the composite formatted cell "xx.x (xx.x)". Without them in the ARD, rendering fails.

**Consequence:** The ARD contains operation_ids that are not declared operations in the method. Any code that re-embeds ARD rows into `analysis@results` for validation will fail `validate_reporting_event()` unless it filters to formal operation IDs first.

**Workaround in `ars_explorer.R`:** `.embed_ard_into_re()` pre-filters the ARD to formal operation IDs (those declared in `re@methods`) before building `ars_operation_result` objects.

**Longer-term options:**
- Tag component scalar rows in the ARD with a column (e.g., `is_component = TRUE`) so consumers can filter reliably without re-deriving the method's operation list.
- Or register OP_MEAN, OP_SD, OP_MIN, OP_MAX as explicit sub-operations in the method definition, which would then be valid operation_ids in the results. This is a larger API change.

---

### 2.2 `sub_clause_id` in `ars_where_clause` is not resolved  `[DEFERRED]`

`ars_where_clause` supports `sub_clause_id` — a reference to another where clause by ID. The transpiler does not resolve these references; it throws an error when encountered. No shell template currently uses `sub_clause_id`.

**Impact:** Low. Feature is present in the CDISC model but not used in any installed template.

**Tracking:** MASTER_PLAN.md §16.

---

### 2.3 Denominator falls back to unfiltered data on filter error  `[DESIGN]`

When the denominator calculation (ADSL-based N for `OP_N_PCT`) fails — e.g., ADSL lacks the grouping variable — `run()` warns and falls back to the full analysis-set size. This preserves pipeline continuity but can produce incorrect percentages.

**Mitigation:** A `cli_warn()` is always emitted naming the analysis and the error. The denominator value should be treated as suspect when this warning appears.

---

## 3. ars Package Issues (Fixed)

### 3.1 `ars::run()` Shell detection used `inherits()` instead of `S7::S7_inherits()`  `[BUG-FIXED]`

**Symptom:** Clicking "Get ARD" in ARS Explorer produced:
```
ARD error: `re` must be an <arscore::ars_reporting_event>
```

**Cause:** `ars/R/run.R` dispatched on Shell objects using:
```r
if (inherits(re, "arsshells::Shell")) { ... }
```
`inherits()` is S3-based and returns `FALSE` for S7 objects, so every Shell fell through to `arsresult::run()`, which correctly rejected it.

**Fix:** Changed to `S7::S7_inherits(re, arsshells::Shell)`.

**Lesson:** `inherits()` must not be used for class checks on S7 objects. Use `S7::S7_inherits(obj, ClassName)` — where `ClassName` is the actual S7 class object, not a string.

---

### 3.2 ANSI escape codes displayed as raw text in Shiny notifications  `[BUG-FIXED]`

**Symptom:** Error and warning notifications in ARS Explorer showed raw ANSI escape sequences:
```
ARD error: [38;5;232m`re` must be an [34m<arscore::ars_reporting_event>
```

**Cause:** `cli` formats all messages with ANSI colour sequences. `conditionMessage()` returns those sequences as-is. Shiny's `showNotification()` and `tags$pre()` render them as literal characters.

**Fix:** Added `.strip_ansi <- function(x) cli::ansi_strip(x)` and applied it at all 7 notification/card message sites in `ars_explorer.R`.

---

## 4. ARS Explorer Validation Notes

### 4.1 Layer 2 failures that are expected and handled

The following Layer 2 schema failures are expected when using arscore objects and are handled by `.strip_ars_extensions()` before validation:

| Failure pattern | Cause | Handled |
|---|---|---|
| `comparator: must be equal to one of the allowed values` | `IS_NULL` or `NOT_NULL` comparator | ✅ Normalised to `EQ ""`/`NE ""` |
| `Additional property 'isTotal' is not allowed` | arscore extension on `ars_group` | ✅ Stripped |
| `Additional property 'groupId' is not allowed` | arscore extension on `ars_ordered_grouping_factor` | ✅ Stripped |
| `mainListOfContents` missing | arscore treats it as optional | ✅ Auto-generated |

Any Layer 2 failure **not** in the above list represents a genuine structural problem with the serialised reporting event.

### 4.2 Layer 1 failure: unknown operation_ids in results

**Symptom:**
```
Analysis 'AN_XXX': result operation_id 'OP_MEAN' not found in any method's operations
```

**Cause:** Component scalar rows (§2.1) present in ARD were embedded into the reporting event before filtering. Seen when `.embed_ard_into_re()` did not filter to formal operations.

**Status:** Fixed. `.embed_ard_into_re()` now pre-filters. This entry is retained as a diagnostic guide.

---

## 5. Open Issues (No Workaround Yet)

| ID | Package | Description | Severity |
|----|---------|-------------|----------|
| OI-01 | arstlf | `OP_MEAN_SD` formatted value is the mean only, not "mean (SD)" composite string. Downstream formatting relies on component scalars + `frmt_combine()`. | Medium |
| OI-02 | arsresult | Numeric coercion in `.extract_values()` silently converts string comparator values (e.g., `"3"`) to numeric. Type errors are suppressed. | Medium |
| OI-03 | arscore | Duplicate IDs in a reporting event silently overwrite earlier entries in lookups. `validate_reporting_event()` does not check for ID uniqueness. | Low |
| OI-04 | arsshells | `validate_shell()` does not call `validate_reporting_event()` internally; the full referential integrity chain is not checked at shell load time. | Medium |
| OI-05 | arstlf | RTF/PDF export quality from the tfrmt backend is untested. HTML is reliable; RTF needs audit before production use. | Medium |
