# review_24_6.R --------------------------------------------------------------
#
# Hands-on review script for MASTER_PLAN §24 — ARD self-sufficiency.
# Walks through demos that mirror the test suite so you can eyeball
# the behaviour rather than just trusting the green dots.
#
# §24.6 (arstlf short-circuit, MERGED TO MAIN):
#
#   Demo A  — show that enrich_ard_with_geometry() produces a
#             self-sufficient ARD (all geometry columns embedded).
#   Demo B  — T-DM-01 byte-for-byte parity: render(bare)  vs  render(enriched).
#   Demo C  — T-AE-02 bare ARD renders cleanly (sanity baseline).
#   Demo D  — T-AE-02 enriched ARD aborts with §24.13 pointer (the v1
#             prototype-expansion limitation).
#   Demo E  — RDS round-trip: saveRDS/readRDS the enriched ARD, render
#             from the round-tripped frame alone.
#
# §24.7 (arsstudio bundle, ON FEATURE BRANCHES):
#
#   Demo F  — shell_to_json + shell_from_json round-trip preserves the
#             hydrated Shell.
#   Demo G  — write a reproducibility bundle, extract it, render from
#             the bundle's enriched RDS + shell.json alone, verify
#             byte-for-byte parity vs the in-memory render.
#
# How to run:
#
#   1. From the arsworks root, with R working directory set there
#      (e.g. open arsworks.Rproj in RStudio, or run `cd
#      ~/Downloads/Projects/arsworks` first), then:
#
#        source("review_24_6.R")
#
#      The script will:
#        - check out the §24.7 feature branches on arsshells + arsstudio
#        - source sync_and_load.R to pull/document/load all six packages
#        - run all demos
#
#   2. To inspect a rendered table visually, the script stores the gt
#      objects in `.review_results`; e.g. `.review_results$dm01_enriched`
#      will print the gt table at the console.

# ── Configuration ────────────────────────────────────────────────────────────

ROOT <- normalizePath(getwd())
FEATURE_BRANCHES <- list(
  arsshells = "feat/shell-to-json-2026-05-02",
  arsstudio = "feat/bundle-export-2026-05-02"
)

stopifnot(file.exists(file.path(ROOT, "sync_and_load.R")))
for (pkg in names(FEATURE_BRANCHES)) {
  stopifnot(dir.exists(file.path(ROOT, pkg)))
}

# ── 1. Check out feature branches for the §24.7 work ─────────────────────────

message("\n══ Checking out feature branches ═══════════════════════════════════════")

for (pkg in names(FEATURE_BRANCHES)) {
  branch <- FEATURE_BRANCHES[[pkg]]
  pkg_path <- file.path(ROOT, pkg)
  system2("git", c("-C", pkg_path, "fetch", "origin", branch),
          stdout = TRUE, stderr = TRUE)
  out <- system2("git", c("-C", pkg_path, "checkout", branch),
                 stdout = TRUE, stderr = TRUE)
  message(paste("  ", pkg, ": ", paste(out, collapse = " ")))
  system2("git", c("-C", pkg_path, "pull", "--ff-only"),
          stdout = TRUE, stderr = TRUE)
  head_sha <- system2("git", c("-C", pkg_path, "rev-parse", "--short", "HEAD"),
                      stdout = TRUE, stderr = FALSE)
  message(sprintf("  %s HEAD: %s", pkg, head_sha))
}

# ── 2. Sync + load all packages ──────────────────────────────────────────────

source(file.path(ROOT, "sync_and_load.R"))

# ── 3. Helper: build a hydrated shell + bare ARD + enriched ARD ──────────────

.fixture <- function(template, adam) {
  group_map <- list(
    GRP_TRT = list(
      list(id = "GRP_TRT_A", value = "Treatment A",
           label = "Treatment A (N=20)", order = 1),
      list(id = "GRP_TRT_B", value = "Treatment B",
           label = "Treatment B (N=20)", order = 2)
    )
  )
  shell <- arsshells::use_shell(template) |>
    arsshells::hydrate(group_map = group_map, adam = adam)
  bare <- arsresult::run(shell@reporting_event, adam = adam)
  geom <- arsshells::shell_geometry_frame(shell)
  enriched <- arscore::enrich_ard_with_geometry(bare, shell@reporting_event, geom)
  list(shell = shell, bare = bare, enriched = enriched)
}

