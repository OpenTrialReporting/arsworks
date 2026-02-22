# Test Data Generation for arsworks (Current Templates)

This script generates minimal synthetic ADaM datasets that are compatible
with the **current** shell templates (v0.1.0), where treatment values are
hardcoded as `"Treatment A"` and `"Treatment B"`.

> **Note:** These datasets will become obsolete once Phase A of
> `PLAN_DATA_DRIVEN_GROUPS.md` is complete. At that point the templates will
> be study-agnostic and the bundled CDISCPILOT01 data (`ars::adsl`, etc.)
> will replace them. This file is kept for backwards compatibility only.

Run this script in R to create `adsl`, `adae`, and `adlb` in your session:

---

## Required values per shell

| Shell | Dataset | Key hardcoded values |
|-------|---------|----------------------|
| T-DM-01 | ADSL | `TRT01A`: `"Treatment A"`, `"Treatment B"` · `SAFFL == "Y"` · `SEX`: `"M"`, `"F"` · `RACE`: `"White"`, `"Black or African American"`, `"Other"` |
| T-DS-01 | ADSL | `TRT01A`: same · `RANDFL == "Y"` · `COMPLFL == "Y"` · `DCSREAS`: `"Adverse Event"`, `"Withdrawal by Subject"`, `"Physician Decision"`, `"Lost to Follow-up"`, `"Other"` |
| T-AE-01 | ADAE + ADSL | `TRT01A`: same · `TRTEMFL == "Y"` · `AEREL`: `"PROBABLE"`, `"POSSIBLE"`, `"RELATED"` · `AESER == "Y"` · `AETOXGR >= "3"` · `AEACN == "DRUG WITHDRAWN"` · `AEOUT == "FATAL"` |
| T-AE-02 | ADAE + ADSL | `TRT01A`: same · `TRTEMFL == "Y"` · `AEBODSYS`: `"Cardiac disorders"`, `"Gastrointestinal disorders"`, `"Nervous system disorders"` · `AEDECOD`: `"Palpitations"`, `"Tachycardia"`, `"Nausea"`, `"Vomiting"`, `"Diarrhoea"`, `"Headache"`, `"Dizziness"`, `"Fatigue"` |
| T-LB-01 | ADLB + ADSL | `TRT01A`: same · `PARAMCD`: `"HGB"`, `"PLT"`, `"WBC"`, `"ALT"`, `"AST"`, `"CREAT"`, `"GLUC"` · `ANL01FL == "Y"` · `ABLFL == "Y"` (baseline) or `!= "Y"` (change) |
| T-LB-02 | ADLB + ADSL | `TRT01A`: same · `PARAMCD`: `"HGB"`, `"ALT"`, `"CREAT"` · `ANL01FL == "Y"` · `BNRIND`: `"Low"`, `"Normal"`, `"High"` · `WGRNRIND`: `"Low"`, `"Normal"`, `"High"` |

---

## R Code

