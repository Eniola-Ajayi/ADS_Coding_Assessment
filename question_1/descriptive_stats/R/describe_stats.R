#' Descriptive statistics for data frame columns, overall or by group
#'
#' Applies the package's statistics to one or more numeric columns of a data
#' frame, either overall or within groups. It is the equivalent of
#' `PROC MEANS` with a `CLASS` statement in SAS, or of `dplyr::group_by()`
#' followed by `summarise()`, and returns one row per group and variable.
#'
#' @details
#' Every statistic is calculated with the package's own functions
#' ([calc_mean()], [calc_median()], [calc_mode()], [calc_q1()], [calc_q3()],
#' [calc_iqr()]), so the results are identical to calling them on each
#' subset by hand.
#'
#' **Groups**
#' * Groups are sorted by the grouping columns, the first column varying
#'   slowest (factor columns keep their level order).
#' * Missing values in a grouping column form their own group, shown as
#'   `NA`, so no records are dropped silently. (SAS `PROC MEANS` drops them
#'   unless the `MISSING` option is used.)
#' * A data frame grouped with `dplyr::group_by()` is summarised by its
#'   groups, unless `by` is given.
#'
#' **Missing values in the analysis columns**
#' * With `na.rm = TRUE` (the default, as in `PROC MEANS`) they are left out
#'   of the statistics and counted in `n_missing`.
#' * With `na.rm = FALSE`, any missing value makes that row's statistics `NA`,
#'   as for the vector functions.
#' * A group with no non-missing values gets `NA` statistics, and a single
#'   warning reports how many such group/variable combinations there were.
#'
#' **Mode**: there can be several modes (ties), so `mode` is a character
#' column, e.g. `"1, 2"`, and `NA` when there is no mode.
#'
#' @param data A data frame. Tibbles and data.tables also work.
#' @param vars Character vector of the numeric columns to summarise. Defaults
#'   to every numeric column that is not a grouping column.
#' @param by Character vector of grouping columns, of any type (character,
#'   factor, numeric, date, ...). Defaults to no grouping, or to the groups of
#'   a grouped data frame.
#' @param na.rm Logical. Remove missing values before computing? Defaults to
#'   `TRUE`; the number removed is reported in `n_missing`.
#' @inheritParams calc_q1
#'
#' @return A data frame with one row per group and variable, containing the
#'   grouping columns (if any), then `variable`, `n` (non-missing values),
#'   `n_missing`, `mean`, `median`, `mode`, `q1`, `q3` and `iqr`.
#'
#' @seealso [calc_mean()], [calc_q1()] for the definitions used.
#' @export
#'
#' @examples
#' trial <- data.frame(
#'   arm    = c("Placebo", "Placebo", "Placebo", "Drug", "Drug", "Drug"),
#'   sex    = c("F", "M", "F", "M", "F", "M"),
#'   age    = c(64, 71, 58, 69, 75, 80),
#'   weight = c(70.2, 81.5, NA, 77.0, 65.4, 72.8)
#' )
#'
#' # Every numeric column, whole data set
#' describe_stats(trial)
#'
#' # By treatment arm (like PROC MEANS with CLASS arm)
#' describe_stats(trial, vars = "age", by = "arm")
#'
#' # Two grouping columns, SAS-style quartiles
#' describe_stats(trial, vars = c("age", "weight"), by = c("arm", "sex"), type = 2)
#'
#' # A dplyr grouped data frame is summarised by its groups:
#' # trial |> dplyr::group_by(arm) |> describe_stats()
describe_stats <- function(data, vars = NULL, by = NULL, na.rm = TRUE, type = 7) {
  #stop with an error if data is not a data frame
  if (!is.data.frame(data)) {
    stop(
      sprintf("`data` must be a data frame, not %s.", describe_type(data)),
      call. = FALSE
    )
  }
  #if na.rm is anything that is not a boolean, not one value or is set to missing then stop with an error
  if (!is.logical(na.rm) || length(na.rm) != 1L || is.na(na.rm)) {
    stop("`na.rm` must be a single TRUE or FALSE value.", call. = FALSE)
  }
  #stop with an error if type is not 2, 6 or 7
  #checked here so a bad type gives one error up front rather than failing inside the loop below
  check_type(type)

  # Columns to group by, and columns to summarise
  if (is.null(by)) by <- group_columns(data) #no by given: use the groups of a dplyr grouped data frame, if there are any
  by <- check_columns(data, by, "by") #check the by columns exist in data
  vars <- choose_vars(data, vars, by) #pick the numeric columns to summarise, or check the ones given

  #plain data frame from here on
  #tibbles and data.tables behave slightly differently when selecting rows and columns,
  #so this makes them all behave the same
  data <- as.data.frame(data)
  groups <- group_rows(data, by) #row numbers in each group, plus each group's values (e.g. Placebo)

  #empty list with one slot per group and variable combination, filled in by the loop below
  results <- vector("list", length(groups$rows) * length(vars))
  #counts group and variable combinations with no values, so there is one warning at the end
  #instead of one per group
  n_empty <- 0L
  k <- 0L #position in results to fill next
  #loop over each group, then each variable within the group (like by group processing in sas)
  for (g in seq_along(groups$rows)) {
    for (v in vars) {
      k <- k + 1L
      #data[[v]] takes column v as a vector, then [groups$rows[[g]]] keeps only the rows in group g
      #summarise_column() then calculates every statistic on those values
      stats <- summarise_column(data[[v]][groups$rows[[g]]], na.rm, type)
      n_empty <- n_empty + (stats$n == 0L) #TRUE counts as 1 and FALSE as 0, so this adds 1 when the group had no values
      row <- cbind(data.frame(variable = v, stringsAsFactors = FALSE), stats) #put the variable name in front of the statistics
      if (length(by) > 0L) {
        #put the group values in front too, e.g. TRT01A = Placebo
        #drop = FALSE keeps it as a data frame, otherwise R turns a single column into a plain vector
        row <- cbind(groups$keys[g, , drop = FALSE], row, row.names = NULL)
      }
      results[[k]] <- row #store the finished row
    }
  }

  #one warning covering every group with no values
  if (n_empty > 0L) {
    warning(
      sprintf(
        "%d group/variable combination%s had no non-missing values; %s statistics are NA.",
        n_empty,
        if (n_empty == 1L) "" else "s", #"combination" or "combinations"
        if (n_empty == 1L) "its" else "their" #"its" or "their"
      ),
      call. = FALSE
    )
  }

  #no rows to return (a grouped summary of a data frame with no rows):
  #return an empty table that still has the usual columns
  if (length(results) == 0L) return(empty_summary(data, by))
  out <- do.call(rbind, results) #stack all the one row data frames into one table (like set in sas)
  rownames(out) <- NULL #renumber the rows 1, 2, 3...
  out
}

