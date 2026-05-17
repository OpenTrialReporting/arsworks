# sync_and_load.R -------------------------------------------------------------
#
# Documents and loads all five sub-packages into the current R session.
# Run this at the start of every session, or after pulling new changes.
#
# What it does:
#   1. git pull --ff-only on each sub-package (skipped if no .git present)
#   2. devtools::document() on each sub-package  ← regenerates NAMESPACE files,
#      which are NOT tracked in the repos and must be built locally
#   3. devtools::load_all() on each sub-package in dependency order
#
# Usage:
#   source("sync_and_load.R")
#
# Prerequisites:
#   - renv::restore() must have been run at least once in this project
#   - git must be on PATH (only needed for the pull step)
#   - You must be inside the arsworks/ directory (or adjust ROOT below)

# Resolve the project root: only trust the editor path when this very script is
# the focused file (otherwise getSourceEditorContext picks up whatever unrelated
# file the user has open and we end up pointing at the wrong dir). Otherwise
# fall back to getwd().
.src_path <- tryCatch(
  rstudioapi::getSourceEditorContext()$path,
  error = function(e) ""
)
ROOT <- if (length(.src_path) && nchar(.src_path) > 0L &&
            file.exists(.src_path) &&
            basename(.src_path) == "sync_and_load.R") {
  normalizePath(dirname(.src_path))
} else {
  normalizePath(getwd())
}
rm(.src_path)

PACKAGES <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

# Sanity-check ROOT: every sub-package dir should be a direct child. Fail loud
# rather than silently skipping every package below (the previous behaviour).
.missing <- PACKAGES[!vapply(file.path(ROOT, PACKAGES), dir.exists, logical(1))]
if (length(.missing)) {
  stop("sync_and_load.R: ROOT does not look like arsworks/ — missing sub-package ",
       "dirs: ", paste(.missing, collapse = ", "), ". Resolved ROOT = ", ROOT, ". ",
       "setwd() to the arsworks/ directory or open sync_and_load.R in the editor ",
       "before sourcing.", call. = FALSE)
}
rm(.missing)

# ── 1. Pull latest from each sub-package repo ─────────────────────────────────

message("\n── Pulling latest from sub-package repos ──────────────────────────────")

pull_results <- vapply(PACKAGES, function(pkg) {
  path <- file.path(ROOT, pkg)
  if (!file.exists(file.path(path, ".git"))) {
    message(sprintf("  SKIP  %s  (no .git — running as submodule pointer only)", pkg))
    return("skipped")
  }
  # Submodules are typically checked out in detached HEAD at the SHA pinned by
  # the superproject; a plain `git pull` has no upstream to track. Skip rather
  # than warn — use `git submodule update --remote` from the superproject to
  # advance pins intentionally.
  head_ref <- system2("git", c("-C", path, "rev-parse", "--abbrev-ref", "HEAD"),
                      stdout = TRUE, stderr = FALSE)
  if (identical(as.character(head_ref), "HEAD")) {
    message(sprintf("  SKIP  %s  (detached HEAD — pinned by superproject)", pkg))
    return("skipped")
  }
  out <- system2("git", c("-C", path, "pull", "--ff-only"), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status") %||% 0L
  if (!is.null(status) && status != 0L) {
    message(sprintf("  WARN  %s  git pull failed:\n        %s", pkg, paste(out, collapse = "\n        ")))
    return("failed")
  }
  msg <- paste(out, collapse = " ")
  label <- if (grepl("Already up to date", msg, ignore.case = TRUE)) "up-to-date" else "updated"
  message(sprintf("  %-10s  %s", label, pkg))
  return(label)
}, character(1L))

# ── 1.5 Heal corrupt arstlf install (R 4.5 libdeflate workaround) ─────────────
#
# R 4.5's lazy-load DB compressor (libdeflate) produces a corrupt .rdb when
# arstlf is installed with byte-compilation enabled. Symptom: any access to an
# arstlf function fails with "internal error 1 in R_decompress1 with libdeflate"
# during the load_all step below. arstlf/DESCRIPTION carries ByteCompile: no for
# this reason, but devtools::install() and some renv paths ignore that field, so
# we re-check the installed copy here and reinstall via bare R CMD INSTALL if it
# can't decompress.
local({
  inst <- tryCatch(find.package("arstlf"), error = function(e) character(0))
  if (!length(inst)) return()
  ok <- tryCatch({
    loadNamespace("arstlf")
    ns <- asNamespace("arstlf")
    all(vapply(ls(ns, all.names = TRUE), function(n) {
      tryCatch({ force(get(n, envir = ns)); TRUE },
               error = function(e) FALSE)
    }, logical(1L)))
  }, error = function(e) FALSE)
  if (isTRUE(ok)) return()
  message("  HEAL  arstlf  (.rdb corrupt — reinstalling with --no-byte-compile)")
  try(unloadNamespace("arstlf"), silent = TRUE)
  unlink(inst, recursive = TRUE, force = TRUE)
  status <- system2(
    file.path(R.home("bin"), "R.exe"),
    c("CMD", "INSTALL", "--no-byte-compile",
      paste0("--library=", shQuote(dirname(inst))),
      shQuote(file.path(ROOT, "arstlf"))),
    stdout = FALSE, stderr = FALSE
  )
  if (!identical(status, 0L)) warning("arstlf reinstall failed (status ", status, ")")
})

# ── 2. Document + reload all packages in dependency order ─────────────────────

message("\n── Documenting packages ────────────────────────────────────────────────")

for (pkg in PACKAGES) {
  path <- file.path(ROOT, pkg)
  if (!dir.exists(path)) next
  tryCatch({
    devtools::document(path, quiet = TRUE)
    message(sprintf("  documented  %s", pkg))
  }, error = function(e) {
    message(sprintf("  WARN  %s  document() failed: %s", pkg, conditionMessage(e)))
  })
}

message("\n── Reloading packages ──────────────────────────────────────────────────")

for (pkg in PACKAGES) {
  path <- file.path(ROOT, pkg)
  if (!dir.exists(path)) {
    warning(sprintf("Package directory not found: %s", path))
    next
  }
  tryCatch(
    pkgload::unload(pkg),
    error = function(e) NULL   # not loaded yet — fine
  )
  devtools::load_all(path, quiet = TRUE)
  message(sprintf("  loaded  %s", pkg))
}

# ── 3. Summary ────────────────────────────────────────────────────────────────

message("\n── Done ────────────────────────────────────────────────────────────────")
updated  <- sum(pull_results == "updated")
uptodate <- sum(pull_results == "up-to-date")
skipped  <- sum(pull_results == "skipped")
failed   <- sum(pull_results == "failed")

message(sprintf(
  "  Pulled:  %d updated, %d already up-to-date, %d skipped, %d failed",
  updated, uptodate, skipped, failed
))
message(sprintf("  Loaded:  %s", paste(PACKAGES, collapse = ", ")))

if (failed > 0L) {
  warning("One or more git pulls failed. Check messages above.")
}

invisible(list(pull = pull_results, packages = PACKAGES))