```r
# ── ADSL ──────────────────────────────────────────────────────────────────────
# 60 subjects: 20 Treatment A (safety), 20 Treatment B (safety), 20 not in SAF
# All 40 SAF subjects also randomised

set.seed(4271)

n_per_arm <- 20L

adsl <- data.frame(
  USUBJID = sprintf("SUBJ-%03d", seq_len(n_per_arm * 3L)),
  STUDYID = "STUDY-001",
  stringsAsFactors = FALSE
)

adsl$TRT01A <- rep(
  c("Treatment A", "Treatment B", "Not Treated"),
  each = n_per_arm
)

# Population flags
adsl$SAFFL  <- ifelse(adsl$TRT01A != "Not Treated", "Y", "N")
adsl$RANDFL <- ifelse(adsl$TRT01A != "Not Treated", "Y", "N")

# Completion / discontinuation (SAF subjects only)
# 15/20 complete per arm; 5/20 discontinue per arm
adsl$COMPLFL <- "N"
adsl$COMPLFL[adsl$SAFFL == "Y"] <- rep(
  c(rep("Y", 15L), rep("N", 5L)),
  times = 2L
)

disc_reasons <- c("Adverse Event", "Withdrawal by Subject",
                  "Physician Decision", "Lost to Follow-up", "Other")
adsl$DCSREAS <- ""
adsl$DCSREAS[adsl$SAFFL == "Y" & adsl$COMPLFL == "N"] <- rep(
  disc_reasons,
  times = 2L   # 5 discontinuers per arm × 2 arms
)

# Demographics
adsl$AGE <- c(
  sample(45:75, n_per_arm, replace = TRUE),   # Arm A
  sample(45:75, n_per_arm, replace = TRUE),   # Arm B
  sample(45:75, n_per_arm, replace = TRUE)    # Not treated
)
adsl$SEX <- rep(
  c(rep("M", 10L), rep("F", 10L)),
  times = 3L
)
adsl$RACE <- rep(
  c(rep("White", 12L),
    rep("Black or African American", 5L),
    rep("Other", 3L)),
  times = 3L
)

# Weight / BMI (optional extras; used by some shells)
adsl$WEIGHTBL <- round(rnorm(nrow(adsl), mean = 75, sd = 12), 1)
adsl$BMIBL    <- round(adsl$WEIGHTBL / (1.70^2), 1)


# ── ADAE ──────────────────────────────────────────────────────────────────────
# Adverse events for SAF subjects only.
# Covers all SOCs, PTs, relationship flags, severity grades, and outcomes
# required by T-AE-01 and T-AE-02.

saf_subjects <- adsl$USUBJID[adsl$SAFFL == "Y"]   # 40 subjects

# Base AE rows — one record per subject-event combination
adae <- data.frame(
  USUBJID = rep(saf_subjects, each = 3L),   # 3 events per SAF subject = 120 rows
  STUDYID = "STUDY-001",
  stringsAsFactors = FALSE
)

adae$TRT01A <- adsl$TRT01A[match(adae$USUBJID, adsl$USUBJID)]

# All are treatment-emergent
adae$TRTEMFL <- "Y"

# Rotate through SOC/PT pairs to ensure all shells see each value
soc_pt_pairs <- list(
  list(soc = "Cardiac disorders",           pt = "Palpitations"),
  list(soc = "Cardiac disorders",           pt = "Tachycardia"),
  list(soc = "Gastrointestinal disorders",  pt = "Nausea"),
  list(soc = "Gastrointestinal disorders",  pt = "Vomiting"),
  list(soc = "Gastrointestinal disorders",  pt = "Diarrhoea"),
  list(soc = "Nervous system disorders",    pt = "Headache"),
  list(soc = "Nervous system disorders",    pt = "Dizziness"),
  list(soc = "Nervous system disorders",    pt = "Fatigue")
)

n_ae <- nrow(adae)
pair_idx   <- ((seq_len(n_ae) - 1L) %% length(soc_pt_pairs)) + 1L
adae$AEBODSYS <- vapply(pair_idx, function(i) soc_pt_pairs[[i]]$soc, character(1))
adae$AEDECOD  <- vapply(pair_idx, function(i) soc_pt_pairs[[i]]$pt,  character(1))

# Relationship to study drug — cycle through values including those in template
aerel_vals  <- c("RELATED", "PROBABLE", "POSSIBLE", "NONE", "REMOTE")
adae$AEREL  <- rep_len(aerel_vals, n_ae)

# Seriousness — ensure at least a few "Y" per arm
adae$AESER  <- "N"
adae$AESER[seq(1, n_ae, by = 10L)] <- "Y"

# Toxicity grade — ensure some Grade >= 3
adae$AETOXGR <- rep_len(c("1", "2", "3", "4", "2", "1", "3", "2", "1", "2"), n_ae)

# Action taken — ensure some "DRUG WITHDRAWN"
adae$AEACN   <- "DOSE NOT CHANGED"
adae$AEACN[seq(5, n_ae, by = 15L)] <- "DRUG WITHDRAWN"

# Outcome — ensure some "FATAL"
adae$AEOUT   <- "RECOVERED/RESOLVED"
adae$AEOUT[seq(10, n_ae, by = 25L)] <- "FATAL"

# Add a handful of non-emergent rows (TRTEMFL = "N") for realism
non_emergent <- data.frame(
  USUBJID  = saf_subjects[1:5],
  STUDYID  = "STUDY-001",
  TRT01A   = adsl$TRT01A[match(saf_subjects[1:5], adsl$USUBJID)],
  TRTEMFL  = "N",
  AEBODSYS = "Cardiac disorders",
  AEDECOD  = "Palpitations",
  AEREL    = "NONE",
  AESER    = "N",
  AETOXGR  = "1",
  AEACN    = "DOSE NOT CHANGED",
  AEOUT    = "RECOVERED/RESOLVED",
  stringsAsFactors = FALSE
)

adae <- rbind(adae, non_emergent)

# Carry subject-level population flags from ADSL onto ADAE
# (standard ADaM practice — SAFFL, TRT01A etc. are merged onto event datasets)
adae$SAFFL <- adsl$SAFFL[match(adae$USUBJID, adsl$USUBJID)]


# ── ADLB ──────────────────────────────────────────────────────────────────────
# Lab data for SAF subjects.
# Covers all PARAMCDs in T-LB-01 (HGB, PLT, WBC, ALT, AST, CREAT, GLUC)
# and all BNRIND / WGRNRIND levels required by T-LB-02.

params <- list(
  list(paramcd = "HGB",  param = "Haemoglobin (g/dL)",          
       bl_mean = 135, bl_sd = 15,  chg_mean = -2,  chg_sd = 5),
  list(paramcd = "PLT",  param = "Platelets (10^9/L)",           
       bl_mean = 220, bl_sd = 50,  chg_mean = -5,  chg_sd = 20),
  list(paramcd = "WBC",  param = "White Blood Cell Count (10^9/L)",
       bl_mean = 6.5, bl_sd = 1.5, chg_mean = 0.2, chg_sd = 0.8),
  list(paramcd = "ALT",  param = "Alanine Aminotransferase (U/L)",
       bl_mean = 28,  bl_sd = 10,  chg_mean = 2,   chg_sd = 8),
  list(paramcd = "AST",  param = "Aspartate Aminotransferase (U/L)",
       bl_mean = 25,  bl_sd = 8,   chg_mean = 1,   chg_sd = 6),
  list(paramcd = "CREAT",param = "Creatinine (umol/L)",           
       bl_mean = 85,  bl_sd = 15,  chg_mean = 3,   chg_sd = 10),
  list(paramcd = "GLUC", param = "Glucose (mmol/L)",              
       bl_mean = 5.2, bl_sd = 0.8, chg_mean = 0.1, chg_sd = 0.5)
)

adlb_rows <- lapply(params, function(p) {
  # Baseline record (ABLFL = "Y")
  bl <- data.frame(
    USUBJID  = saf_subjects,
    STUDYID  = "STUDY-001",
    TRT01A   = adsl$TRT01A[match(saf_subjects, adsl$USUBJID)],
    PARAMCD  = p$paramcd,
    PARAM    = p$param,
    AVAL     = round(rnorm(length(saf_subjects), p$bl_mean, p$bl_sd), 2),
    BASE     = NA_real_,
    CHG      = NA_real_,
    ABLFL    = "Y",
    ANL01FL  = "Y",
    SAFFL    = "Y",
    stringsAsFactors = FALSE
  )
  bl$BASE <- bl$AVAL

  # Post-baseline record (ABLFL != "Y", CHG = AVAL - BASE)
  pb <- bl
  pb$AVAL  <- round(bl$AVAL + rnorm(length(saf_subjects), p$chg_mean, p$chg_sd), 2)
  pb$CHG   <- round(pb$AVAL - bl$BASE, 2)
  pb$ABLFL <- "N"

  rbind(bl, pb)
})

adlb <- do.call(rbind, adlb_rows)

# Add BNRIND (baseline normal range indicator) and WGRNRIND (worst post-BL)
# Required by T-LB-02. Distribute Low/Normal/High so all cells are non-empty.
nrind_levels <- c("Low", "Normal", "High")

bl_rows <- adlb$ABLFL == "Y"
pb_rows <- adlb$ABLFL == "N"

# Only HGB, ALT, CREAT are used in T-LB-02 — populate all for completeness
adlb$BNRIND   <- NA_character_
adlb$WGRNRIND <- NA_character_

# Baseline: rotate Low/Normal/High across subjects (within each parameter)
adlb$BNRIND[bl_rows] <- rep_len(
  c(rep("Normal", 14L), rep("Low", 3L), rep("High", 3L)),
  sum(bl_rows)
)
# Carry baseline BNRIND forward to post-baseline rows
adlb$BNRIND[pb_rows] <- adlb$BNRIND[bl_rows]

# Worst post-baseline grade — rotate so all 3 × 3 shift cells are non-empty
adlb$WGRNRIND[pb_rows] <- rep_len(
  c(rep("Normal", 12L), rep("Low", 4L), rep("High", 4L)),
  sum(pb_rows)
)

# ── Verify key cell counts ────────────────────────────────────────────────────
cat("=== adsl ===\n")
print(table(adsl$TRT01A, adsl$SAFFL))

cat("\n=== adae (TRTEMFL = Y, by TRT01A) ===\n")
print(table(adae$TRT01A[adae$TRTEMFL == "Y"]))

cat("\n=== adlb (baseline, by PARAMCD and TRT01A) ===\n")
print(table(adlb$PARAMCD[adlb$ABLFL == "Y"], adlb$TRT01A[adlb$ABLFL == "Y"]))

cat("\n=== T-LB-02 shift cells (BNRIND x WGRNRIND, HGB only) ===\n")
hgb_pb <- adlb[adlb$PARAMCD == "HGB" & adlb$ABLFL == "N", ]
print(table(hgb_pb$BNRIND, hgb_pb$WGRNRIND))

cat("\nDone. Objects created: adsl, adae, adlb\n")
```

