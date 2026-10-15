# ---------------------------------------------------------------------------
# Question 1: build, test and demonstrate the descriptiveStats package
#
# Run from the repository root (the folder containing question_1/).
# ---------------------------------------------------------------------------

pkg_path <- "question_1/descriptive_stats"

# 1. Generate documentation (man/*.Rd and NAMESPACE) from the roxygen comments
devtools::document(pkg_path)

# 2. Run the unit tests
devtools::test(pkg_path)

# 3. Full package check (should report 0 errors, 0 warnings, 0 notes)
devtools::check(pkg_path)

# 4. Install and use
devtools::install(pkg_path, upgrade = FALSE)
library(descriptiveStats)

data <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)

calc_mean(data)    # 4.3
calc_median(data)  # 4.5
calc_mode(data)    # 5
calc_q1(data)      # 2.25 (R default, type 7)
calc_q3(data)      # 5
calc_iqr(data)     # 2.75

# SAS-style quartiles (PCTLDEF=5)
calc_q1(data, type = 2)  # 2
calc_q3(data, type = 2)  # 5

# Edge cases
calc_mode(c(1, 1, 2, 2, 3))         # ties: 1 2
calc_mode(c(4, 8, 15))              # no mode: NA
calc_mean(c(2, NA, 4))              # NA
calc_mean(c(2, NA, 4), na.rm = TRUE) # 3
try(calc_mean("a"))                 # informative error
