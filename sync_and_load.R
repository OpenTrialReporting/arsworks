# sync_and_load.R -------------------------------------------------------------
#
# Pulls the latest commits from all five sub-package repos and reloads them
# into the current R session using devtools::load_all().
#
# Usage:
#   source("sync_and_load.R")
#
# Prerequisites:
#   - git must be on PATH
#   - You must be inside the arsworks/ directory (or adjust ROOT below)
#   - Each sub-package must have its own .git/ and an 'origin' remote

ROOT <- normalizePath(dirname(rstudioapi::getSourceEditorContext()$path))

PACKAGES <- c("arscore", "arsshells", "arsresult", "arstlf", "ars")

# ── 1. Pull latest from each sub-package repo ─────────────────────────────────

message("\n── Pulling latest from sub-package repos ──────────────────────────────")

pull_results <- vapply(PACKAGES, function(pkg) {
  path <- file.path(ROOT, pkg)
  if (!dir.exists(file.path(path, ".git"))) {
    message(sprintf("  SKIP  %s  (no .git — running as submodule pointer only)", pkg))
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

# ── 2. Reload all packages in dependency order ────────────────────────────────

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
