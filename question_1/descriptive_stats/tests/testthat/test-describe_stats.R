# Small data set with known answers:
#   arm A: ages 70, 50, 70   (rows 2, 3, 5)
#   arm B: ages 60, 80       (rows 1, 4)
#   arm NA: age 65           (row 6)
trial <- data.frame(
  arm = c("B", "A", "A", "B", "A", NA),
  sex = c("F", "M", "F", "F", "M", "M"),
  age = c(60, 70, 50, 80, 70, 65),
  wt  = c(70, NA, 60, 90, 80, 75),
  stringsAsFactors = FALSE
)

stat_columns <- c("variable", "n", "n_missing", "mean", "median", "mode", "q1", "q3", "iqr")

test_that("whole data frame: one row per numeric column", {
  res <- describe_stats(trial)
  expect_s3_class(res, "data.frame")
  expect_named(res, stat_columns)
  expect_equal(res$variable, c("age", "wt"))
  expect_equal(res$n, c(6, 5))
  expect_equal(res$n_missing, c(0, 1))
})

test_that("results match the vector functions", {
  res <- describe_stats(trial, vars = "wt")
  x <- trial$wt
  expect_equal(res$mean, calc_mean(x, na.rm = TRUE))
  expect_equal(res$median, calc_median(x, na.rm = TRUE))
  expect_equal(res$q1, calc_q1(x, na.rm = TRUE))
  expect_equal(res$q3, calc_q3(x, na.rm = TRUE))
  expect_equal(res$iqr, calc_iqr(x, na.rm = TRUE))
})

test_that("by group: sorted groups, missing group kept, values match subsets", {
  res <- describe_stats(trial, vars = "age", by = "arm")
  expect_named(res, c("arm", stat_columns))
  expect_equal(res$arm, c("A", "B", NA))
  expect_equal(res$n, c(3, 2, 1))
  expect_equal(res$mean[1], calc_mean(c(70, 50, 70)))
  expect_equal(res$median[2], calc_median(c(60, 80)))
  expect_equal(res$mode[1], "70")
  expect_equal(res$mean[3], 65)
})

test_that("two grouping columns: first column varies slowest", {
  res <- describe_stats(trial, vars = "age", by = c("arm", "sex"))
  expect_equal(paste(res$arm, res$sex), c("A F", "A M", "B F", "NA M"))
  expect_equal(res$n, c(1, 2, 2, 1))
})

test_that("several variables by group: one row per group and variable", {
  res <- describe_stats(trial, vars = c("age", "wt"), by = "arm")
  expect_equal(nrow(res), 6)
  expect_equal(res$variable, rep(c("age", "wt"), 3))
  # arm A weight: NA, 60, 80
  a_wt <- res[res$arm %in% "A" & res$variable == "wt", ]
  expect_equal(a_wt$n, 2)
  expect_equal(a_wt$n_missing, 1)
  expect_equal(a_wt$mean, 70)
})

test_that("factor grouping columns keep their level order", {
  df <- trial
  df$arm <- factor(df$arm, levels = c("B", "A"))
  res <- describe_stats(df, vars = "age", by = "arm")
  expect_equal(as.character(res$arm), c("B", "A", NA))
})

test_that("na.rm = FALSE gives NA statistics when values are missing", {
  res <- describe_stats(trial, vars = "wt", na.rm = FALSE)
  expect_true(is.na(res$mean))
  expect_equal(res$n_missing, 1)
})

test_that("a group with no values gives NA and a single warning", {
  df <- data.frame(g = c("a", "a", "b", "c"), x = c(1, 2, NA, NA))
  expect_warning(
    res <- describe_stats(df, vars = "x", by = "g"),
    "2 group/variable combinations had no non-missing values"
  )
  expect_equal(res$n, c(2, 0, 0))
  expect_true(all(is.na(res$mean[2:3])))
})

test_that("mode reports ties and no mode", {
  expect_equal(describe_stats(data.frame(x = c(1, 1, 2, 2, 3)))$mode, "1, 2")
  expect_true(is.na(describe_stats(data.frame(x = c(1, 2, 3)))$mode))
})

test_that("type is passed to the quartiles", {
  res <- describe_stats(trial, vars = "age", type = 2)
  expect_equal(res$q1, calc_q1(trial$age, type = 2))
  expect_equal(res$iqr, calc_iqr(trial$age, type = 2))
})

test_that("integer columns are summarised", {
  res <- describe_stats(data.frame(x = 1:4))
  expect_equal(res$mean, 2.5)
})

test_that("empty data frames", {
  expect_warning(res <- describe_stats(data.frame(x = numeric(0))), "no non-missing")
  expect_equal(res$n, 0)
  res <- describe_stats(data.frame(g = character(0), x = numeric(0)), by = "g")
  expect_equal(nrow(res), 0)
  expect_named(res, c("g", stat_columns))
})

test_that("invalid input gives informative errors", {
  expect_error(describe_stats(1:3), "must be a data frame")
  expect_error(describe_stats(trial, vars = "height"), "not found")
  expect_error(describe_stats(trial, vars = "arm"), "must be numeric")
  expect_error(describe_stats(trial, by = "site"), "not found")
  expect_error(describe_stats(trial, vars = "age", by = "age"), "both")
  expect_error(describe_stats(data.frame(a = "x")), "no numeric columns")
  expect_error(describe_stats(trial, vars = 3), "character vector")
  expect_error(describe_stats(trial, type = 3), "`type`")
  expect_error(describe_stats(trial, na.rm = NA), "`na.rm`")
})

test_that("a dplyr grouped data frame is summarised by its groups", {
  skip_if_not_installed("dplyr")
  grouped <- dplyr::group_by(trial, arm)
  expect_equal(
    describe_stats(grouped, vars = "age"),
    describe_stats(trial, vars = "age", by = "arm")
  )
  # An explicit `by` takes priority over the grouping
  expect_equal(
    describe_stats(grouped, vars = "age", by = "sex"),
    describe_stats(trial, vars = "age", by = "sex")
  )
})

# --- Validation against a published clinical table ---------------------------
# CDISC Pilot study, Table 14-2.01 "Summary of Demographic and Baseline
# Characteristics" (ITT population), as reproduced by the R Consortium:
# https://rconsortium.github.io/submissions-pilot3-adam/main/articles/tlf-demographic.html
#   Age            Placebo   Xanomeline High Dose   Xanomeline Low Dose
#   N                   86                     84                    84
#   Mean             75.21                  74.38                 75.67
#   Median           76.00                  76.00                 77.50
test_that("reproduces CDISC Pilot Table 14-2.01: age by planned arm", {
  skip_if_not_installed("pharmaverseadam")
  res <- describe_stats(pharmaverseadam::adsl, vars = "AGE", by = "TRT01P")
  arms <- res[!res$TRT01P %in% "Screen Failure", ] # the table is ITT only

  expect_equal(arms$TRT01P, c("Placebo", "Xanomeline High Dose", "Xanomeline Low Dose"))
  expect_equal(arms$n, c(86, 84, 84))
  expect_equal(round(arms$mean, 2), c(75.21, 74.38, 75.67)) # published to 2 dp
  expect_equal(arms$median, c(76, 76, 77.5))
})