# ---------------------------------------------------------------------------
# Internal helpers for describe_stats()
# ---------------------------------------------------------------------------

#' All statistics for one vector, as a one-row data frame
#' @noRd
summarise_column <- function(x, na.rm, type) {
  n_missing <- sum(is.na(x)) #number of missing values (TRUE counts as 1)
  #start with a one row table of NA statistics, which is filled in below if there is anything to compute
  #stringsAsFactors = FALSE keeps text as text (older versions of R turned it into factors)
  stats <- data.frame(
    n = length(x) - n_missing, n_missing = n_missing,
    mean = NA_real_, median = NA_real_, mode = NA_character_,
    q1 = NA_real_, q3 = NA_real_, iqr = NA_real_,
    stringsAsFactors = FALSE
  )
  # Nothing to compute: no values left, or missing values kept (na.rm = FALSE)
  #exiting here means the calc_ functions never see empty input, so they don't each give their own
  #warning; describe_stats() gives one warning for all empty groups instead
  if (stats$n == 0L || (n_missing > 0L && !na.rm)) return(stats)

  modes <- calc_mode(x, na.rm = na.rm) #can be several values (ties) or NA (no mode)
  stats$mean   <- calc_mean(x, na.rm = na.rm)
  stats$median <- calc_median(x, na.rm = na.rm)
  #join several modes into one text value, e.g. "1, 2"
  stats$mode   <- if (anyNA(modes)) NA_character_ else paste(modes, collapse = ", ")
  stats$q1     <- calc_q1(x, na.rm = na.rm, type = type)
  stats$q3     <- calc_q3(x, na.rm = na.rm, type = type)
  stats$iqr    <- calc_iqr(x, na.rm = na.rm, type = type)
  stats
}

