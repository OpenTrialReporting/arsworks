# arsworks — Known Issues and Gaps

**Maintained by:** Lovemore Gakava  
**Last updated:** 2026-02-28  
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

### 2.1 Component scalar rows in the ARD exceed the method's declared operations  `[BUG-FIXED]`

**Resolved by §21 flat operations refactor (2026-02-28).**

`OP_MEAN_SD` and `OP_RANGE` composite operations have been removed from `METH_CONT`.
Every scalar that the method produces (`OP_MEAN`, `OP_SD`, `OP_MIN`, `OP_MAX`, `OP_COUNT`,
`OP_MEDIAN`) is now a formally declared operation. The ARD contains only declared
operation IDs; `validate_reporting_event()` accepts the embedded results without filtering.

The `.embed_ard_into_re()` pre-filter in `ars_explorer.R` has been removed; the comment
confirms "No pre-filter is needed". `arstlf` composes display cells at render time via
`frmt_combine()` keyed on the flat anchor ops (`OP_MEAN` → "mean (SD)", `OP_MIN` →
"min, max") using the `.combined_ops` registry in `prep_ard.R`.

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

**Cause:** Component scalar rows (§2.1) present in ARD were embedded into the reporting
event before filtering. Seen when `.embed_ard_into_re()` did not filter to formal operations.

**Status:** Fully resolved by §21 flat ops refactor (2026-02-28). All METH_CONT scalars
are now formally declared operations; no undeclared rows are ever produced. The pre-filter
in `.embed_ard_into_re()` has been removed entirely — it is no longer needed.
This entry is retained as a diagnostic guide.

---

## 5. Open Issues (No Workaround Yet)

| ID | Package | Description | Severity |
|----|---------|-------------|----------|
| ~~OI-01~~ | ~~arstlf~~ | ~~`OP_MEAN_SD` formatted value is the mean only~~ | ~~Medium~~ | **RESOLVED** — `OP_MEAN_SD` removed by §21 refactor; `frmt_combine(OP_MEAN, OP_SD)` renders "xx.x (xx.x)" correctly. |
| ~~OI-02~~ | ~~arsresult~~ | ~~Numeric coercion in `.extract_values()` silently converts string comparator values to numeric. Type errors are suppressed.~~ | ~~Medium~~ | **RESOLVED** — `GT`/`GE`/`LT`/`LE` now pass `numeric_required = TRUE` to `.extract_values()`; a non-numeric value raises `cli_abort`. String fall-back is still silent for `EQ`/`NE`/`IN`/`NOTIN`. |
| ~~OI-03~~ | ~~arscore~~ | ~~Duplicate IDs in a reporting event silently overwrite earlier entries in lookups.~~ | ~~Low~~ | **RESOLVED** — `validate_reporting_event()` now checks all 7 top-level collections (analyses, methods, analysis_sets, data_subsets, analysis_groupings, outputs, reference_documents), operation IDs within each method, and group IDs within each grouping factor. Duplicates are collected with all other referential integrity errors and reported together. |
| ~~OI-04~~ | ~~arsshells~~ | ~~`validate_shell()` does not call `validate_reporting_event()` internally~~ | ~~Medium~~ | **RESOLVED** — `validate_shell()` now checks the full reference chain: `analysis_set_id`, `data_subset_id`, `ordered_groupings` (grouping_id + group_id), and all `ShellCell` refs. |
| OI-05 | arstlf | RTF/PDF export quality from the tfrmt backend is untested. HTML is reliable; RTF needs audit before production use. | Medium |
| ~~OI-06~~ | ~~arsresult / arsshells~~ | ~~`referencedOperationRelationships` not declared on percentage operations — denominator linkage invisible to the ARS model.~~ | ~~Medium~~ | **RESOLVED** — Declared in all 4 templates; `AN_HDR_N` denominator analysis added to each. See below. |
| OI-07 | arsresult / arscore | `resultsByGroup: false` pattern not supported — blocks all CSD comparison methods (Chi-sq, ANOVA, Fisher exact). See below. | Medium |
| ~~OI-08~~ | ~~arsresult~~ | ~~`dataSubsetId` filtering in `run()` unverified — may be silently ignored for some analysis patterns.~~ | ~~Medium~~ | **RESOLVED** — Implemented and tested in both paths. See below. |

