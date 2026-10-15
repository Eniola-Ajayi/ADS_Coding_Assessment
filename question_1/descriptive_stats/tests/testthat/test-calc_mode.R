test_that("calc_mode() returns the single most frequent value", {
  expect_equal(calc_mode(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 5)
})

test_that("calc_mode() returns all tied modes, sorted", {
  expect_equal(calc_mode(c(3, 3, 1, 1, 2)), c(1, 3))
  expect_equal(calc_mode(c(2.5, 2.5, -1, -1, 0)), c(-1, 2.5))
})

test_that("calc_mode() returns NA when there is no mode", {
  expect_identical(calc_mode(c(4, 8, 15)), NA_real_)       # all unique
  expect_identical(calc_mode(c(1, 1, 2, 2)), NA_real_)     # all equally frequent
})

test_that("calc_mode() edge cases", {
  expect_equal(calc_mode(9), 9)                 # single value
  expect_equal(calc_mode(c(4, 4, 4)), 4)        # all identical
  expect_equal(calc_mode(c(1, 1, NA, 2), na.rm = TRUE), 1)
  expect_equal(calc_mode(c(Inf, Inf, 1)), Inf)
  expect_equal(calc_mode(c(1L, 2L, 2L)), 2)
})
