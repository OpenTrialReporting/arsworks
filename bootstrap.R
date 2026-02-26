# bootstrap.R -----------------------------------------------------------------
#
# One-shot setup for a fresh clone of arsworks.
#
# What it does:
#   1. Initialises git submodules (handles clones done without --recurse-submodules)
#   2. Patches renv.lock so the local 'ars' package is not fetched from CRAN
#      (there is an unrelated CRAN package called 'ars'; this step prevents
#      renv::restore() from failing on a version-not-found error)
#   3. Runs renv::restore() to install all pinned CRAN dependencies
#   4. Installs the five local sub-packages in dependency order
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

submodules <- c("arscore", "arsshells", "arsresult", "arstlf", "ars")

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

# ── Step 2: Patch renv.lock ───────────────────────────────────────────────────
#
# The 'ars' entry in renv.lock can end up with "Source": "Repository",
# which causes renv::restore() to look for ars 0.1.0 on CRAN — where it
# does not exist (a different, unrelated package named 'ars' lives there).
# All five local packages should have "Source": "unknown".

message("\n── Step 2: Patching renv.lock ───────────────────────────────────────────")

lock_path <- file.path(ROOT, "renv.lock")

if (!file.exists(lock_path)) {
  stop("renv.lock not found at: ", lock_path)
}

lock_lines <- readLines(lock_path, warn = FALSE)

# Locate the "ars" package block (exact key match, not arscore/arsshells/etc.)
ars_block_start <- grep('^    "ars": \\{', lock_lines)

patched <- FALSE

if (length(ars_block_start) > 0L) {
  # Scan forward from that line for the first "Source" field within ~10 lines
  scan_range <- seq(ars_block_start[1] + 1L, min(ars_block_start[1] + 10L, length(lock_lines)))
  source_line <- scan_range[grepl('"Source"', lock_lines[scan_range])][1]

  if (!is.na(source_line) && grepl('"Repository"', lock_lines[source_line])) {
    lock_lines[source_line] <- sub('"Repository"', '"unknown"', lock_lines[source_line])
    writeLines(lock_lines, lock_path)
    message("  Fixed: ars Source changed from 'Repository' to 'unknown'.")
    patched <- TRUE
  }
}

if (!patched) {
  message("  OK: ars Source already set to 'unknown' — no changes needed.")
}

# ── Step 3: renv::restore() ──────────────────────────────────────────────────

message("\n── Step 3: Restoring CRAN packages via renv ────────────────────────────")
message("  (The five local packages are skipped here; installed in Step 4.)\n")

renv::restore(prompt = FALSE)

# ── Step 4: Install local packages in dependency order ───────────────────────
#
# Dependency order:
#   arscore  →  arsshells, arsresult  →  arstlf  →  ars

message("\n── Step 4: Installing local packages ───────────────────────────────────")

install_order <- c("arscore", "arsshells", "arsresult", "arstlf", "ars")

for (pkg in install_order) {
  path <- file.path(ROOT, pkg)

  if (!dir.exists(path)) {
    stop(sprintf(
      "Package directory not found: %s\nDid Step 1 (submodule init) complete successfully?",
      path
    ))
  }

  message(sprintf("  Installing %-12s from ./%s/ ...", pkg, pkg))

  tryCatch(
    devtools::install(path, quiet = TRUE, upgrade = "never"),
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
