test_that("calc_median() handles even and odd lengths", {
  expect_equal(calc_median(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 4.5) # (4 + 5) / 2
  expect_equal(calc_median(c(3, 1, 2)), 2)
  expect_equal(calc_median(c(10, 1)), 5.5)
})

test_that("calc_median() does not need sorted input", {
  expect_equal(calc_median(c(10, 5, 1, 6, 2)), 5)
})

test_that("calc_median() matches stats::median() on random data", {
  set.seed(2)
  for (n in c(1, 2, 3, 4, 51, 1000)) {
    v <- runif(n, -100, 100)
    expect_equal(calc_median(v), stats::median(v), info = paste("n =", n))
  }
})

test_that("calc_median() edge cases", {
  expect_equal(calc_median(7), 7)
  expect_equal(calc_median(c(1, NA, 3, 4), na.rm = TRUE), 3)
  expect_equal(calc_median(c(-Inf, 1, Inf)), 1)
})
