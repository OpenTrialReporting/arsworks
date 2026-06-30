#!/usr/bin/env Rscript
# Install the arsworks suite inside the CI/Docker image.
#
# WHY THIS EXISTS (and why we do NOT use devtools::install for the dep tree):
# devtools::install()/remotes run their own dependency resolver that downloads
# and compiles packages from SOURCE on Linux, bypassing bspm. That made every
# dependency (gt, V8/libsass, pak, fs, ...) build from source, and some of those
# source builds fail. utils::install.packages(), by contrast, is bridged by bspm
# on the r2u base image to apt/r2u BINARIES — fast and reliable. So:
#   1. install all CRAN deps of the six sub-packages via install.packages()  (binaries)
#   2. install the six local packages from source via `R CMD INSTALL`         (deps already present)
#
# NOTE: webshot2 (an arsstudio dep installed below) provides the R interface
# only; rendering gt/Shiny output to images at runtime also needs a headless
# Chrome (via chromote), intentionally omitted to keep the image lean.

local_pkgs <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

# --- 1. Collect declared CRAN dependencies across the six sub-packages --------
parse_deps <- function(p) {
  d <- read.dcf(file.path(p, "DESCRIPTION"))
  fields <- intersect(c("Depends", "Imports", "LinkingTo", "Suggests"), colnames(d))
  if (!length(fields)) return(character())
  raw <- unlist(strsplit(paste(d[1, fields], collapse = ","), ","))
  raw <- trimws(sub("\\(.*", "", raw))          # strip "(>= x.y)" version pins
  raw[nzchar(raw)]
}
deps <- unique(unlist(lapply(local_pkgs, parse_deps)))
deps <- setdiff(deps, c(local_pkgs, "R"))        # not the local pkgs, not base R
deps <- union(deps, c("devtools", "testthat"))   # needed by run_tests.R

cat(sprintf("Installing %d CRAN dependencies as r2u binaries (via bspm)...\n", length(deps)))
install.packages(deps)                           # bspm -> apt/r2u binaries

# --- 2. Install the six local packages from source, in dependency order -------
Rbin <- file.path(R.home("bin"), "R")
for (p in local_pkgs) {
  cat(sprintf("\n==> R CMD INSTALL %s\n", p))
  st <- system2(Rbin, c("CMD", "INSTALL", "--no-docs", "--no-multiarch", shQuote(p)))
  if (st != 0L) stop(sprintf("installation failed for '%s'", p), call. = FALSE)
}

# --- 3. Verify all six import cleanly -----------------------------------------
for (p in local_pkgs) {
  suppressPackageStartupMessages(library(p, character.only = TRUE))
  cat("loaded", p, "\n")
}
cat("\nSuite installed successfully.\n")
