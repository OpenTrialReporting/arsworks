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
  n <- length(saf_subjects)
  trt <- adsl$TRT01A[match(saf_subjects, adsl$USUBJID)]

  # Baseline record (ABLFL = "Y", ANL01FL = "Y")
  bl <- data.frame(
    USUBJID  = saf_subjects,
    STUDYID  = "STUDY-001",
    TRT01A   = trt,
    PARAMCD  = p$paramcd,
    PARAM    = p$param,
    AVAL     = round(rnorm(n, p$bl_mean, p$bl_sd), 2),
    BASE     = NA_real_,
    CHG      = NA_real_,
    ABLFL    = "Y",
    ANL01FL  = "Y",
    AVISITN  = 0L,
    SAFFL    = "Y",
    stringsAsFactors = FALSE
  )
  bl$BASE <- bl$AVAL

  # Post-baseline visit 1 (ABLFL = "N", ANL01FL = "N" — not the analysis visit)
  # Represents an intermediate on-treatment measurement; intentionally excluded
  # from T-LB-01 CHG analyses so that ANL01FL filtering is load-bearing.
  pb1 <- bl
  pb1$AVAL    <- round(bl$AVAL + rnorm(n, p$chg_mean * 0.5, p$chg_sd), 2)
  pb1$CHG     <- round(pb1$AVAL - bl$BASE, 2)
  pb1$ABLFL   <- "N"
  pb1$ANL01FL <- "N"   # ← excluded from analysis
  pb1$AVISITN <- 1L

  # Post-baseline visit 2 (ABLFL = "N", ANL01FL = "Y" — the analysis visit)
  # This is the record used by T-LB-01 CHG analyses and T-LB-02 shift tables.
  pb2 <- bl
  pb2$AVAL    <- round(bl$AVAL + rnorm(n, p$chg_mean, p$chg_sd), 2)
  pb2$CHG     <- round(pb2$AVAL - bl$BASE, 2)
  pb2$ABLFL   <- "N"
  pb2$ANL01FL <- "Y"   # ← included in analysis
  pb2$AVISITN <- 2L

  rbind(bl, pb1, pb2)
})

adlb <- do.call(rbind, adlb_rows)

# Add BNRIND (baseline normal range indicator) and WGRNRIND (worst post-BL)
# Required by T-LB-02. Assigned per-arm so Arms A and B have meaningfully
# different shift distributions. WGRNRIND is only set on the analysis visit
# (ANL01FL = "Y" AND ABLFL = "N").
#
# Arm A: more normal baseline, more improvement (shift toward Normal/Low)
# Arm B: more abnormal baseline, more worsening (shift toward High)
# Both arms have all 3×3 shift cells populated to exercise the full table.

adlb$BNRIND   <- NA_character_
adlb$WGRNRIND <- NA_character_

for (arm in c("Treatment A", "Treatment B")) {

  arm_subj <- adsl$USUBJID[adsl$TRT01A == arm]

  bl_idx  <- which(adlb$ABLFL == "Y"  & adlb$USUBJID %in% arm_subj)
  pb_idx  <- which(adlb$ABLFL == "N"  & adlb$USUBJID %in% arm_subj)
  anl_idx <- which(adlb$ABLFL == "N"  & adlb$ANL01FL == "Y" &
                     adlb$USUBJID %in% arm_subj)

  # Baseline BNRIND: Arm A skews Normal-heavy; Arm B skews High-heavy
  # (20 subjects × 7 params = 140 baseline rows per arm)
  if (arm == "Treatment A") {
    adlb$BNRIND[bl_idx] <- rep_len(
      c(rep("Normal", 14L), rep("Low", 4L), rep("High", 2L)),
      length(bl_idx)
    )
  } else {
    adlb$BNRIND[bl_idx] <- rep_len(
      c(rep("Normal", 10L), rep("Low", 3L), rep("High", 7L)),
      length(bl_idx)
    )
  }

  # Carry BNRIND forward to all post-baseline rows for this arm
  # Match by USUBJID + PARAMCD so every visit row gets the right value
  for (i in pb_idx) {
    bl_match <- which(adlb$ABLFL == "Y" &
                        adlb$USUBJID  == adlb$USUBJID[i] &
                        adlb$PARAMCD  == adlb$PARAMCD[i])
    adlb$BNRIND[i] <- adlb$BNRIND[bl_match]
  }

  # WGRNRIND on analysis visit only: Arm A skews toward improvement (Normal);
  # Arm B skews toward worsening (High). All shift cells populated in both arms.
  if (arm == "Treatment A") {
    adlb$WGRNRIND[anl_idx] <- rep_len(
      c(rep("Normal", 14L), rep("Low", 4L), rep("High", 2L)),
      length(anl_idx)
    )
  } else {
    adlb$WGRNRIND[anl_idx] <- rep_len(
      c(rep("Normal", 8L), rep("Low", 3L), rep("High", 9L)),
      length(anl_idx)
    )
  }
}

