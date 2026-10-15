#' Calculate the first quartile (Q1)
#'
#' Computes the first quartile (25th percentile) of a numeric vector.
#'
#' @details
#' There is no single agreed definition of a sample quantile. This package
#' implements three of the nine definitions in Hyndman and Fan (1996), chosen
#' because they are the defaults of widely used software:
#'
#' | `type` | Used by | Method |
#' |---|---|---|
#' | 7 (default) | R, Excel `QUARTILE.INC` | linear interpolation at position `(n - 1)p + 1` |
#' | 6 | SPSS, Minitab | linear interpolation at position `(n + 1)p` |
#' | 2 | SAS (`PCTLDEF=5`, the default) | inverse empirical CDF, averaging at ties |
#'
#' The results match [stats::quantile()] with the same `type`.
#'
#' **Edge cases**
#' * Missing values (`NA`, `NaN`): returns `NA` unless `na.rm = TRUE`.
#' * Empty vector (or all values missing with `na.rm = TRUE`): returns `NA`
#'   with a warning.
#' * Single value: returns that value.
#' * Non-numeric input, or an invalid `type`: error.
#'
#' @inheritParams calc_mean
#' @param type Quantile definition: `7` (default, as in R), `6` or `2`
#'   (as in SAS). See Details.
#'
#' @return A single numeric value (double), or `NA` as described above.
#'
#' @references Hyndman, R. J. and Fan, Y. (1996). Sample quantiles in
#'   statistical packages. *The American Statistician*, 50(4), 361-365.
#'
#' @seealso [calc_q3()], [calc_iqr()], [calc_median()]
#' @export
#'
#' @examples
#' x <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)
#' calc_q1(x)            # R default (type 7)
#' calc_q1(x, type = 2)  # SAS default
#' calc_q1(c(x, NA), na.rm = TRUE)
calc_q1 <- function(x, na.rm = FALSE, type = 7) {
  calc_quartile(x, p = 0.25, na.rm = na.rm, type = type, fun = "calc_q1")
}

#' Calculate the third quartile (Q3)
#'
#' Computes the third quartile (75th percentile) of a numeric vector.
#'
#' @inherit calc_q1 details return references
#' @inheritParams calc_q1
#'
#' @seealso [calc_q1()], [calc_iqr()], [calc_median()]
#' @export
#'
#' @examples
#' x <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)
#' calc_q3(x)            # R default (type 7)
#' calc_q3(x, type = 6)  # SPSS/Minitab
calc_q3 <- function(x, na.rm = FALSE, type = 7) {
  calc_quartile(x, p = 0.75, na.rm = na.rm, type = type, fun = "calc_q3")
}

#' Calculate the interquartile range (IQR)
#'
#' Computes the interquartile range, `Q3 - Q1`: the spread of the middle 50%
#' of the data.
#'
#' @details
#' Q1 and Q3 are calculated with [calc_q1()] and [calc_q3()] using the same
#' `type`, so the result matches [stats::IQR()] with that `type`. Edge cases
#' behave as for [calc_q1()]: `NA` for missing values unless `na.rm = TRUE`,
#' `NA` with a warning for empty input, and `0` for a single value.
#'
#' @inheritParams calc_q1
#'
#' @return A single non-negative numeric value (double), or `NA`.
#'
#' @seealso [calc_q1()], [calc_q3()]
#' @export
#'
#' @examples
#' x <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)
#' calc_iqr(x)
#' calc_iqr(x, type = 2)
#' calc_iqr(5)  # a single value has no spread
calc_iqr <- function(x, na.rm = FALSE, type = 7) {
  check_type(type)
  input <- check_numeric_input(x, na.rm = na.rm)
  if (input$has_na) return(NA_real_)
  if (input$is_empty) return(empty_result("calc_iqr"))

  sorted <- sort(input$x)
  quantile_hf(sorted, 0.75, type) - quantile_hf(sorted, 0.25, type)
}

# Shared implementation for calc_q1() and calc_q3()
calc_quartile <- function(x, p, na.rm, type, fun) {
  check_type(type)
  input <- check_numeric_input(x, na.rm = na.rm)
  if (input$has_na) return(NA_real_)
  if (input$is_empty) return(empty_result(fun))

  quantile_hf(sort(input$x), p, type)
}
