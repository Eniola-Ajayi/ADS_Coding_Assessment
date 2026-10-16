# descriptiveStats

A small R package of descriptive statistics written from first principles, with
consistent input validation, documented edge-case behaviour and a full
`testthat` suite.

| Function | Returns |
|---|---|
| `calc_mean(x, na.rm = FALSE)` | Arithmetic mean |
| `calc_median(x, na.rm = FALSE)` | Median (average of the two middle values for even `n`) |
| `calc_mode(x, na.rm = FALSE)` | Most frequent value(s); all values on ties, `NA` if there is no mode |
| `calc_q1(x, na.rm = FALSE, type = 7)` | First quartile (25th percentile) |
| `calc_q3(x, na.rm = FALSE, type = 7)` | Third quartile (75th percentile) |
| `calc_iqr(x, na.rm = FALSE, type = 7)` | Interquartile range, Q3 - Q1 |
| `describe_stats(data, vars, by, na.rm = TRUE, type = 7)` | All of the above for the numeric columns of a data frame, overall or by group |

## Installation

```r
# from the repository root
devtools::install("question_1/descriptive_stats")
library(descriptiveStats)
```

## Usage

```r
data <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)

calc_mean(data)    # 4.3
calc_median(data)  # 4.5
calc_mode(data)    # 5
calc_q1(data)      # 2.25  (R default, type 7)
calc_q3(data)      # 5
calc_iqr(data)     # 2.75

calc_q1(data, type = 2)  # 2  (SAS default, PCTLDEF=5)
```

### Data frames and groups: `describe_stats()`

Beyond the brief: `describe_stats()` applies every statistic to the numeric
columns of a data frame, overall or within groups, the R equivalent of
`PROC MEANS` with a `CLASS` statement. It returns one row per group and
variable with `n`, `n_missing`, `mean`, `median`, `mode`, `q1`, `q3` and
`iqr`.

```r
adsl <- pharmaverseadam::adsl

describe_stats(adsl, vars = "AGE")                        # whole study
describe_stats(adsl, vars = "AGE", by = "TRT01A")         # by treatment arm
describe_stats(adsl, vars = "AGE", by = c("TRT01A", "SEX"), type = 2)  # SAS quartiles

# dplyr grouped data frames work too
adsl |> dplyr::group_by(TRT01A) |> describe_stats(vars = "AGE")
```

* Every value comes from the vector functions above, so results are
  identical to calling them on each subset (and the tests check this).
* Missing values in the analysis columns are removed by default
  (`na.rm = TRUE`, as in `PROC MEANS`) and counted in `n_missing`.
* Missing values in a grouping column form their own `NA` group, so no
  records are dropped silently (`PROC MEANS` drops them unless `MISSING` is
  set).
* `mode` is a character column, because there can be several modes
  (e.g. `"1, 2"`).
* No extra package dependencies: grouped data frames are recognised without
  importing dplyr.
* **Validated against a published table:** grouped by planned arm
  (`TRT01P`), the age N, mean and median of every arm match Table 14-2.01
  (Summary of Demographic and Baseline Characteristics) of the CDISC Pilot
  study, as [reproduced by the R Consortium](https://rconsortium.github.io/submissions-pilot3-adam/main/articles/tlf-demographic.html).
  A unit test checks this on every run.

### A note on the expected values in the assessment brief

The brief lists `calc_mean(data) # 3.3`, `calc_q1(data) # 2.5`,
`calc_q3(data) # 5.5` and `calc_iqr(data) # 3`. These do not match the data:

* **Mean**: the ten values sum to 43, so the mean is **4.3** (`mean(data)` agrees).
* **Quartiles**: none of the nine standard definitions in
  `stats::quantile(type = 1:9)` gives 2.5 / 5.5 for this vector. Those values
  *are* produced by `quantile(unique(data), c(0.25, 0.75))`, i.e. by applying
  the default method to the de-duplicated values, which suggests the example
  was generated that way by mistake.

Rather than bend the functions to reproduce numbers that cannot be justified,
the package implements standard, documented definitions and verifies them
against base R in the tests (`calc_q1(x, type = t)` equals
`quantile(x, 0.25, type = t)` for every supported `t`).

## Design decisions

### Input validation in one place
Every exported function calls the internal helper `check_numeric_input()`, so
all six behave identically:

| Input | Behaviour |
|---|---|
| Character, factor, logical, list, `NULL`, `Date` | Error, e.g. *"`x` must be a numeric vector, not a character vector."* |
| Contains `NA` / `NaN`, `na.rm = FALSE` (default) | Returns `NA` (consistent with base R) |
| Contains `NA` / `NaN`, `na.rm = TRUE` | Missing values are removed first |
| Empty (or all missing with `na.rm = TRUE`) | Returns `NA` with a warning |
| Single value | Returns that value (`calc_iqr()` returns 0) |
| `Inf` / `-Inf` | Kept; e.g. the mean of `c(1, Inf)` is `Inf` |
| Integer vectors | Converted to double, so very long vectors cannot overflow |

Logical vectors are rejected deliberately: `TRUE`/`FALSE` silently becoming
1/0 is a common source of bugs.

### Mean
Computed as `sum(x) / n` followed by a second-pass correction
`mean + sum(x - mean) / n`, the same approach base R uses, which removes
floating-point rounding error on long vectors or values of very different
magnitude. It is vectorised (no explicit loop), so it is fast for long vectors.

### Mode
Returns **all** tied modes, sorted. If there is more than one distinct value
and every value occurs equally often (e.g. `c(1, 2, 3)` or `c(1, 1, 2, 2)`),
there is no mode and `NA` is returned.

### Quartiles
There is no single definition of a sample quantile. The `type` argument
supports three of Hyndman & Fan's (1996) definitions, implemented from scratch:

| `type` | Software default | Q1, Q3 of the example data |
|---|---|---|
| 7 (default) | R, Excel | 2.25, 5 |
| 6 | SPSS, Minitab | 2, 5.25 |
| 2 | SAS (`PCTLDEF=5`) | 2, 5 |

`calc_iqr()` uses the same `type` for both quartiles.

## Development

```r
devtools::document()  # regenerate man/ and NAMESPACE from the roxygen comments
devtools::test()      # run the testthat suite
devtools::check()     # full R CMD check
```

```
descriptive_stats/
|-- DESCRIPTION        package metadata
|-- NAMESPACE          exports (generated by roxygen2)
|-- LICENSE
|-- R/
|   |-- calc_mean.R
|   |-- calc_median.R
|   |-- calc_mode.R
|   |-- calc_quartiles.R   calc_q1(), calc_q3(), calc_iqr()
|   `-- utils.R            internal input validation + quantile algorithm
|-- man/               help pages (generated by roxygen2)
`-- tests/testthat/    one test file per function + shared input validation tests
```