---

## 6. Open Issues — Detail

### ~~OI-06~~ — `referencedOperationRelationships` not declared on `%` operations  `[BUG-FIXED]`

**Resolved 2026-02-28.**

All four affected templates updated. arscore model was already complete; this was purely template JSON work.

**Affected packages:** `arsresult`, `arsshells`

**Description:**  
The CSD method `Mth01_CatVar_Summ_ByGrp` formally declares the numerator/denominator
relationship for its percentage operation via `referencedOperationRelationships`:

```json
{
  "referencedOperationRelationships": [
    {
      "referencedOperationRole": "NUMERATOR",
      "operationId": "Mth01_CatVar_Summ_ByGrp_2_n",
      "analysisId": null
    },
    {
      "referencedOperationRole": "DENOMINATOR",
      "operationId": "Mth01_CatVar_Count_ByGrp_1_n",
      "analysisId": "AN_HDR_TRT"
    }
  ]
}
```

`METH_AE_FREQ` (and any other method that computes a percentage) currently
hard-codes the denominator inside the R stdlib function. The relationship is
invisible to the ARS model: no `referencedOperationRelationships` are declared
in the method, and the templates do not carry these fields on the `%` / `pct`
operation cells.

**Impact:**  
- Strict ARS consumers (e.g., CDISC validators checking referential integrity on
  operation relationships) will find no declared linkage and cannot verify
  percentage correctness from the JSON alone.
- JSON will not fully round-trip against conformant ARS viewers that display
  denominator provenance.

**CSD structure (verified against `Common Safety Displays.json` line 1594):**  

Two separate declarations are required:

*On the method's operation* (shared template for all analyses using the method):
```json
{
  "id": "OP_N_PCT",
  "referencedOperationRelationships": [
    { "id": "ROR_NPCT_NUM", "referencedOperationRole": { "controlledTerm": "NUMERATOR" },
      "operationId": "OP_N" },
    { "id": "ROR_NPCT_DEN", "referencedOperationRole": { "controlledTerm": "DENOMINATOR" },
      "operationId": "OP_N" }
  ]
}
```
Both point to `OP_N`; the difference is resolved per-analysis via `referencedAnalysisOperations`.

*On each analysis* (resolves abstract ROR IDs to concrete analysis IDs):
```json
"referencedAnalysisOperations": [
  { "referencedOperationRelationshipId": "ROR_NPCT_NUM", "analysisId": "<this analysis>" },
  { "referencedOperationRelationshipId": "ROR_NPCT_DEN", "analysisId": "AN_HDR_N" }
]
```

**Current state across installed templates:**

| Template | Method | NUMERATOR ROR | DENOMINATOR ROR | `referencedAnalysisOperations` |
|---|---|:---:|:---:|:---:|
| T-AE-02 | METH_AE_FREQ | ✅ `ROR_NPCT_NUMERATOR` | ❌ | ❌ |
| T-AE-01 | METH_AE_FREQ | ❌ | ❌ | ❌ |
| T-DM-01 | METH_CAT | ❌ | ❌ | ❌ |
| T-DS-01 | METH_FREQ | ❌ | ❌ | ❌ |

**arscore model:** Fully supports this — `ars_referenced_operation_relationship`,
`ars_referenced_analysis_operation`, and the Layer 1 validator (`validate_reporting_event()`)
are all in place. This is **template JSON work only** — no code changes needed.

**Needed changes (three per template):**  
1. **Method block** — add NUMERATOR + DENOMINATOR RORs to `OP_N_PCT` in each
   method (`METH_AE_FREQ`, `METH_CAT`, `METH_FREQ`).