---

## Expected output

```
=== adsl ===
               SAFFL
TRT01A           N  Y
  Not Treated   20  0
  Treatment A    0 20
  Treatment B    0 20

=== adae (TRTEMFL = Y, by TRT01A) ===
  Treatment A   Treatment B
           60            60

=== adlb (baseline, by PARAMCD and TRT01A) ===
       Treatment A  Treatment B
  ALT           20           20
  AST           20           20
  CREAT         20           20
  GLUC          20           20
  HGB           20           20
  PLT           20           20
  WBC           20           20

=== T-LB-02 shift cells (BNRIND x WGRNRIND, HGB only) ===
         High  Low  Normal
  High      x    x       x
  Low       x    x       x
  Normal    x    x       x
```

---

## Compatibility matrix

| Shell | Works with this data? | Notes |
|-------|-----------------------|-------|
| T-DM-01 | ✅ | All demographics present; correct case |
| T-DS-01 | ✅ | All discontinuation reasons present |
| T-AE-01 | ✅ | All AE flags, grades, and outcomes present |
| T-AE-02 | ✅ | All 3 SOCs and 8 PTs present |
| T-LB-01 | ✅ | All 7 PARAMCDs; baseline and change rows |
| T-LB-02 | ✅ | All shift combinations (3 × 3) for HGB, ALT, CREAT |

