#' Calculate the median
#'
#' Computes the median: the middle value of the sorted data. For an even
#' number of values it is the average of the two middle values.
#'
#' @details
#' **Edge cases**
#' * Missing values (`NA`, `NaN`): returns `NA` unless `na.rm = TRUE`.
#' * Empty vector (or all values missing with `na.rm = TRUE`): returns `NA`
#'   with a warning.
#' * Single value: returns that value.
#' * `Inf`/`-Inf` are kept and sorted to the ends.
#' * Non-numeric input (character, factor, logical, list, `NULL`): error.
#'
#' @inheritParams calc_mean
#'
#' @return A single numeric value (double), or `NA` as described above.
#'
#' @seealso [calc_q1()], [calc_q3()], [calc_mean()]
#' @export
#'
#' @examples
#' # Even length: average of the 5th and 6th sorted values, (4 + 5) / 2
#' calc_median(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#'
#' # Odd length: the middle value
#' calc_median(c(3, 1, 2))
#'
#' calc_median(c(3, NA, 1), na.rm = TRUE)
calc_median <- function(x, na.rm = FALSE) {
  input <- check_numeric_input(x, na.rm = na.rm) #check validity of vector for processing
  if (input$has_na) return(NA_real_) #exit here if missing values present and user has not declared to remove them
  if (input$is_empty) return(empty_result("calc_median")) #exit here with a warning if there are no values left to process

  x <- sort(input$x)
  n <- length(x)
  middle <- (n + 1L) %/% 2L #position of middle value

#if length is odd then then middle value is the median
  if (n %% 2L == 1L) {
    x[middle]
#if even then the median is the average of the elements at middle position (m) and m+1
  } else {
    (x[middle] + x[middle + 1L]) / 2
  }
}