# ── Verify key cell counts ────────────────────────────────────────────────────
cat("=== adsl ===\n")
print(table(adsl$TRT01A, adsl$SAFFL))

cat("\n=== adae (TRTEMFL = Y, by TRT01A) ===\n")
print(table(adae$TRT01A[adae$TRTEMFL == "Y"]))

cat("\n=== adlb visit structure (rows per subject per PARAMCD, HGB only) ===\n")
hgb <- adlb[adlb$PARAMCD == "HGB", ]
cat("  All visits:            ", nrow(hgb) / length(unique(hgb$USUBJID)),
    "rows per subject\n")
cat("  ABLFL=Y (baseline):    ",
    sum(hgb$ABLFL == "Y") / length(unique(hgb$USUBJID)), "row per subject\n")
cat("  ABLFL=N, ANL01FL=N:    ",
    sum(hgb$ABLFL == "N" & hgb$ANL01FL == "N") / length(unique(hgb$USUBJID)),
    "row per subject (non-analysis visit — excluded from CHG analyses)\n")
cat("  ABLFL=N, ANL01FL=Y:    ",
    sum(hgb$ABLFL == "N" & hgb$ANL01FL == "Y") / length(unique(hgb$USUBJID)),
    "row per subject (analysis visit — included in CHG analyses)\n")

cat("\n=== adlb (baseline, by PARAMCD and TRT01A) ===\n")
print(table(adlb$PARAMCD[adlb$ABLFL == "Y"], adlb$TRT01A[adlb$ABLFL == "Y"]))

cat("\n=== adlb (analysis visit ABLFL=N ANL01FL=Y, by PARAMCD and TRT01A) ===\n")
anl_pb <- adlb[adlb$ABLFL == "N" & adlb$ANL01FL == "Y", ]
print(table(anl_pb$PARAMCD, anl_pb$TRT01A))

cat("\n=== T-LB-02 shift cells (BNRIND x WGRNRIND, HGB analysis visit only) ===\n")
hgb_pb <- adlb[adlb$PARAMCD == "HGB" & adlb$ABLFL == "N" & adlb$ANL01FL == "Y", ]
print(table(hgb_pb$BNRIND, hgb_pb$WGRNRIND))

cat("\nDone. Objects created: adsl, adae, adlb\n")


# ── Table Generation ──────────────────────────────────────────────────────────
# Run data generation above first, then load ars.
#
# All 6 installed shells use Mode 2 (pre-specified) treatment arm groupings.
# group_map must always be supplied to hydrate() / ars_pipeline() with the
# treatment arm values from your study data. Without it, all arms will return
# identical results (the full dataset, unfiltered).
#
# Pattern A — pipe workflow:
#   Assign the hydrated shell, then pass it explicitly to render().
#   run() returns an ArsResult (list with $ard and $shell), which render()
#   accepts directly.
#
# Pattern B — ars_pipeline():
#   All-in-one wrapper; simpler for scripts.

library(ars)

# Shared group_map for all shells (both arms use the same treatment arm values)
grp_map <- list(
  GRP_TRT = list(
    list(id = "GRP_TRT_A", value = "Treatment A", order = 1L),
    list(id = "GRP_TRT_B", value = "Treatment B", order = 2L)
  )
)

# ── T-DM-01 — Summary of Demographic Characteristics ─────────────────────────
# Analyses: AGE (continuous), SEX and RACE (categorical frequencies)
# Dataset: ADSL only

