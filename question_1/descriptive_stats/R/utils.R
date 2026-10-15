# Internal helpers shared by every exported function. Not exported.

#' Validate and clean a numeric input vector
#'
#' Central input checks so that every statistic behaves the same way:
#' rejects non-numeric input with an informative error, handles missing
#' values according to `na.rm`, and flags empty input.
#'
#' @param x Object passed by the user.
#' @param na.rm Logical; remove missing values (`NA`/`NaN`) before computing?
#' @param arg Name of the argument, used in error messages.
#'
#' @return A list with elements `x` (a double vector, missing values removed
#'   when `na.rm = TRUE`), `has_na` (logical) and `is_empty` (logical).
#' @noRd
check_numeric_input <- function(x, na.rm = FALSE, arg = "x") {
  if (!is.logical(na.rm) || length(na.rm) != 1L || is.na(na.rm)) {
    stop("`na.rm` must be a single TRUE or FALSE value.", call. = FALSE)
  }
  if (is.null(x)) {
    stop(sprintf("`%s` must be a numeric vector, not NULL.", arg), call. = FALSE)
  }
  # Factors are stored as integers, so check for them explicitly first
  if (is.factor(x) || !is.numeric(x)) {
    stop(
      sprintf(
        "`%s` must be a numeric vector, not %s.", arg, describe_type(x)
      ),
      call. = FALSE
    )
  }

  # Convert integers to double: avoids integer overflow on very long vectors
  # and keeps return types consistent.
  x <- as.double(x)
  missing <- is.na(x) # TRUE for both NA and NaN

  if (any(missing)) {
    if (!na.rm) {
      return(list(x = x, has_na = TRUE, is_empty = FALSE))
    }
    x <- x[!missing]
  }

  list(x = x, has_na = FALSE, is_empty = length(x) == 0L)
}

#' Human-readable description of an object's type for error messages
#' @noRd
describe_type <- function(x) {
  if (is.factor(x)) return("a factor")
  if (is.data.frame(x)) return("a data frame")
  if (is.matrix(x) && !is.numeric(x)) return(sprintf("a %s matrix", typeof(x)))
  if (is.list(x)) return("a list")
  if (!is.null(attr(x, "class"))) {
    return(sprintf("an object of class <%s>", class(x)[1L])) # e.g. Date
  }
  sprintf("a %s vector", typeof(x))
}

#' Warn and return NA when there are no values to summarise
#' @noRd
empty_result <- function(fun) {
  warning(
    sprintf("`%s()` received no non-missing values; returning NA.", fun),
    call. = FALSE
  )
  NA_real_
}

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
  n <- length(x)
  if (n == 1L) return(x[1L])

  if (type == 2) {
    # Inverse of the empirical CDF, averaging at discontinuities
    np <- n * p
    j <- floor(np + 4 * .Machine$double.eps) # small fuzz for floating point
    g <- np - j
    lo <- x[max(j, 1L)]
    hi <- x[min(j + 1L, n)]
    if (abs(g) < 4 * .Machine$double.eps) {
      return(if (j == 0) x[1L] else (lo + hi) / 2)
    }
    return(hi)
  }

  # Types 6 and 7 are both "position = n * p + m" with linear interpolation
  m <- switch(as.character(type),
    "6" = p,
    "7" = 1 - p
  )
  h <- n * p + m                       # (fractional) position in sorted data
  j <- floor(h + 4 * .Machine$double.eps)
  g <- h - j                           # how far between x[j] and x[j + 1]

  if (j < 1L) return(x[1L])            # positions before the first value
  if (j >= n) return(x[n])             # positions beyond the last value
  if (abs(g) < 4 * .Machine$double.eps) return(x[j])

  (1 - g) * x[j] + g * x[j + 1L]
}

#' Validate the quantile `type` argument
#' @noRd
check_type <- function(type) {
  if (!is.numeric(type) || length(type) != 1L || !(type %in% c(2, 6, 7))) {
    stop(
      "`type` must be one of 2 (SAS default), 6 (SPSS/Minitab) or 7 (R default).",
      call. = FALSE
    )
  }
  invisible(type)
}