---

## Table Generation

Run the data generation code above first, then use the pipelines below.
Each shell has both a step-by-step pipe and an `ars_pipeline()` equivalent.

> **Prerequisites:** `library(ars)` and the data objects `adsl`, `adae`,
> `adlb` in your session.

```r
library(ars)
```

---

> **Note on the pipe:** `run()` returns the ARD only — the shell is not
> carried through. In the step-by-step form you must hold the hydrated shell
> in a variable and pass it explicitly to `render()`. The `ars_pipeline()`
> form handles this internally and is the recommended approach for scripts.
> Fixing the pipe so it works naturally end-to-end is tracked in
> `PLAN_DATA_DRIVEN_GROUPS.md` as a future design improvement.

---

### T-DM-01 — Summary of Demographic Characteristics

Analyses: AGE (continuous), SEX and RACE (categorical frequencies).  
Dataset: ADSL only.

```r
# Step-by-step — hold shell in variable, pass to render() explicitly
shell_dm01 <- use_shell("T-DM-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     AGE = "AGE", SEX = "SEX", RACE = "RACE")
  )
ard_dm01 <- run(shell_dm01, adam = list(ADSL = adsl))
render(ard_dm01, shell_dm01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-DM-01",
  adam         = list(ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   AGE = "AGE", SEX = "SEX", RACE = "RACE"),
  backend      = "tfrmt"
)
```

---

### T-DS-01 — Subject Disposition