# Hide gt's per-render random div id so byte-for-byte comparisons survive.
.normalise_gt_html <- function(gt_tbl) {
  s <- as.character(gt::as_raw_html(gt_tbl))
  s <- gsub('id="[a-z]{10}"', 'id="STABLE_ID"', s)
  s <- gsub('#[a-z]{10} ',    '#STABLE_ID ',    s)
  s
}

.review_results <- list()

# ── Demo A — enriched ARD self-sufficiency ───────────────────────────────────

message("\n══ Demo A — enriched ARD carries embedded geometry ══════════════════")

dm01 <- .fixture("T-DM-01", list(ADSL = ars::adsl))

embedded_cols <- arstlf:::.embedded_geom_cols
message(sprintf("  Bare ARD columns (%d):     %s",
                ncol(dm01$bare), paste(names(dm01$bare), collapse = ", ")))
message(sprintf("  Enriched ARD columns (%d): %s",
                ncol(dm01$enriched), paste(names(dm01$enriched), collapse = ", ")))
message(sprintf("  Embedded geom cols on bare?      %s",
                all(embedded_cols %in% names(dm01$bare))))
message(sprintf("  Embedded geom cols on enriched?  %s",
                all(embedded_cols %in% names(dm01$enriched))))

.review_results$dm01_bare     <- dm01$bare
.review_results$dm01_enriched <- dm01$enriched

# ── Demo B — T-DM-01 byte-for-byte render parity ─────────────────────────────

message("\n══ Demo B — T-DM-01: render(bare) == render(enriched) ════════════════")

gt_bare     <- arstlf::render(dm01$bare,     dm01$shell, backend = "tfrmt")
gt_enriched <- arstlf::render(dm01$enriched, dm01$shell, backend = "tfrmt")

html_bare     <- .normalise_gt_html(gt_bare)
html_enriched <- .normalise_gt_html(gt_enriched)

message(sprintf("  Identical (modulo gt's per-render random id)? %s",
                identical(html_bare, html_enriched)))
message(sprintf("  HTML lengths: bare=%d  enriched=%d",
                nchar(html_bare), nchar(html_enriched)))

.review_results$dm01_gt_bare     <- gt_bare
.review_results$dm01_gt_enriched <- gt_enriched

# ── Demo C — T-AE-02 bare ARD renders cleanly ────────────────────────────────

message("\n══ Demo C — T-AE-02 bare ARD renders cleanly (baseline) ══════════════")

ae02 <- .fixture("T-AE-02", list(ADAE = ars::adae, ADSL = ars::adsl))

gt_ae02_bare <- tryCatch(
  arstlf::render(ae02$bare, ae02$shell, backend = "tfrmt"),
  error = function(e) {
    message("  ✗ Unexpected error: ", conditionMessage(e))
    NULL
  }
)
if (!is.null(gt_ae02_bare)) {
  message("  ✓ T-AE-02 bare ARD rendered without error.")
  .review_results$ae02_gt_bare <- gt_ae02_bare
}

# ── Demo D — T-AE-02 enriched ARD aborts with §24.13 pointer ─────────────────

message("\n══ Demo D — T-AE-02 enriched ARD must abort (§24.13) ═════════════════")

abort_msg <- tryCatch(
  {
    arstlf::render(ae02$enriched, ae02$shell, backend = "tfrmt")
    NA_character_
  },
  error = function(e) conditionMessage(e)
)
if (is.na(abort_msg)) {
  message("  ✗ Expected abort, but render() succeeded.")
} else {
  message("  ✓ Abort fired. Message:")
  message(paste("    ", strsplit(abort_msg, "\n")[[1]], collapse = "\n"))
}

# ── Demo E — RDS round-trip self-sufficiency ─────────────────────────────────

message("\n══ Demo E — RDS round-trip: enriched ARD survives disk → reload ══════")

# RDS preserves R's column types exactly, so a writeRDS / readRDS pair
# is the cleanest way to demonstrate "self-sufficiency". A CSV export
# also works for human inspection but loses tibble class and some
# column types (NA-only cols collapse to logical, mixed numerics get
# coerced) — the §24 goal is a *self-describing* ARD frame, not a
# specific serialization. RDS makes that claim sharp.
rds_path <- tempfile(fileext = ".rds")
saveRDS(dm01$enriched, rds_path)
roundtrip <- readRDS(rds_path)

