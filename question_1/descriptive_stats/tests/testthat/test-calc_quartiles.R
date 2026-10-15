x <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)

test_that("quartiles of the example data (R default, type 7)", {
  expect_equal(calc_q1(x), 2.25)
  expect_equal(calc_q3(x), 5)
  expect_equal(calc_iqr(x), 2.75)
})

test_that("quartiles match stats::quantile() for every supported type", {
  set.seed(3)
  samples <- list(
    x, 1:2, 1:3, 1:4, c(5, 1), runif(7), rnorm(10), rnorm(11), rpois(100, 3), rnorm(1001)
  )
  for (type in c(2, 6, 7)) {
    for (v in samples) {
      expect_equal(calc_q1(v, type = type), unname(stats::quantile(v, 0.25, type = type)),
                   info = paste("type", type, "n", length(v)))
      expect_equal(calc_q3(v, type = type), unname(stats::quantile(v, 0.75, type = type)),
                   info = paste("type", type, "n", length(v)))
      expect_equal(calc_iqr(v, type = type), stats::IQR(v, type = type),
                   info = paste("type", type, "n", length(v)))
    }
  }
})

test_that("Q1 <= median <= Q3", {
  set.seed(4)
  v <- rexp(500)
  expect_lte(calc_q1(v), calc_median(v))
  expect_lte(calc_median(v), calc_q3(v))
})

test_that("quartile edge cases", {
  expect_equal(calc_q1(5), 5)
  expect_equal(calc_q3(5), 5)
  expect_equal(calc_iqr(5), 0)
  expect_equal(calc_q1(c(x, NA), na.rm = TRUE), 2.25)
  expect_error(calc_q1(x, type = 3), "`type` must be one of")
  expect_error(calc_iqr(x, type = "7"), "`type` must be one of")
})
