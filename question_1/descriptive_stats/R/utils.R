# Internal helpers shared by every exported function. Not exported.

#' Validate and clean a numeric input vector
#'
#' Central input checks so that every statistic behaves the same way:
#' rejects non-numeric input with an informative error, handles missing
#' values according to `na.rm`, and flags empty input.
#'
#' @param x Object passed by the user.
#' @param na.rm Logical; remove missing values (`NA`/`NaN`) before computing
#' @param arg Name of the argument, used in error messages.
#'
#' @return A list with elements `x` (a double vector, missing values removed
#'   when `na.rm = TRUE`), `has_na` (logical) and `is_empty` (logical).
#' @noRd
check_numeric_input <- function(x, na.rm = FALSE, arg = "x") {
# if the na.rm equals anything that is not a boolean, not one value or is set to missing then stop with an error.
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
