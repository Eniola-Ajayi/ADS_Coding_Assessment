# Behaviour shared by every exported function (via check_numeric_input())

all_funs <- list(
  calc_mean = calc_mean, calc_median = calc_median, calc_mode = calc_mode,
  calc_q1 = calc_q1, calc_q3 = calc_q3, calc_iqr = calc_iqr
)

test_that("non-numeric input gives an informative error", {
  for (nm in names(all_funs)) {
    f <- all_funs[[nm]]
    expect_error(f("a"), "must be a numeric vector, not a character vector", info = nm)
    expect_error(f(factor(1:3)), "not a factor", info = nm)
    expect_error(f(c(TRUE, FALSE)), "not a logical vector", info = nm)
    expect_error(f(list(1, 2)), "not a list", info = nm)
    expect_error(f(NULL), "not NULL", info = nm)
    expect_error(f(Sys.Date()), "class <Date>", info = nm)
  }
})

test_that("invalid na.rm gives an error", {
  for (nm in names(all_funs)) {
    expect_error(all_funs[[nm]](1:3, na.rm = "yes"), "`na.rm` must be", info = nm)
    expect_error(all_funs[[nm]](1:3, na.rm = NA), "`na.rm` must be", info = nm)
  }
})

test_that("missing values return NA unless na.rm = TRUE", {
  for (nm in names(all_funs)) {
    expect_identical(all_funs[[nm]](c(1, NA, 3)), NA_real_, info = nm)
    expect_identical(all_funs[[nm]](c(1, NaN, 3)), NA_real_, info = nm)
    expect_false(is.na(all_funs[[nm]](c(1, 2, 2, NA, 3), na.rm = TRUE)[1]), info = nm)
  }
})

test_that("empty input returns NA with a warning", {
  for (nm in names(all_funs)) {
    expect_warning(res <- all_funs[[nm]](numeric(0)), "no non-missing values", info = nm)
    expect_identical(res, NA_real_, info = nm)
    expect_warning(res <- all_funs[[nm]](c(NA_real_, NA_real_), na.rm = TRUE), "no non-missing", info = nm)
    expect_identical(res, NA_real_, info = nm)
  }
})

test_that("integer input works and returns doubles", {
  for (nm in names(all_funs)) {
    expect_type(all_funs[[nm]](c(1L, 2L, 2L, 3L)), "double")
  }
})

test_that("very large integer vectors do not overflow", {
  big <- rep(.Machine$integer.max, 3)
  expect_equal(calc_mean(big), as.double(.Machine$integer.max))
})
