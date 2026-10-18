#' Calculate the arithmetic mean
#'
#' Computes the arithmetic mean (the sum of the values divided by how many values
#' there are) of a numeric vector.
#'
#' @details
#' The mean is calculated in two passes: a first estimate (1)`sum(x) / n`, then a
#' correction for floating-point rounding error, (2) `mean + sum(x - mean) / n`.
#' This matches the approach used by base R's [mean()] and keeps the result
#' accurate for long vectors and for values of very different magnitudes.
#' Integer input is converted to double first, so very long integer vectors
#' cannot overflow.
#'
#' **Edge case handling**
#' * Missing values in the vector (`NA`, `NaN`): returns `NA` unless `na.rm = TRUE` where alternatively, missing values will be dropped first.
#' * An Empty vector (or all values missing with `na.rm = TRUE`): returns `NA`
#'   with a warning.
#' * a vector with a Single value: returns that value alone.
#' * Infinity: `Inf`/`-Inf`  are kept: the mean may be `Inf`, `-Inf`, or `NaN` when
#'   both are present.
#' * Non-numeric input (character, factor, logical, list, `NULL`): results in an error.
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should missing values be removed before computing?
#'   Defaults to `FALSE`, consistent with base R.
#'
#' @return A single numeric value (double), or `NA` as described above.
#'
#' @seealso [calc_median()], [calc_mode()]
#' @export
#'
#' @examples
#' calc_mean(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#'
#' # Missing values
#' calc_mean(c(2, 4, NA))
#' calc_mean(c(2, 4, NA), na.rm = TRUE)
#'
#' # Single value
#' calc_mean(7)
#'
#' # Empty input returns NA with a warning
#' suppressWarnings(calc_mean(numeric(0)))
calc_mean <- function(x, na.rm = FALSE) {
  input <- check_numeric_input(x, na.rm = na.rm) #check validity of vector for processing
  if (input$has_na) return(NA_real_) #exit here if missing values present and user has not declared to remove them
  if (input$is_empty) return(empty_result("calc_mean")) #exit here with a warning if there are no values left to process

  x <- input$x #cleaned input
  n <- length(x)# number of values in cleaned input

  #first pass (1)
  mean_1 <- sum(x) / n
  if (!is.finite(mean_1)) return(mean_1) # Inf / NaN: no correction possible

  # Second pass (2) which corrects the accumulated rounding error
  mean_1 + sum(x - mean_1) / n
}
