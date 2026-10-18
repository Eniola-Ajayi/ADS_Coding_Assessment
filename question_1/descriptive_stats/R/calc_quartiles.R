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
#' In the case where there is double programming between two software packages,
#' adjusting the type can align the result returned in R with that of the
#' alternative software used in the double programming effort.
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
  #q1 is the 25th percentile so pass p = 0.25 to the shared helper at the bottom of this file
  #fun is only used to name this function in the warning if there are no values to process
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
  #q3 is the 75th percentile, same helper as q1 but with p = 0.75
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
  check_type(type) #stop with an error if type is not 2, 6 or 7
  input <- check_numeric_input(x, na.rm = na.rm) #check validity of vector for processing
  if (input$has_na) return(NA_real_) #exit here if missing values present and user has not declared to remove them
  if (input$is_empty) return(empty_result("calc_iqr")) #exit here with a warning if there are no values left to process

  #sort once and use the same sorted values for both quartiles
  #calc_q3(x) - calc_q1(x) would give the same answer but would check, sort and warn twice
  sorted <- sort(input$x)
  quantile_hf(sorted, 0.75, type) - quantile_hf(sorted, 0.25, type) #iqr = q3 - q1
}


# ---------------------------------------------------------------------------
# Internal helpers (not exported)
# ---------------------------------------------------------------------------

# Shared implementation for calc_q1(), calc_q3() and calc_iqr()
#' Sample quantile following Hyndman & Fan (1996)
#'
#' Implemented from first principles. Supports type 2 (SAS PCTLDEF=5),
#' type 6 (SPSS/Minitab) and type 7 (R and Excel default).
#'
#' @param x Sorted double vector with no missing values, length >= 1.
#' @param p Probability in \[0, 1\].
#' @param type One of 2, 6 or 7.
#' @return A single double.
#' @noRd
quantile_hf <- function(x, p, type = 7) {
  n <- length(x) #number of values
  if (n == 1L) return(x[1L]) #only one value so every quantile is that value

  #type 2 (sas): no interpolation, the answer is always one of the values or the average of two
  if (type == 2) {
    # Inverse of the empirical CDF, averaging at discontinuities
    np <- n * p #position of the quantile in the sorted values, e.g. 10 values * 0.25 = 2.5
    #computers store decimals approximately, e.g. 100 * 0.29 comes out as 28.999999999999996
    #not 29, so add a tiny amount before rounding down so it still rounds down to 29 and not 28
    j <- floor(np + 4 * .Machine$double.eps) # small fuzz for floating point
    g <- np - j #fraction left over, e.g. 2.5 - 2 = 0.5
    lo <- x[max(j, 1L)] #value at position j (max() stops position 0 going off the start)
    hi <- x[min(j + 1L, n)] #value at position j + 1 (min() stops it going off the end)
    #no fraction left over (allowing for the same tiny rounding error) means np is a whole number:
    #average the two values either side, e.g. np = 3 gives (x[3] + x[4]) / 2
    #np = 0 only happens when p = 0, so return the smallest value
    if (abs(g) < 4 * .Machine$double.eps) {
      return(if (j == 0) x[1L] else (lo + hi) / 2)
    }
    return(hi) #np is not a whole number so round up to the next value, e.g. np = 2.5 gives x[3]
  }

  # Types 6 and 7 are both "position = n * p + m" with linear interpolation
  #they only differ in m, the small shift added to the position
  #switch() picks the line matching type, like select/when in sas
  m <- switch(as.character(type),
    "6" = p, #type 6: position = (n + 1)p
    "7" = 1 - p #type 7: position = (n - 1)p + 1
  )
  h <- n * p + m                       # (fractional) position in sorted data
  j <- floor(h + 4 * .Machine$double.eps) #whole number part of the position (same fuzz as type 2)
  g <- h - j                           # how far between x[j] and x[j + 1]

  if (j < 1L) return(x[1L])            # positions before the first value
  if (j >= n) return(x[n])             # positions beyond the last value
  if (abs(g) < 4 * .Machine$double.eps) return(x[j]) #position lands exactly on a value so return it

  #otherwise interpolate: move g of the way from x[j] to x[j + 1]
  #e.g. type 7 q1 of 1, 2, 2, 3, 4, 5, 5, 5, 6, 10: h = 3.25 so 2 + 0.25 * (3 - 2) = 2.25
  (1 - g) * x[j] + g * x[j + 1L]
}

#' Validate the quantile `type` argument
#' @noRd
check_type <- function(type) {
  #stop with an error if type is not a single number, or is not one of the supported types 2, 6 or 7
  if (!is.numeric(type) || length(type) != 1L || !(type %in% c(2, 6, 7))) {
    stop(
      "`type` must be one of 2 (SAS default), 6 (SPSS/Minitab) or 7 (R default).",
      call. = FALSE
    )
  }
  invisible(type) #return type without printing it, the function is only called for the check
}

# Shared implementation for calc_q1() and calc_q3()
calc_quartile <- function(x, p, na.rm, type, fun) {
  check_type(type) #stop with an error if type is not 2, 6 or 7
  input <- check_numeric_input(x, na.rm = na.rm) #check validity of vector for processing
  if (input$has_na) return(NA_real_) #exit here if missing values present and user has not declared to remove them
  #exit here with a warning if there are no values left to process
  #fun is the name of the function the user called (calc_q1 or calc_q3), used in the warning
  if (input$is_empty) return(empty_result(fun))

  quantile_hf(sort(input$x), p, type) #sort the values then find the quantile at p
}
