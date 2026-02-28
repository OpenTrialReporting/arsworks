# uat_checks.R ---------------------------------------------------------------
#
# §22.3 / §22.1 — User Acceptance Testing checks for all 6 shells.
#
# Run AFTER data_table_examples.R has been sourced (all 6 ard_* objects present).
# Also performs §22.1 NaN/NA raw_value diagnosis across every ARD.
#
# source("uat_checks.R")
# ----------------------------------------------------------------------------

library(dplyr)

# ── Helpers ------------------------------------------------------------------

.uat_ard_check <- function(name, ard_result) {
  ard   <- ard_result$ard
  shell <- ard_result$shell

  # 1. Raw-value pathology: NA-string, NaN-string, NaN-numeric
  na_str_rows  <- ard[!is.na(ard$raw_value) & ard$raw_value %in% c("NA", "NaN", "Inf", "-Inf"), ]
  num_vals     <- suppressWarnings(as.numeric(ard$raw_value))
  nan_num_rows <- ard[!is.na(num_vals) & is.nan(num_vals), ]

  # 2. Unresolved N=xx column headers
  col_hdrs      <- unlist(shell@col_headers)
  unresolved_hdr <- col_hdrs[grepl("N=xx", col_hdrs, fixed = TRUE)]

  # 3. Zero N with non-NA percentage (should be suppressed)
  zero_n  <- ard[!is.na(ard$raw_value) & ard$raw_value == "0" &
                   ard$operation_id == "OP_N", ]
  zero_pct_present <- if (nrow(zero_n) > 0L) {
    # For each zero-N analysis, check if OP_N_PCT is NA or 0 (correct) vs numeric (wrong)
    checks <- vapply(seq_len(nrow(zero_n)), function(i) {
      pct_row <- ard[ard$analysis_id == zero_n$analysis_id[i] &
                       ard$operation_id == "OP_N_PCT", ]
      if (nrow(pct_row) == 0L) return(FALSE)
      pv <- suppressWarnings(as.numeric(pct_row$raw_value[1]))
      !is.na(pv) && pv != 0
    }, logical(1))
    sum(checks)
  } else 0L

  list(
    shell          = name,
    ard_rows       = nrow(ard),
    na_string      = nrow(na_str_rows),
    nan_numeric    = nrow(nan_num_rows),
    unresolved_hdr = length(unresolved_hdr),
    zero_n_total   = nrow(zero_n),
    pct_not_suppressed = zero_pct_present,
    na_ops         = if (nrow(na_str_rows)  > 0) unique(na_str_rows$operation_id)  else character(0),
    nan_ops        = if (nrow(nan_num_rows) > 0) unique(nan_num_rows$operation_id) else character(0)
  )
}

.uat_render_check <- function(name, ard_result) {
  gt_tbl <- tryCatch(
    render(ard_result, backend = "tfrmt"),
    error = function(e) { cat("  ERROR rendering", name, ":", conditionMessage(e), "\n"); NULL }
  )
  if (is.null(gt_tbl)) return(list(shell = name, render_ok = FALSE, row_count = NA_integer_,
                                    na_text = NA_integer_, hdr_na = NA_integer_))

  # Count rendered body rows (each column in ._body; use nrow of ._body tibble)
  row_count <- tryCatch(nrow(gt_tbl[["_body"]]), error = function(e) NA_integer_)

  # Scan HTML for ">NA<" (literal NA text in a cell)
  html <- tryCatch(as.character(gt::as_raw_html(gt_tbl)), error = function(e) "")
  # Count ALL occurrences (gregexpr returns -1 when no match)
  na_matches  <- gregexpr(">\\s*NA\\s*<", html, perl = TRUE)[[1]]
  na_text     <- if (na_matches[1] == -1L) 0L else length(na_matches)

  # Count ALL N=xx occurrences (not just "any line matches")
  hdr_matches <- gregexpr("N=xx", html, fixed = TRUE)[[1]]
  hdr_na      <- if (hdr_matches[1] == -1L) 0L else length(hdr_matches)

  list(shell = name, render_ok = TRUE, row_count = row_count,
       na_text = na_text, hdr_na = hdr_na, gt = gt_tbl)
}

# ── Run checks ---------------------------------------------------------------

shells <- list(
  "T-DM-01" = ard_dm01,
  "T-DS-01" = ard_ds01,
  "T-AE-01" = ard_ae01,
  "T-AE-02" = ard_ae02,
  "T-LB-01" = ard_lb01,
  "T-LB-02" = ard_lb02
)

cat("\n╔══════════════════════════════════════════════════════╗\n")
cat("║         §22 UAT — ARD-level checks                  ║\n")
cat("╚══════════════════════════════════════════════════════╝\n\n")

ard_results <- lapply(names(shells), function(nm) .uat_ard_check(nm, shells[[nm]]))

# Summary table
cat(sprintf("%-10s  %6s  %9s  %11s  %13s  %6s  %18s\n",
            "Shell", "Rows", "NA-string", "NaN-numeric", "Unresol.Hdr", "Zero-N", "Pct-not-suppressed"))
cat(strrep("-", 90), "\n")
for (r in ard_results) {
  flag <- if (r$na_string > 0 || r$nan_numeric > 0 || r$unresolved_hdr > 0 || r$pct_not_suppressed > 0) " ⚠" else " ✓"
  cat(sprintf("%-10s  %6d  %9d  %11d  %13d  %6d  %18d  %s\n",
              r$shell, r$ard_rows, r$na_string, r$nan_numeric,
              r$unresolved_hdr, r$zero_n_total, r$pct_not_suppressed, flag))
}

# Detail on any problems found
for (r in ard_results) {
  if (r$na_string > 0)
    cat(sprintf("\n  [%s] NA-string ops: %s\n", r$shell, paste(r$na_ops, collapse = ", ")))
  if (r$nan_numeric > 0)
    cat(sprintf("\n  [%s] NaN-numeric ops: %s\n", r$shell, paste(r$nan_ops, collapse = ", ")))
}

cat("\n╔══════════════════════════════════════════════════════╗\n")
cat("║         §22 UAT — Render checks (gt output)         ║\n")
cat("╚══════════════════════════════════════════════════════╝\n\n")

render_results <- lapply(names(shells), function(nm) .uat_render_check(nm, shells[[nm]]))

cat(sprintf("%-10s  %10s  %9s  %10s  %12s\n",
            "Shell", "Render OK", "Row Count", "\"NA\" text", "Unresol.Hdr"))
cat(strrep("-", 60), "\n")
for (r in render_results) {
  flag <- if (!isTRUE(r$render_ok) || r$na_text > 0 || r$hdr_na > 0) " ⚠" else " ✓"
  cat(sprintf("%-10s  %10s  %9s  %10d  %12d  %s\n",
              r$shell,
              if (isTRUE(r$render_ok)) "YES" else "NO",
              if (is.na(r$row_count)) "?" else as.character(r$row_count),
              if (is.na(r$na_text)) 0L else r$na_text,
              if (is.na(r$hdr_na)) 0L else r$hdr_na,
              flag))
}

# ── Stash render results for inspection -----------------------------------------
gt_dm01 <- render_results[[1]]$gt
gt_ds01 <- render_results[[2]]$gt
gt_ae01 <- render_results[[3]]$gt
gt_ae02 <- render_results[[4]]$gt
gt_lb01 <- render_results[[5]]$gt
gt_lb02 <- render_results[[6]]$gt

cat("\n\nRendered gt tables stored as: gt_dm01, gt_ds01, gt_ae01, gt_ae02, gt_lb01, gt_lb02\n")
cat("UAT checks complete.\n")
