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

dataframe1 <- data.frame(
  ndose   = c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10),
  usubjid = c("001", "002", "003","004", "005", "006", "007", "008","009", "010"),
  age     = c(34, 51, 47,34, 51, 47,34, 51, 47, 47),
  sex     = c("M", "F", "F","M", "F", "F","M", "F", "M","M"),
  trt     = c("Placebo", "Drug A", "Drug A","Placebo", "Drug A", "Drug A","Placebo", "Drug A", "Drug A", "Drug A")
)


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
calc_mode(c(1, 1, 2, 2, 3))         # result when more than one qualifying value for mode -> ties: 1 2
calc_mode(c(4, 8, 15))              # result when no mode-> NA
calc_mean(c(2, NA, 4))              # result when missing values without requesting they be removed by declaring na.rm=TRUE->NA
calc_mean(c(2, NA, 4), na.rm = TRUE) #result when missing values present in vector but removed-> 3
try(calc_mean("a"))                 # informative error when invalid input applied to function

# Beyond the brief: data frames, overall or by group (like PROC MEANS + CLASS)
adsl <- pharmaverseadam::adsl
describe_stats(adsl, vars = "AGE")
describe_stats(adsl, vars = "AGE", by = "TRT01A")
describe_stats(adsl, vars = "AGE", by = c("TRT01A", "SEX"), type = 2)  # SAS quartiles
describe_stats(pharmaverseadam::adsl, vars = "AGE", by = "TRT01P")

table1<-describe_stats(pharmaverseadam::adsl, vars = "AGE", by = "TRT01P")

table2<-describe_stats(dataframe1, vars = "age", by = "trt")