2. **New header-count analysis** (`AN_HDR_N`) — each template needs an explicit
   analysis that computes `OP_N` per arm in the analysis set. This is the CSD
   denominator analysis (c.f. `An01_05_SAF_Summ_ByTrt` in CSD). Currently the
   column N is computed as an internal side-channel (`analysis_set_n`) in
   `run()`. Adding it as a first-class analysis makes it visible in the ARD.  
   ⚠️ Once added, check `arstlf` N=xx header resolution does not double-count.
3. **Per-analysis wiring** — every analysis with `OP_N_PCT` gets
   `referencedAnalysisOperations`: NUMERATOR → self, DENOMINATOR → `AN_HDR_N`.

**Effort by template:**

| Template | Analyses with OP_N_PCT | Changes needed |
|---|:---:|---|
| T-AE-01 | 7 | Add RORs to method + `AN_HDR_N` + wire 7 analyses |
| T-AE-02 | 2 | Add DENOMINATOR ROR + `AN_HDR_N` + wire 2 analyses |
| T-DM-01 | 2 | Add RORs to method + `AN_HDR_N` + wire 2 analyses |
| T-DS-01 | 8 | Add RORs to method + `AN_HDR_N` + wire 8 analyses |

**Tracking:** `MASTER_PLAN.md §20` (arsresult backlog).

---

### OI-07 — `resultsByGroup: false` pattern not supported  `[DEFERRED]`

**Affected packages:** `arsresult`, `arscore`

**Description:**  
CSD defines three comparison methods that use `resultsByGroup: false` on all
groupings and emit a **single** result whose `resultGroups` carry only a
`groupingId` (no `groupId`):

| CSD Method ID | Description |
|---|---|
| `Mth03_CatVar_Comp_PChiSq` | Pearson Chi-square p-value |
| `Mth04_ContVar_Comp_Anova` | One-way ANOVA p-value |
| `Mth05_CatVar_Comp_FishEx` | Fisher exact test p-value |

Current blockers:  
- `arsresult::run()` always writes a `groupId` on every result row; the
  no-`groupId` result pattern is not handled.  
- `ars_operation_result` (arscore S7 class) requires `groupId` to be non-empty
  in each `resultGroup`; it must be made optional (`default = ""`).  
- `stdlib.R` has no comparison methods; Chi-square, ANOVA, and Fisher exact
  functions need to be added.  
- `arstlf` render path assumes each result row maps to an arm column;
  a single-row comparison result (p-value) needs a separate tfrmt / gt
  geometry.

**Impact:**  
No p-value or inferential comparison analyses can be produced until this is
resolved. All CSD tables that include a p-value column (T-DM-01, T-AE-03,
efficacy tables) are structurally incomplete.

**Tracking:** `MASTER_PLAN.md §20` (arsresult backlog).

---

### ~~OI-08~~ — `dataSubsetId` filtering in `arsresult::run()`  `[BUG-FIXED]`

**Resolved by code inspection and test verification — 2026-02-28.**

Both execution paths in `arsresult/R/run.R` apply `data_subset_id` filtering
correctly:

- **PIN path** (`run.R` lines 441–451): `analysis@data_subset_id` is looked up
  in `ds_index`, transpiled via `.filter_data_subset()`, and applied to `data`
  before `_call_method_once` is called. If the subset ID is not found, a
  `cli_warn()` is emitted and the analysis is skipped (not silently ignored).

- **Expand path** (`run.R` lines 504–514): Same lookup and filter applied to
  `base_data` before the combo loop. An additional early-return guard fires if
  the filtered `base_data` has zero rows (line 518).

**Test coverage:**

- `test-run.R:420` — "dataSubsetId filter is applied: zero-row subset yields
  count of 0": PIN path; `DS_SEX_X` (`SEX == "X"`) matches no subject;
  asserts `OP_N == 0`, not the full safety-pop count of 8.

- `test-run.R:1463, 1519, 1695, 1878, 2025` — Expand-path tests (T-AE-02
  pattern) use `data_subset_id = "DS_TEAE"` with a `TRTEMFL = "Y"` filter;
  result row counts confirm only TEAE rows are counted.

The concern in the original OI-08 entry was moot: the filter was never
incidental to the `groupId` arm-pin path. It is a formal, explicit step in
both branches.