#' Row numbers of each group, and one row of grouping values per group
#'
#' Groups are sorted by the grouping columns (first column slowest), and
#' missing grouping values form their own group.
#' @noRd
group_rows <- function(data, by) {
  #no by columns: one group containing every row
  if (length(by) == 0L) {
    return(list(keys = NULL, rows = list(seq_len(nrow(data)))))
  }
  # Sorted integer codes per grouping column; exclude = NULL keeps NA as a code
  #factor() sorts each column's values and numbers them 1, 2, 3..., e.g. Drug = 1, Placebo = 2
  #numbers sort as numbers, dates as dates, and factor columns keep their level order
  #lapply() does this for each by column in turn, like a loop
  codes <- lapply(data[by], function(col) as.integer(factor(col, exclude = NULL)))
  #combine the codes of all the by columns into one group id per row
  #lex.order = TRUE sorts with the first by column varying slowest (like proc sort by arm sex)
  #drop = TRUE leaves out combinations that never occur in the data
  #do.call() is needed because the number of by columns varies: it passes each one as a separate argument
  group_id <- do.call(interaction, c(unname(codes), list(drop = TRUE, lex.order = TRUE)))

  rows <- unname(split(seq_len(nrow(data)), group_id)) #list of the row numbers in each group, in group order
  #first row number of each group (vapply() is like lapply() but checks each result is one whole number)
  first_rows <- vapply(rows, function(r) r[1L], integer(1))
  keys <- data[first_rows, by, drop = FALSE] #the group values, taken from the first row of each group (one row per group)
  rownames(keys) <- NULL #renumber the rows 1, 2, 3...
  list(keys = keys, rows = rows)
}

#' Grouping columns of a dplyr grouped data frame (without needing dplyr)
#' @noRd
group_columns <- function(data) {
  groups <- attr(data, "groups") #dplyr::group_by() stores the grouping in a hidden attribute called "groups"
  if (inherits(data, "grouped_df") && is.data.frame(groups)) {
    return(setdiff(names(groups), ".rows")) #the grouping column names, minus dplyr's own .rows column
  }
  character(0) #not grouped: no grouping columns
}

#' Check that column names are valid and present in `data`
#' @noRd
check_columns <- function(data, cols, arg) {
  if (is.null(cols) || length(cols) == 0L) return(character(0)) #no columns given: return an empty set of names
  #stop with an error if the column names are not text, or include a missing value
  if (!is.character(cols) || anyNA(cols)) {
    stop(sprintf("`%s` must be a character vector of column names.", arg), call. = FALSE)
  }
  missing <- setdiff(cols, names(data)) #names given that are not columns in data
  #stop with an error listing every column that was not found, not just the first
  if (length(missing) > 0L) {
    stop(
      sprintf(
        "Column%s not found in `data` (from `%s`): %s.",
        if (length(missing) == 1L) "" else "s", arg, backticks(missing) #"Column" or "Columns"
      ),
      call. = FALSE
    )
  }
  unique(cols) #drop repeats, e.g. by = c("arm", "arm")
}

#' The numeric columns to summarise
#' @noRd
choose_vars <- function(data, vars, by) {
  #TRUE or FALSE for each column: is it numeric? factors are left out because they are stored as numbers underneath
  is_num <- vapply(data, function(col) is.numeric(col) && !is.factor(col), logical(1))

  #vars not given: use every numeric column that is not a by column
  if (is.null(vars)) {
    vars <- setdiff(names(data)[is_num], by)
    #stop with an error if there is nothing to summarise
    if (length(vars) == 0L) {
      stop("`data` has no numeric columns to summarise.", call. = FALSE)
    }
    return(vars)
  }

  #vars given: check the columns exist, are numeric and are not also by columns
  vars <- check_columns(data, vars, "vars")
  if (length(vars) == 0L) stop("`vars` must name at least one column.", call. = FALSE)
  not_numeric <- vars[!is_num[vars]] #the vars columns that are not numeric
  if (length(not_numeric) > 0L) {
    stop(
      sprintf("Columns in `vars` must be numeric. Not numeric: %s.", backticks(not_numeric)),
      call. = FALSE
    )
  }
  both <- intersect(vars, by) #columns named in both vars and by
  if (length(both) > 0L) {
    stop(
      sprintf("A column cannot be in both `vars` and `by`: %s.", backticks(both)),
      call. = FALSE
    )
  }
  vars
}

#' Zero-row result with the usual columns (for a data frame with no rows)
#' @noRd
empty_summary <- function(data, by) {
  #summarise an empty vector to get the statistic columns, then [0, ] keeps no rows
  #so only the column names and types are left
  stats <- summarise_column(numeric(0), na.rm = TRUE, type = 7)[0, , drop = FALSE]
  template <- cbind(data.frame(variable = character(0), stringsAsFactors = FALSE), stats) #add the variable column in front
  if (length(by) > 0L) template <- cbind(data[0, by, drop = FALSE], template) #and the by columns, keeping their types
  template
}

#' Format names for messages: `a`, `b`
#' @noRd
backticks <- function(x) paste0("`", x, "`", collapse = ", ") #e.g. c("age", "sex") gives "`age`, `sex`"