# Enriched ARD must still satisfy the §24.6 detection rule after a disk trip.
message(sprintf("  Round-tripped ARD has all embedded cols? %s",
                all(embedded_cols %in% names(roundtrip))))

gt_roundtrip <- tryCatch(
  arstlf::render(roundtrip, dm01$shell, backend = "tfrmt"),
  error = function(e) {
    message("  ✗ Round-trip render failed: ", conditionMessage(e))
    NULL
  }
)
if (!is.null(gt_roundtrip)) {
  html_rt <- .normalise_gt_html(gt_roundtrip)
  message(sprintf("  Identical HTML to in-memory enriched? %s",
                  identical(html_rt, html_enriched)))
  .review_results$dm01_gt_roundtrip <- gt_roundtrip
}

# ── Demo F — shell_to_json round-trip preserves a hydrated Shell ─────────────

message("\n══ Demo F — shell_to_json + shell_from_json round-trip ═════════════════")

shell_json <- tempfile(fileext = ".json")
arsshells::shell_to_json(dm01$shell, shell_json)
shell_back <- arsshells::shell_from_json(shell_json, quiet = TRUE)

message(sprintf("  ID matches:           %s", identical(dm01$shell@id, shell_back@id)))
message(sprintf("  N sections matches:   %s",
                identical(length(dm01$shell@sections), length(shell_back@sections))))
geom1 <- arsshells::shell_geometry_frame(dm01$shell)
geom2 <- arsshells::shell_geometry_frame(shell_back)
message(sprintf("  Geometry frame rows:  %d (orig) vs %d (round-trip)",
                nrow(geom1), nrow(geom2)))
message(sprintf("  Geometry analysis_id matches:  %s",
                identical(geom1$analysis_id, geom2$analysis_id)))

# ── Demo G — full bundle round-trip ──────────────────────────────────────────

message("\n══ Demo G — Reproducibility bundle: write → extract → render ═══════════")

bundle_zip <- tempfile(fileext = ".zip")
arsstudio:::.write_bundle_zip(
  out_zip  = bundle_zip,
  shell_id = "T-DM-01",
  shell    = dm01$shell,
  ard      = dm01$bare
)
message(sprintf("  Bundle written: %s (%d bytes)",
                bundle_zip, file.info(bundle_zip)$size))

bundle_entries <- utils::unzip(bundle_zip, list = TRUE)$Name
message("  Entries:")
for (e in bundle_entries) message(sprintf("    - %s", e))

ext_dir <- tempfile("ars_bundle_extract_")
dir.create(ext_dir)
utils::unzip(bundle_zip, exdir = ext_dir)

# Reload from the bundle — RDS path (the recommended one).
ard_from_rds <- readRDS(file.path(ext_dir, "T-DM-01_ard_enriched.rds"))
shell_from_bundle <- arsshells::shell_from_json(
  file.path(ext_dir, "T-DM-01_shell.json"),
  quiet = TRUE
)
gt_from_bundle <- arstlf::render(ard_from_rds, shell_from_bundle, backend = "tfrmt")

html_bundle <- .normalise_gt_html(gt_from_bundle)
message(sprintf("  Bundle render matches in-memory enriched render? %s",
                identical(html_bundle, html_enriched)))

.review_results$bundle_path     <- bundle_zip
.review_results$bundle_extract  <- ext_dir
.review_results$gt_from_bundle  <- gt_from_bundle

# ── Done ────────────────────────────────────────────────────────────────────

message("\n══ Done ══════════════════════════════════════════════════════════════")
message("  Inspect rendered tables interactively:")
message("    .review_results$dm01_gt_bare")
message("    .review_results$dm01_gt_enriched")
message("    .review_results$ae02_gt_bare")
message("    .review_results$dm01_gt_roundtrip")
message("    .review_results$gt_from_bundle")
message("")
message("  Inspect bundle on disk:")
message(sprintf("    %s", .review_results$bundle_path))
message(sprintf("    extracted: %s", .review_results$bundle_extract))
message("")
message("  Inspect ARD frames:")
message("    str(.review_results$dm01_bare)")
message("    str(.review_results$dm01_enriched)")
message("")
message("  When you're done reviewing, return packages to main with:")
message("    system('git -C arsshells checkout main')")
message("    system('git -C arsstudio checkout main')")

invisible(.review_results)