ard_dm01 <- use_shell("T-DM-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     AGE = "AGE", SEX = "SEX", RACE = "RACE"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADSL = adsl))
render(ard_dm01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-DM-01",
  adam         = list(ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   AGE = "AGE", SEX = "SEX", RACE = "RACE"),
  group_map    = grp_map,
  backend      = "tfrmt"
)


# ── T-DS-01 — Subject Disposition ────────────────────────────────────────────
# Analyses: randomised, treated, completed, and each discontinuation reason
# Dataset: ADSL only

ard_ds01 <- use_shell("T-DS-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", RANDFL = "RANDFL",
                     SAFFL = "SAFFL", COMPLFL = "COMPLFL",
                     DCSREAS = "DCSREAS"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADSL = adsl))
render(ard_ds01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-DS-01",
  adam         = list(ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", RANDFL = "RANDFL",
                   SAFFL = "SAFFL", COMPLFL = "COMPLFL",
                   DCSREAS = "DCSREAS"),
  group_map    = grp_map,
  backend      = "tfrmt"
)


# ── T-AE-01 — Overview of Adverse Events ─────────────────────────────────────
# Analyses: any TEAE, related TEAE, SAE, Grade >= 3, discontinuation, fatal
# Denominator (N) from ADSL safety population
# Datasets: ADAE + ADSL

ard_ae01 <- use_shell("T-AE-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     TRTEMFL = "TRTEMFL", AEREL = "AEREL",
                     AESER = "AESER", AETOXGR = "AETOXGR",
                     AEACN = "AEACN", AEOUT = "AEOUT"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADAE = adae, ADSL = adsl))
render(ard_ae01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-AE-01",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL", AEREL = "AEREL",
                   AESER = "AESER", AETOXGR = "AETOXGR",
                   AEACN = "AEACN", AEOUT = "AEOUT"),
  group_map    = grp_map,
  backend      = "tfrmt"
)


# ── T-AE-02 — TEAEs by System Organ Class and Preferred Term ─────────────────
# Analyses: subject counts and percentages per SOC and PT
# Datasets: ADAE + ADSL

ard_ae02 <- use_shell("T-AE-02") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     TRTEMFL = "TRTEMFL",
                     AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADAE = adae, ADSL = adsl))
render(ard_ae02, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-AE-02",
  adam         = list(ADAE = adae, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   TRTEMFL = "TRTEMFL",
                   AEBODSYS = "AEBODSYS", AEDECOD = "AEDECOD"),
  group_map    = grp_map,
  backend      = "tfrmt"
)


# ── T-LB-01 — Summary of Laboratory Parameters ───────────────────────────────
# Analyses: Count, Mean (SD), Median, Range at baseline and change from baseline
# for each of 7 lab parameters
# Datasets: ADLB + ADSL

ard_lb01 <- use_shell("T-LB-01") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                     ABLFL = "ABLFL", AVAL = "AVAL", CHG = "CHG"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADLB = adlb, ADSL = adsl))
render(ard_lb01, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-LB-01",
  adam         = list(ADLB = adlb, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                   ABLFL = "ABLFL", AVAL = "AVAL", CHG = "CHG"),
  group_map    = grp_map,
  backend      = "tfrmt"
)


# ── T-LB-02 — Shift Table (Baseline vs. Post-Baseline Normal Range) ───────────
# Analyses: subject counts per baseline x worst post-baseline normal range
# category (Low / Normal / High) for HGB, ALT, and CREAT
# Datasets: ADLB + ADSL

ard_lb02 <- use_shell("T-LB-02") |>
  hydrate(
    variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                     PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                     BNRIND = "BNRIND", WGRNRIND = "WGRNRIND"),
    group_map    = grp_map
  ) |>
  run(adam = list(ADLB = adlb, ADSL = adsl))
render(ard_lb02, backend = "tfrmt")

# ars_pipeline() equivalent
ars_pipeline(
  shell        = "T-LB-02",
  adam         = list(ADLB = adlb, ADSL = adsl),
  variable_map = c(TRT01A = "TRT01A", SAFFL = "SAFFL",
                   PARAMCD = "PARAMCD", ANL01FL = "ANL01FL",
                   BNRIND = "BNRIND", WGRNRIND = "WGRNRIND"),
  group_map    = grp_map,
  backend      = "tfrmt"
)