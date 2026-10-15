x <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)

test_that("calc_mean() gives the arithmetic mean", {
  expect_equal(calc_mean(x), 4.3) # 43 / 10
  expect_equal(calc_mean(c(-5, 5)), 0)
  expect_equal(calc_mean(c(0.1, 0.2, 0.3)), 0.2)
})

test_that("calc_mean() matches base::mean() on random data", {
  set.seed(1)
  for (n in c(1, 2, 3, 10, 101, 10000)) {
    v <- rnorm(n, mean = 100, sd = 50)
    expect_equal(calc_mean(v), mean(v), info = paste("n =", n))
  }
})

test_that("calc_mean() is accurate for values of very different magnitudes", {
  v <- c(1e10, 1, -1e10, 1)
  expect_equal(calc_mean(v), mean(v))
})

test_that("calc_mean() edge cases", {
  expect_equal(calc_mean(42), 42)
  expect_equal(calc_mean(c(1, NA, 3), na.rm = TRUE), 2)
  expect_equal(calc_mean(c(1, 2, Inf)), Inf)
  expect_true(is.nan(calc_mean(c(Inf, -Inf))))
})

test_that("calc_mean() works on long vectors", {
  v <- seq_len(1e6)
  expect_equal(calc_mean(v), mean(v))
})
