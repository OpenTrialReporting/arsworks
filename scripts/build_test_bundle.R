# build_test_bundle.R --------------------------------------------------------
#
# Helper invoked by the §25 no-arsworks GitHub Actions workflow (Step 7).
#
# Builds a freshly-hydrated T-DM-01 reproducibility bundle from the bundled
# `ars::adsl` test data and unpacks it into ./bundle/. The downstream job
# can then run `Rscript T-DM-01_recreate_test.R` from there in a clean R
# session that has *no* arsworks namespaces available.
#
# This script is deliberately small — its only job is to produce
# `bundle/T-DM-01_*.{rds,csv,json,R,md}` and the matching ADSL sample.
# The actual no-arsworks parity assertion lives inside the bundled
# `T-DM-01_recreate_test.R` (which we do NOT replicate here — using the
# bundled artifact is the whole point of the workflow).
#
# Run:
#   Rscript scripts/build_test_bundle.R [out_dir]
#
# Default `out_dir` is `bundle/`.

suppressMessages({
  for (pkg in c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")) {
    devtools::load_all(pkg, quiet = TRUE)
  }
  library(arsshells)
  library(dplyr)
})

args   <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1L) args[[1L]] else "bundle"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("== Building T-DM-01 bundle into ", normalizePath(out_dir), " ==")

group_map <- list(
  GRP_TRT = list(
    list(id = "GRP_TRT_A", value = "Treatment A",
         label = "Treatment A (N=20)", order = 1),
    list(id = "GRP_TRT_B", value = "Treatment B",
         label = "Treatment B (N=20)", order = 2)
  )
)

shell <- arsshells::use_shell("T-DM-01", quiet = TRUE) |>
  arsshells::hydrate(group_map = group_map,
                     adam      = list(ADSL = ars::adsl))
ard   <- arsresult::run(shell@reporting_event,
                        adam = list(ADSL = ars::adsl))

zip_path <- file.path(out_dir, "T-DM-01_bundle.zip")
arsstudio:::.write_bundle_zip(
  out_zip  = zip_path,
  shell_id = "T-DM-01",
  shell    = shell,
  ard      = ard
)

# Unpack the zip alongside it so the no-arsworks job can chdir straight
# into the unpacked directory.
utils::unzip(zip_path, exdir = out_dir)

# Drop the ADSL sample the recipe expects under the default sidecar name.
saveRDS(ars::adsl, file.path(out_dir, "T-DM-01_adsl_sample.rds"))

message("== Bundle contents in ", out_dir, " ==")
print(list.files(out_dir))

invisible(NULL)
