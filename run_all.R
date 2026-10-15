# =============================================================================
# run_all.R - run every R deliverable from scratch and log the results
#
# Usage: set the working directory to the repository root, then
#   source("run_all.R")
# A full log is written to run_all_log.txt.
# =============================================================================

if (!dir.exists("question_1")) {
  stop("Please set the working directory to the repository root first, e.g.\n",
       "  setwd(\"path/to/repo\")", call. = FALSE)
}

log_file <- "run_all_log.txt"
log_con <- file(log_file, open = "wt")
sink(log_con, split = TRUE)
sink(log_con, type = "message")

step <- function(label, expr) {
  cat("\n", strrep("=", 78), "\n", label, "\n", strrep("=", 78), "\n", sep = "")
  start <- Sys.time()
  ok <- tryCatch(
    withCallingHandlers(
      { force(expr); TRUE },
      warning = function(w) {
        cat("WARNING: ", conditionMessage(w), "\n", sep = "")
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      cat("ERROR: ", conditionMessage(e), "\n", sep = "")
      FALSE
    }
  )
  cat(sprintf("--> %s (%.1fs)\n", if (ok) "OK" else "FAILED",
              as.numeric(difftime(Sys.time(), start, units = "secs"))))
  invisible(ok)
}

# Run a script in its own environment so questions cannot affect each other
run_script <- function(path) {
  source(path, local = new.env(parent = globalenv()), echo = FALSE)
}

# -----------------------------------------------------------------------------
step("Install missing packages", {
  pkgs <- c(
    "devtools", "roxygen2", "testthat",
    "dplyr", "stringr", "ggplot2", "scales", "gt", "gtsummary",
    "admiral", "sdtm.oak", "pharmaverseraw", "pharmaversesdtm", "pharmaverseadam"
  )
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    cat("Installing:", paste(missing, collapse = ", "), "\n")
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
  for (p in pkgs) cat(sprintf("  %-16s %s\n", p, as.character(packageVersion(p))))
})

# -----------------------------------------------------------------------------
pkg <- file.path("question_1", "descriptive_stats")

# Functions with the package's names in the global environment (e.g. from
# sourcing a draft script) mask the package's own versions.
clash <- intersect(
  ls(globalenv()),
  c("calc_mean", "calc_median", "calc_mode", "calc_q1", "calc_q3", "calc_iqr")
)
if (length(clash)) {
  cat("NOTE: ", paste(clash, collapse = ", "), " found in the global environment. ",
      "Clear them first with rm(", paste(clash, collapse = ", "), ").\n", sep = "")
}

step("Q1a: document (roxygen2 -> man/ and NAMESPACE)", devtools::document(pkg))

step("Q1b: unit tests", {
  res <- as.data.frame(devtools::test(pkg, reporter = "summary", stop_on_failure = FALSE))
  cat("Tests:", sum(res$nb), " Failed:", sum(res$failed), " Errors:", sum(res$error),
      " Skipped:", sum(res$skipped), "\n")
  if (sum(res$failed) + sum(res$error) > 0) stop("some tests failed")
})

step("Q1c: R CMD check", {
  # On Windows, R CMD check needs the Rtools version that matches the R version
  if (!pkgbuild::has_build_tools(debug = FALSE)) {
    stop("Rtools for R ", getRversion(), " not found: install it from ",
         "https://cran.r-project.org/bin/windows/Rtools/ and restart R")
  }
  chk <-devtools::check(pkg, error_on = "never", quiet = TRUE, document = FALSE)
  cat("Errors:", length(chk$errors), " Warnings:", length(chk$warnings),
      " Notes:", length(chk$notes), "\n")
  for (x in c(chk$errors, chk$warnings, chk$notes)) cat("\n", x, "\n")
})

step("Q1d: install and run the example", {
  # Installed with base R's installer rather than devtools::install(): in this
  # logged session, devtools::install() (which loads {pak}) left R unable to
  # write files in the later steps ("Bad file descriptor"). question_1.R keeps
  # devtools::install(), the usual call when developing a package.
  if ("descriptiveStats" %in% loadedNamespaces()) pkgload::unload("descriptiveStats")
  install.packages(pkg, repos = NULL, type = "source", quiet = TRUE)
  library(descriptiveStats)
  data <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)
  # Namespace-qualified, so draft functions of the same name cannot mask them
  print(c(
    mean   = descriptiveStats::calc_mean(data),
    median = descriptiveStats::calc_median(data),
    mode   = descriptiveStats::calc_mode(data),
    q1     = descriptiveStats::calc_q1(data),
    q3     = descriptiveStats::calc_q3(data),
    iqr    = descriptiveStats::calc_iqr(data)
  ))
})

# -----------------------------------------------------------------------------
step("Q2: SDTM DS domain", run_script(file.path("question_2_sdtm", "02_create_ds_domain.R")))
step("Q3: ADaM ADSL", run_script(file.path("question_3_adam", "create_adsl.R")))
step("Q4.1: AE summary table", run_script(file.path("question_4_tlg", "01_create_ae_summary_table.R")))
step("Q4.2: AE visualisations", run_script(file.path("question_4_tlg", "02_create_visualizations.R")))
step("Q4.3: AE listing", run_script(file.path("question_4_tlg", "03_create_listings.R")))
step("Data for Q5/Q6: export adae.csv", run_script(file.path("data", "export_adae.R")))

# -----------------------------------------------------------------------------
step("Output files", {
  outs <- list.files(
    c("question_2_sdtm/output", "question_3_adam/output", "question_4_tlg/output", "data"),
    full.names = TRUE
  )
  print(data.frame(file = outs, kb = round(file.size(outs) / 1024, 1)))
})

step("Session info", print(sessionInfo()))

sink(type = "message")
sink()
close(log_con)
cat("Done. See", log_file, "\n")
