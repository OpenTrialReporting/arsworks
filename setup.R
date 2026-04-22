# setup.R ---------------------------------------------------------------------
#
# One-command entry point for arsworks. Auto-detects whether a full
# bootstrap is needed, then documents + loads all sub-packages, builds the
# example ADaM datasets + tables, and runs UAT checks.
#
# Usage:
#   source("setup.R")                  # smart default
#   setup(force_bootstrap = TRUE)      # force reinstall even if env looks OK
#   setup(skip_examples = TRUE)        # bootstrap + sync only
#   setup(skip_uat = TRUE)             # skip UAT checks
#
# What triggers an auto-bootstrap (any one is enough):
#   - A submodule directory is empty (fresh clone without --recurse-submodules)
#   - One of the five local packages is not installed
#   - An installed local package's version does not match its DESCRIPTION
#     (happens after a submodule pointer bump)
#   - renv reports missing CRAN packages (environment drift)
#
# Set environment variable ARSWORKS_SKIP_BOOTSTRAP=1 to bypass detection
# entirely (advanced; only if you know your environment is already correct).
# -----------------------------------------------------------------------------

setup <- function(force_bootstrap = FALSE,
                  skip_examples   = FALSE,
                  skip_uat        = FALSE) {

  ROOT <- tryCatch(
    normalizePath(rstudioapi::getActiveProject()),
    error = function(e) normalizePath(getwd())
  )

  PACKAGES <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

  message("arsworks setup")
  message(sprintf("  Project root: %s", ROOT))

  # ── Decide whether bootstrap is needed ──────────────────────────────────────

  skip_env <- identical(Sys.getenv("ARSWORKS_SKIP_BOOTSTRAP"), "1")

  reasons <- character(0)

  if (!skip_env) {
    # 1. Submodule dirs populated?
    empty_subs <- PACKAGES[!vapply(PACKAGES, function(p) {
      d <- file.path(ROOT, p)
      dir.exists(d) && length(list.files(d)) > 0L
    }, logical(1L))]
    if (length(empty_subs) > 0L) {
      reasons <- c(reasons, sprintf("empty submodule: %s",
                                    paste(empty_subs, collapse = ", ")))
    }

    # 2. Local packages installed?
    not_installed <- PACKAGES[!vapply(PACKAGES, function(p) {
      requireNamespace(p, quietly = TRUE)
    }, logical(1L))]
    if (length(not_installed) > 0L) {
      reasons <- c(reasons, sprintf("not installed: %s",
                                    paste(not_installed, collapse = ", ")))
    }

    # 3. Installed version matches DESCRIPTION?
    version_drift <- character(0)
    for (p in setdiff(PACKAGES, c(empty_subs, not_installed))) {
      desc_path <- file.path(ROOT, p, "DESCRIPTION")
      if (!file.exists(desc_path)) next
      desc_ver <- tryCatch(
        as.character(read.dcf(desc_path, fields = "Version")[1, 1]),
        error = function(e) NA_character_
      )
      inst_ver <- tryCatch(
        as.character(utils::packageVersion(p)),
        error = function(e) NA_character_
      )
      if (!is.na(desc_ver) && !is.na(inst_ver) && desc_ver != inst_ver) {
        version_drift <- c(version_drift,
                           sprintf("%s (installed %s, source %s)",
                                   p, inst_ver, desc_ver))
      }
    }
    if (length(version_drift) > 0L) {
      reasons <- c(reasons, sprintf("version drift: %s",
                                    paste(version_drift, collapse = "; ")))
    }

    # 4. renv: CRAN packages missing?
    renv_missing <- tryCatch({
      st <- renv::status(project = ROOT)
      # renv::status returns a list; look for missing/synchronized flags
      if (isFALSE(st$synchronized)) {
        mp <- st$library$missing %||% character(0)
        setdiff(mp, PACKAGES)  # ignore the five local ones
      } else {
        character(0)
      }
    }, error = function(e) character(0))
    if (length(renv_missing) > 0L) {
      reasons <- c(reasons, sprintf("CRAN drift (%d missing)",
                                    length(renv_missing)))
    }
  }

  need_bootstrap <- force_bootstrap || length(reasons) > 0L

  # ── Step 1: Bootstrap (conditional) ─────────────────────────────────────────

  if (need_bootstrap) {
    if (force_bootstrap) {
      message("\n── Bootstrap: forced by caller ──────────────────────────────")
    } else {
      message("\n── Bootstrap: required ──────────────────────────────────────")
      for (r in reasons) message("  - ", r)
    }
    source(file.path(ROOT, "bootstrap.R"), local = FALSE)
  } else if (skip_env) {
    message("\n  Bootstrap skipped (ARSWORKS_SKIP_BOOTSTRAP=1).")
  } else {
    message("\n  Bootstrap not needed — environment looks healthy.")
  }

  # ── Step 2: sync_and_load ───────────────────────────────────────────────────

  message("\n── Syncing & loading packages ──────────────────────────────────")
  source(file.path(ROOT, "sync_and_load.R"), local = FALSE)

  # ── Step 3: example tables (optional) ───────────────────────────────────────

  if (!skip_examples) {
    message("\n── Building example ADaM data + rendering all 6 shells ────────")
    source(file.path(ROOT, "data_table_examples.R"), local = FALSE)
  } else {
    message("\n  Example tables skipped (skip_examples = TRUE).")
  }

  # ── Step 4: UAT checks (optional; requires examples) ────────────────────────

  if (!skip_uat && !skip_examples) {
    message("\n── Running UAT checks ──────────────────────────────────────────")
    source(file.path(ROOT, "uat_checks.R"), local = FALSE)
  } else if (skip_uat) {
    message("\n  UAT checks skipped (skip_uat = TRUE).")
  } else {
    message("\n  UAT checks skipped (requires example tables).")
  }

  message("\n── setup() complete ────────────────────────────────────────────")
  invisible(list(
    bootstrapped = need_bootstrap,
    reasons      = reasons,
    examples     = !skip_examples,
    uat          = !skip_uat && !skip_examples
  ))
}

# Null-coalesce for pre-4.4 R sessions (renv::status() shape is list-of-lists).
`%||%` <- function(a, b) if (is.null(a)) b else a

# Auto-run with smart defaults when the file is sourced. Comment this line and
# call setup() directly if you want fine-grained control.
setup()
