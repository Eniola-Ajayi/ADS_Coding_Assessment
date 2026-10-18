#' Calculate the mode
#'
#' Finds the most frequently occurring value(s) of a numeric vector.
#'
#' @details
#' **Ties**: if several values share the highest frequency, all of them are
#' returned, sorted in increasing order (a multimodal result).
#'
#' **No mode**: if the vector has more than one distinct value and every
#' value occurs the same number of times (e.g. `c(1, 2, 3)` or
#' `c(1, 1, 2, 2)`), there is no mode and `NA` is returned.
#'
#' **Other edge cases**
#' * Missing values (`NA`, `NaN`): returns `NA` unless `na.rm = TRUE`.
#' * Empty vector (or all values missing with `na.rm = TRUE`): returns `NA`
#'   with a warning.
#' * Single value, or all values identical: returns that value.
#' * Values are compared exactly, so floating-point values that differ in the
#'   last decimal place count as different values.
#' * Non-numeric input (character, factor, logical, list, `NULL`): error.
#'
#' @inheritParams calc_mean
#'
#' @return A numeric vector: one value for a single mode, several values when
#'   there are ties, or `NA` when there is no mode.
#'
#' @seealso [calc_mean()], [calc_median()]
#' @export
#'
#' @examples
#' # Single mode
#' calc_mode(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#'
#' # Ties: both modes are returned
#' calc_mode(c(1, 1, 2, 2, 3))
#'
#' # No mode: every value appears equally often
#' calc_mode(c(4, 8, 15))
calc_mode <- function(x, na.rm = FALSE) {
  input <- check_numeric_input(x, na.rm = na.rm) #check validity of vector for processing
  if (input$has_na) return(NA_real_) #exit here if missing values present and user has not declared to remove them
  if (input$is_empty) return(empty_result("calc_mode")) #exit here with a warning if there are no values left to process

  x <- input$x
  values <- sort(unique(x)) #sort values and remove duplciates to get list of distinct values
  counts <- tabulate(match(x, values), nbins = length(values)) #find and count how many times each value appears in the input vector
  top <- max(counts)#count for most frequent value

  # More than one distinct value, all equally frequent -> no mode
  if (length(values) > 1L && all(counts == top)) {
    return(NA_real_)
  }

  values[counts == top] #return values with corresponding top count
}
