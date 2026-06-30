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

# ── 1.5 Heal installed sub-packages when they drift from source ───────────────
#
# Two failure modes are covered:
#
# 1. arstlf-specific: R 4.5's libdeflate-backed lazy-load DB miscompresses
#    arstlf's byte-compiled functions, so any access fails with "internal error
#    1 in R_decompress1 with libdeflate". arstlf/DESCRIPTION carries
#    ByteCompile: no, but some install paths ignore it — we re-probe by
#    force-decompressing every namespace entry and reinstall with
#    --no-byte-compile if any entry fails.
#
# 2. Help-DB drift (any package): roxygen reads @inheritParams targets from the
#    INSTALLED help DB of the dependency, not its source. If a sub-package gains
#    a new function (and a new man/*.Rd) but its renv-installed copy is older,
#    the document() step below emits "@param refers to unavailable topic
#    pkg::fn" warnings. We compare source man/ topics against the installed
#    help/AnIndex and reinstall the dependency when source has topics the
#    installed copy is missing.
# Find the renv project library explicitly. We do NOT use find.package() to
# locate the installed copy: when a package has been dev-loaded via load_all,
# pkgload shims .libPaths() to make find.package() return the SOURCE directory
# — and unlink()-ing that would wipe the user's git submodule working tree.
.renv_lib <- {
  lp <- .libPaths()
  hit <- lp[grepl("renv[\\\\/]library", lp)]
  if (length(hit)) hit[[1L]] else lp[[1L]]
}

.reinstall_pkg <- function(pkg, inst, reason, extra_args = character(0)) {
  # SAFETY: never unlink any sub-package source dir. (Discovery uses .renv_lib
  # explicitly, so inst should already be the installed copy — this is
  # defence-in-depth against a future regression resurrecting find.package().)
  inst_norm <- normalizePath(inst, mustWork = FALSE)
  src_norms <- vapply(PACKAGES,
                      function(p) normalizePath(file.path(ROOT, p), mustWork = FALSE),
                      character(1L))
  if (inst_norm %in% src_norms) {
    warning(sprintf(
      "heal[%s]: refusing to unlink %s — that's a source tree, not an install",
      pkg, inst_norm), call. = FALSE)
    return(invisible())
  }
  message(sprintf("  HEAL  %-10s  (%s — reinstalling)", pkg, reason))

  lib  <- dirname(inst)
  Rbin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")

  # Install-then-swap: build the fresh copy into a staging library FIRST, and
  # only replace the existing install once it succeeds. The previous behaviour
  # unlink()ed the install before reinstalling, so any failed reinstall (e.g.
  # the old R.exe-not-found bug) left the package deleted. The stage lives
  # inside `lib` so it shares a filesystem with the target and the final move
  # is atomic; the dependency search path (R_LIBS=lib) lets the install's
  # test-load resolve sibling sub-packages already in `lib`.
  stage <- file.path(lib, paste0(".heal-stage-", pkg))
  unlink(stage, recursive = TRUE, force = TRUE)
  dir.create(stage, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)

  status <- system2(
    Rbin,
    c("CMD", "INSTALL", extra_args,
      paste0("--library=", shQuote(stage)),
      shQuote(file.path(ROOT, pkg))),
    env = paste0("R_LIBS=", lib),
    stdout = FALSE, stderr = FALSE
  )

  staged <- file.path(stage, pkg)
  if (!identical(status, 0L) || !dir.exists(staged)) {
    warning(sprintf("%s reinstall failed (status %s) — keeping existing install",
                    pkg, status), call. = FALSE)
    return(invisible())
  }

  # Fresh copy is ready: swap it in with rollback safety. Move the old install
  # aside (atomic rename), move the new one into place, then drop the backup;
  # if the second move fails, restore the backup so we never end up with no
  # installed copy.
  try(unloadNamespace(pkg), silent = TRUE)
  backup <- paste0(inst, ".heal-old")
  unlink(backup, recursive = TRUE, force = TRUE)
  if (dir.exists(inst) && !file.rename(inst, backup)) {
    warning(sprintf("%s: could not move existing install aside — keeping it",
                    pkg), call. = FALSE)
    return(invisible())
  }
  if (file.rename(staged, inst)) {
    unlink(backup, recursive = TRUE, force = TRUE)
  } else if (dir.exists(backup) && !dir.exists(inst)) {
    file.rename(backup, inst)            # restore previous install
    warning(sprintf("%s: could not install healed copy — kept previous install",
                    pkg), call. = FALSE)
  }
  invisible()
}

for (pkg in PACKAGES) {
  src <- file.path(ROOT, pkg)
  if (!dir.exists(src)) next
  inst <- file.path(.renv_lib, pkg)
  if (!dir.exists(inst)) next  # not installed yet — load_all below will handle

  # Help-DB drift: does the installed help index cover every source .Rd topic?
  src_topics <- sub("\\.Rd$", "",
                    list.files(file.path(src, "man"), pattern = "\\.Rd$"))
  idx_path <- file.path(inst, "help", "AnIndex")
  inst_topics <- if (file.exists(idx_path)) {
    tryCatch(read.table(idx_path, sep = "\t", header = FALSE, quote = "",
                        fill = TRUE, stringsAsFactors = FALSE)[[1]],
             error = function(e) character(0))
  } else character(0)
  missing <- setdiff(src_topics, inst_topics)
  if (length(missing)) {
    .reinstall_pkg(pkg, inst,
                   sprintf("help DB missing %d topic(s)", length(missing)),
                   extra_args = if (pkg == "arstlf") "--no-byte-compile" else character(0))
    next
  }

  # arstlf-only: confirm the lazy-load DB is readable end-to-end.
  if (pkg == "arstlf") {
    ok <- tryCatch({
      loadNamespace("arstlf")
      ns <- asNamespace("arstlf")
      all(vapply(ls(ns, all.names = TRUE), function(n) {
        tryCatch({ force(get(n, envir = ns)); TRUE },
                 error = function(e) FALSE)
      }, logical(1L)))
    }, error = function(e) FALSE)
    if (!isTRUE(ok))
      .reinstall_pkg(pkg, inst, ".rdb corrupt", extra_args = "--no-byte-compile")
  }
}
rm(.reinstall_pkg, .renv_lib)

# ── 2. Document + reload all packages in dependency order ─────────────────────

message("\n── Documenting packages ────────────────────────────────────────────────")

for (pkg in PACKAGES) {
  path <- file.path(ROOT, pkg)
  if (!dir.exists(path)) next
  # Unload everything first so document() resolves @inheritParams /
  # [pkg::topic()] links via each dependency's INSTALLED help DB rather than
  # the in-memory dev namespace left over from a prior load_all (which has no
  # help info and triggers "refers to unavailable topic" warnings). Iterate in
  # reverse dependency order so dependents unload before their dependencies.
  for (p in rev(PACKAGES)) try(pkgload::unload(p), silent = TRUE)
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
