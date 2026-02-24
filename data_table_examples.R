# data_table_examples.R -------------------------------------------------------
#
# Example ADaM datasets and table generation using pharmaverseadam.
#
# Study: CDISC Pilot (CDISCPILOT01)
# Arms:  Placebo | Xanomeline Low Dose | Xanomeline High Dose
#
# Column derivations needed before use:
#   ADSL: RANDFL, COMPLFL, DCSREAS  (not in pharmaverseadam ADSL)
#   ADLB: WGRNRIND                  (use ANRIND; PLT -> PLAT rename)
#
# Usage: source this file to create adsl, adae, adlb and run all 6 tables.

library(pharmaverseadam)
library(ars)

# ── Load base datasets ────────────────────────────────────────────────────────

adsl <- pharmaverseadam::adsl
adae <- pharmaverseadam::adae
adlb <- pharmaverseadam::adlb

# ── ADSL derivations ──────────────────────────────────────────────────────────

# RANDFL: randomised if RANDDT is not missing
adsl$RANDFL <- ifelse(!is.na(adsl$RANDDT), "Y", "N")

# COMPLFL / DCSREAS: derived from EOSSTT
# EOSSTT = "COMPLETED"     -> COMPLFL = "Y", DCSREAS = ""
# EOSSTT = "DISCONTINUED"  -> COMPLFL = "N", DCSREAS = reason
# Use DTHFL to assign "Death" as a discontinuation reason where applicable;
# remaining discontinuers are assigned reasons rotating through the 5 categories
# used by the T-DS-01 template.
adsl$COMPLFL <- ifelse(!is.na(adsl$EOSSTT) & adsl$EOSSTT == "COMPLETED", "Y", "N")

disc_idx <- which(adsl$EOSSTT == "DISCONTINUED")
disc_reasons <- c("Adverse Event", "Withdrawal by Subject",
                  "Physician Decision", "Lost to Follow-up", "Other")

adsl$DCSREAS <- ""
# Subjects with death flag get "Adverse Event" as reason (closest match)
death_disc <- disc_idx[adsl$DTHFL[disc_idx] %in% "Y"]
other_disc  <- disc_idx[!adsl$DTHFL[disc_idx] %in% "Y"]

adsl$DCSREAS[death_disc] <- "Adverse Event"
adsl$DCSREAS[other_disc] <- rep_len(disc_reasons, length(other_disc))

# ── ADAE derivations ─────────────────────────────────────────────────────────

# AETOXGR: derive from AESEV (template filters on numeric grade strings)
# MILD -> "1", MODERATE -> "2", SEVERE -> "3"
adae$AETOXGR <- dplyr::case_match(
  adae$AESEV,
  "MILD"     ~ "1",
  "MODERATE" ~ "2",
  "SEVERE"   ~ "3",
  .default   = NA_character_
)

# AEACN: not populated in pharmaverseadam; set to "DOSE NOT CHANGED" as default
adae$AEACN <- ifelse(is.na(adae$AEACN), "DOSE NOT CHANGED", adae$AEACN)

# Carry SAFFL from ADSL
adae$SAFFL <- adsl$SAFFL[match(adae$USUBJID, adsl$USUBJID)]

# ── ADLB derivations ─────────────────────────────────────────────────────────

# Rename PLAT -> PLT to match T-LB-01 template PARAMCD
adlb$PARAMCD[adlb$PARAMCD == "PLAT"] <- "PLT"
adlb$PARAM[adlb$PARAM == "Platelet (GI/L)"] <- "Platelets (10^9/L)"

# WGRNRIND: use ANRIND (post-baseline normal range indicator)
# ANRIND is populated on all visits; WGRNRIND is only needed on analysis visits
adlb$WGRNRIND <- adlb$ANRIND

# Carry SAFFL from ADSL
adlb$SAFFL <- adsl$SAFFL[match(adlb$USUBJID, adsl$USUBJID)]

# ── Verify ────────────────────────────────────────────────────────────────────

cat("=== adsl (SAF population by arm) ===\n")
print(table(adsl$TRT01A[adsl$SAFFL == "Y"]))

cat("\n=== adsl disposition ===\n")
print(table(adsl$EOSSTT[adsl$SAFFL == "Y"], adsl$COMPLFL[adsl$SAFFL == "Y"]))

cat("\n=== adae (TRTEMFL = Y, by TRT01A) ===\n")
print(table(adae$TRT01A[!is.na(adae$TRTEMFL) & adae$TRTEMFL == "Y"]))

cat("\n=== adlb PARAMCDs for T-LB-01 ===\n")
lb01_params <- c("HGB","PLT","WBC","ALT","AST","CREAT","GLUC")
print(lb01_params %in% unique(adlb$PARAMCD))

cat("\n=== T-LB-02 BNRIND x WGRNRIND (HGB, ALT, CREAT analysis visits) ===\n")
anl <- adlb[adlb$PARAMCD %in% c("HGB","ALT","CREAT") &
            !is.na(adlb$ANL01FL) & adlb$ANL01FL == "Y", ]
print(table(anl$BNRIND, anl$WGRNRIND))

cat("\nDone. Objects created: adsl, adae, adlb\n")


# ── Table generation ──────────────────────────────────────────────────────────
#
# All 6 installed shells use Mode 2 (pre-specified) treatment arm groupings.
# group_map must always be supplied with the treatment arm values from the data.
# Without it, all arms return identical results (full dataset, unfiltered).
#
# Pattern A — pipe workflow:
#   run() returns an ArsResult ($ard + $shell); pass it directly to render().
# Pattern B — ars_pipeline():
#   All-in-one wrapper; simpler for scripts.

# Shared group_map — 3 arms from CDISCPILOT01
# 'value'  = the TRT01A value used to filter the data
# 'label'  = the column header shown in the rendered table (N=xx resolved at render time)
# 'order'  = left-to-right column order
grp_map <- list(
  GRP_TRT = list(
    list(id = "GRP_TRT_A", value = "Placebo",              label = "Placebo (N=xx)",              order = 1L),
    list(id = "GRP_TRT_B", value = "Xanomeline Low Dose",  label = "Xanomeline Low Dose (N=xx)",  order = 2L),
    list(id = "GRP_TRT_C", value = "Xanomeline High Dose", label = "Xanomeline High Dose (N=xx)", order = 3L)
  )
)

# ── T-DM-01 — Summary of Demographic Characteristics ─────────────────────────
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
# Note: WGRNRIND derived from ANRIND (post-baseline normal range indicator)
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
