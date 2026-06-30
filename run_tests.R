#!/usr/bin/env Rscript
# CI test runner for the arsworks suite.
#
# Runs testthat for every sub-package and exits NON-ZERO if any test fails or
# errors, or if a package cannot be loaded/tested at all. This replaces the
# previous `grep -i "failed" test-results.log` gate, which let crashes report
# success: when `devtools::test()` aborted with "there is no package called
# 'devtools'", that text contained no "failed", so the build went green while
# nothing was actually tested.
#
# Run inside the Docker image:  docker run --entrypoint Rscript <image> run_tests.R

suppressMessages(library(testthat))

pkgs <- c("arscore", "arsshells", "arsresult", "arstlf", "ars", "arsstudio")

total_fail   <- 0L
summary_rows <- character(0)

for (p in pkgs) {
  cat(sprintf("\n========== testing %s ==========\n", p))
  res <- tryCatch(
    devtools::test(p, stop_on_failure = FALSE),
    error = function(e) {
      cat(sprintf("ERROR: %s could not be tested: %s\n", p, conditionMessage(e)))
      e
    }
  )

  if (inherits(res, "error")) {
    total_fail   <- total_fail + 1L
    summary_rows <- c(summary_rows, sprintf("  %-10s LOAD/RUN ERROR", p))
    next
  }

  df    <- as.data.frame(res)
  nfail <- sum(df$failed) + sum(df$error)            # df$error is logical
  total_fail <- total_fail + nfail
  summary_rows <- c(
    summary_rows,
    sprintf("  %-10s FAIL=%d  WARN=%d  SKIP=%d  PASS=%d",
            p, nfail, sum(df$warning), sum(df$skipped), sum(df$passed))
  )
}

cat("\n========== SUITE TEST SUMMARY ==========\n")
cat(paste(summary_rows, collapse = "\n"), "\n")
cat(sprintf("Total failing/errored: %d\n", total_fail))

if (total_fail > 0L) {
  quit(status = 1L)
}
cat("All suite tests passed.\n")
