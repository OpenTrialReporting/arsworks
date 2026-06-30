# bootstrap.R -----------------------------------------------------------------
#
# One-shot setup for a fresh clone of arsworks.
#
# What it does:
#   1. Initialises git submodules (handles clones done without --recurse-submodules)
#   2. Runs renv::restore() to install all pinned CRAN dependencies. The six
#      local packages are NOT tracked in renv.lock — they're listed in renv's
#      ignored.packages (renv/settings.json) — so renv leaves them alone.
#   3. Installs the six local sub-packages in dependency order
#
# Usage (run once, after cloning):
#   source("bootstrap.R")
#
# After bootstrap, start each working session with:
#   source("sync_and_load.R")
# -----------------------------------------------------------------------------

# ── Resolve project root ──────────────────────────────────────────────────────

ROOT <- tryCatch(
  normalizePath(rstudioapi::getActiveProject()),
  error = function(e) normalizePath(getwd())
)

message("arsworks bootstrap")
message(sprintf("  Project root: %s\n", ROOT))

# ── Step 1: Git submodules ────────────────────────────────────────────────────

message("── Step 1: Git submodules ───────────────────────────────────────────────")

submodules <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

populated <- vapply(submodules, function(pkg) {
  path <- file.path(ROOT, pkg)
  dir.exists(path) && length(list.files(path)) > 0L
}, logical(1L))

if (all(populated)) {
  message("  All submodule directories populated — skipping init.")
} else {
  missing <- submodules[!populated]
  message("  Uninitialised submodules: ", paste(missing, collapse = ", "))
  message("  Running: git submodule update --init --recursive")

  ret <- system2("git", c("-C", ROOT, "submodule", "update", "--init", "--recursive"))

  if (ret != 0L) {
    stop(paste(
      "git submodule update failed (exit code ", ret, ").\n",
      "  - Ensure git is on your PATH.\n",
      "  - Ensure you have network access to github.com.\n",
      "  - If behind a proxy, configure: git config --global http.proxy <proxy>"
    ))
  }

  # Verify
  still_empty <- submodules[!vapply(submodules, function(pkg) {
    length(list.files(file.path(ROOT, pkg))) > 0L
  }, logical(1L))]

  if (length(still_empty) > 0L) {
    stop("Submodule directories still empty after init: ",
         paste(still_empty, collapse = ", "),
         "\nCheck the output above for git errors.")
  }

  message("  All submodules initialised successfully.")
}

# ── Step 2: renv::restore() ──────────────────────────────────────────────────
#
# The six local sub-packages are NOT recorded in renv.lock — they're listed in
# renv's ignored.packages (renv/settings.json) and built from the submodule
# sources in Step 3. So a plain restore only installs the pinned CRAN
# dependencies. The setdiff below is a harmless safeguard in case an older
# lockfile still lists a local package.

message("\n── Step 2: Restoring CRAN packages via renv ────────────────────────────")
message("  (The six local packages are not in the lockfile; installed in Step 3.)\n")

lock_path <- file.path(ROOT, "renv.lock")

if (!file.exists(lock_path)) {
  stop("renv.lock not found at: ", lock_path)
}

local_pkgs <- c("ars", "arscore", "arsshells", "arsresult", "arstlf", "arsstudio")
lock        <- renv::lockfile_read(file = lock_path)
cran_pkgs   <- setdiff(names(lock$Packages), local_pkgs)

renv::restore(packages = cran_pkgs, prompt = FALSE)

# ── Step 3: Install local packages in dependency order ───────────────────────
#
# Dependency order:
#   arscore  →  arsshells, arsresult  →  arstlf  →  ars  →  arsstudio

message("\n── Step 3: Installing local packages ───────────────────────────────────")

install_order <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

for (pkg in install_order) {
  path <- file.path(ROOT, pkg)

  if (!dir.exists(path)) {
    stop(sprintf(
      "Package directory not found: %s\nDid Step 1 (submodule init) complete successfully?",
      path
    ))
  }

  message(sprintf("  Installing %-12s from ./%s/ ...", pkg, pkg))

  # Regenerate man pages, NAMESPACE, and Collate: from the current R/ sources
  # before install. Without this, a newly added R file that isn't yet in
  # Collate: will cause R CMD INSTALL to fail.
  tryCatch(
    devtools::document(path, quiet = TRUE),
    error = function(e) {
      stop(sprintf("Failed to document %s:\n  %s", pkg, conditionMessage(e)))
    }
  )

  tryCatch(
    devtools::install(path, quiet = TRUE, upgrade = FALSE),
    error = function(e) {
      stop(sprintf("Failed to install %s:\n  %s", pkg, conditionMessage(e)))
    }
  )

  message(sprintf("  OK  %s", pkg))
}

# ── Done ──────────────────────────────────────────────────────────────────────

message("\n── Bootstrap complete ───────────────────────────────────────────────────")
message("  All packages installed. Start your session with:")
message("")
message('    source("sync_and_load.R")')
message('    source("data_table_examples.R")')
message("")