Analyses: randomised, treated, completed, and each discontinuation reason.  
Dataset: ADSL only.

```r
# Step-by-step
shell_ds01 <- use_shell("T-DS-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", RANDFL = "RANDFL",
                     SAFFL = "SAFFL", COMPLFL = "COMPLFL",
                     DCSREAS = "DCSREAS")
  )
ard_ds01 <- run(shell_ds01, adam = list(ADSL = adsl))
render(ard_ds01, shell_ds01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-DS-01",
  adam         = list(ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", RANDFL = "RANDFL",
                   SAFFL = "SAFFL", COMPLFL = "COMPLFL",
                   DCSREAS = "DCSREAS"),
  backend      = "tfrmt"
)
```

---

### T-AE-01 — Overview of Adverse Events

Analyses: any TEAE, related TEAE, SAE, Grade ≥ 3, leading to discontinuation,
fatal. Denominator (N) taken from ADSL safety population.  
Datasets: ADAE + ADSL.

```r
# Step-by-step
shell_ae01 <- use_shell("T-AE-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     TRTEMFL = "TRTEMFL", AEREL = "AEREL",
                     AESER = "AESER", AETOXGR = "AETOXGR",
                     AEACN = "AEACN", AEOUT = "AEOUT")
  )
ard_ae01 <- run(shell_ae01, adam = list(ADAE = adae, ADSL = adsl))
render(ard_ae01, shell_ae01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-AE-01",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL", AEREL = "AEREL",
                   AESER = "AESER", AETOXGR = "AETOXGR",
                   AEACN = "AEACN", AEOUT = "AEOUT"),
  backend      = "tfrmt"
)
```

---

### T-AE-02 — TEAEs by System Organ Class and Preferred Term

Analyses: subject counts and percentages per SOC and PT.  
Datasets: ADAE + ADSL.

```r
# Step-by-step
shell_ae02 <- use_shell("T-AE-02") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     TRTEMFL = "TRTEMFL",
                     AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD")
  )
ard_ae02 <- run(shell_ae02, adam = list(ADAE = adae, ADSL = adsl))
render(ard_ae02, shell_ae02, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-AE-02",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL",
                   AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
  backend      = "tfrmt"
)
```

---

### T-LB-01 — Summary of Laboratory Parameters (Descriptive Statistics)

Analyses: Count, Mean (SD), Median, Range at baseline and change from
baseline for each of 7 lab parameters.  
Datasets: ADLB + ADSL.

```r
# Step-by-step
shell_lb01 <- use_shell("T-LB-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                     ABLFL = "ABLFL", AVAL = "AVAL", CHG = "CHG")
  )
ard_lb01 <- run(shell_lb01, adam = list(ADLB = adlb, ADSL = adsl))
render(ard_lb01, shell_lb01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-LB-01",
  adam         = list(ADLB = adlb, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                   ABLFL = "ABLFL", AVAL = "AVAL", CHG = "CHG"),
  backend      = "tfrmt"
)
```

---

### T-LB-02 — Shift Table (Baseline vs. Post-Baseline Normal Range)

Analyses: subject counts per baseline × worst post-baseline normal range
category (Low / Normal / High) for HGB, ALT, and CREAT.  
Datasets: ADLB + ADSL.

```r
# Step-by-step
shell_lb02 <- use_shell("T-LB-02") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                     BNRIND = "BNRIND", WGRNRIND = "WGRNRIND")
  )
ard_lb02 <- run(shell_lb02, adam = list(ADLB = adlb, ADSL = adsl))
render(ard_lb02, shell_lb02, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-LB-02",
  adam         = list(ADLB = adlb, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                   BNRIND = "BNRIND", WGRNRIND = "WGRNRIND"),
  backend      = "tfrmt"
)
```

---

## When to update this file

Once **Phase A** of `PLAN_DATA_DRIVEN_GROUPS.md` is complete:

1. The templates will no longer have hardcoded treatment values.
2. The `variable_map` calls above become unnecessary for variables that
   match ADaM conventions — `hydrate()` will handle them automatically.
3. Replace `adsl`/`adae`/`adlb` references with `ars::adsl`, `ars::adae`,
   `ars::adlb` (CDISCPILOT01 data bundled in the `ars` package).
4. Archive or delete this file at that point.
