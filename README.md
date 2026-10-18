# ADS Coding Assessment

[![Tests](https://github.com/Eniola-Ajayi/ADS_Coding_Assessment/actions/workflows/tests.yml/badge.svg)](https://github.com/Eniola-Ajayi/ADS_Coding_Assessment/actions/workflows/tests.yml)

Solutions to the six questions of the Analytical Data Science coding
assessment: R package development, SDTM/ADaM/TLG programming with the
pharmaverse, and two Python applications.

## Repository structure

```
.
|-- README.md                  this file
|-- run_all.R                  runs every R deliverable from scratch, logs to run_all_log.txt
|-- .github/workflows/         tests.yml: runs every check on each push (GitHub Actions)
|-- data/
|   |-- export_adae.R          exports pharmaverseadam::adae -> data/adae.csv (input for Q5, Q6)
|   `-- adae.csv
|-- question_1/
|   |-- question_1.R           builds, tests, checks and demonstrates the package
|   `-- descriptive_stats/     R package {descriptiveStats}
|       |-- DESCRIPTION, NAMESPACE, LICENSE, README.md
|       |-- R/                 calc_mean, calc_median, calc_mode, calc_q1/q3/iqr, utils
|       |-- man/               roxygen2 documentation
|       `-- tests/testthat/    unit tests
|-- question_2_sdtm/
|   |-- 02_create_ds_domain.R  SDTM DS domain with {sdtm.oak}
|   |-- metadata/sdtm_ct.csv   study controlled terminology
|   `-- output/                ds.rds, ds.csv
|-- question_3_adam/
|   |-- create_adsl.R          ADaM ADSL with {admiral}
|   `-- output/                adsl.rds, adsl.csv
|-- question_4_tlg/
|   |-- 01_create_ae_summary_table.R
|   |-- 02_create_visualizations.R
|   |-- 03_create_listings.R
|   `-- output/                ae_summary_table.html, 2 PNGs, ae_listings.html
|-- question_5_api/            FastAPI clinical data API (+ README, tests)
|-- question_6_genai/          LLM clinical data assistant (+ README, test script)
`-- extensions/                beyond the brief (the answers above are unchanged)
    `-- investigator_app/      Streamlit web app for investigators, built on the Q5 API
```

## Running the R questions

R >= 4.2. Set the working directory to the repository root, then:

```r
source("run_all.R")
```

This installs any missing packages, then runs each question in a fresh
environment and writes `run_all_log.txt`. Each script can also be run on its
own from the repository root.

## Running the Python questions

See `question_5_api/README.md` and `question_6_genai/README.md`. In short:

```bash
cd question_5_api && pip install -r requirements.txt && uvicorn main:app --reload
cd question_6_genai && pip install -r requirements.txt && python test_agent.py
```

## Automated checks

Every push to GitHub runs `.github/workflows/tests.yml` (GitHub Actions) on a
fresh Linux machine, so the badge at the top shows whether everything still
works:

* **R:** `R CMD check` of the Question 1 package, including its unit tests,
  then the Question 2-4 scripts and the ADAE export. Each script stops with an
  error if one of its own checks fails.
* **Python:** the Question 5 API tests, the Question 6 example questions (with
  the offline mock, so no API key is needed) and the investigator app's tests.

## Summary of each question

### Question 1: `descriptiveStats` R package
* Six exported functions with full roxygen2 documentation, including
  documented edge-case behaviour.
* One internal validator (`check_numeric_input()`) gives every function the
  same handling of invalid types, `NA`s (`na.rm`), empty vectors and single values.
* Quartiles are implemented from first principles for three Hyndman & Fan
  definitions: type 7 (R, default), type 6 (SPSS) and type 2 (SAS `PCTLDEF=5`).
* `testthat` suite, including comparisons against base R across random inputs.
* **Note:** the brief's example values for the mean (3.3) and quartiles
  (2.5 / 5.5) do not match the example data (the mean is 4.3, and no standard
  quantile definition gives 2.5 / 5.5). Details are in the package README.

* **Beyond the brief:** `describe_stats()` applies all six statistics to the
    numeric columns of a data frame, overall or by group (like `PROC MEANS`
    with `CLASS`), and also accepts tibbles and dplyr grouped data frames.

### Question 2: SDTM DS domain (`{sdtm.oak}`)
* Maps `pharmaverseraw::ds_raw` following the pharmaverse AE example pattern:
  oak id vars -> topic variable -> qualifiers/timing -> derived variables.
* Uses `condition_add()` for conditional mapping: OTHERSP for "other" events,
  hardcoded RANDOMIZED for protocol milestones, and the C66727 codelist for
  the remaining decodes.
* VISIT/VISITNUM come from the study visit codelists (unscheduled visits not
  in the codelist take their number from the label, e.g. "UNSCHEDULED 4.1" ->
  4.1), DSDTC/DSSTDTC are ISO 8601 character dates, and DSSEQ/DSSTDY are
  derived.
* **Self-check:** the result is compared with `pharmaversesdtm::ds`, from
  which the raw data was generated.

### Question 3: ADaM ADSL (`{admiral}`)
* Starts from `pharmaversesdtm::dm` and derives AGEGR9/AGEGR9N
  (`derive_vars_cat()`), TRTSDTM/TRTSTMF (`derive_vars_dtm()` with
  time-only imputation and `ignore_seconds_flag`), ITTFL, ABNSBPFL and
  CARPOPFL (`derive_var_merged_exist_flag()`), and LSTALVDT
  (`derive_vars_extreme_event()` over VS, AE, DS and treatment dates, using
  complete dates only).

### Question 4: AE tables, listings and graphs
* TEAE summary by SOC and reported term with `gtsummary::tbl_hierarchical()`,
  safety-population denominators, an overall "any TEAE" row and
  descending-frequency sorting (modelled on FDA Table 10).
* `ggplot2`: severity distribution by arm, and the top 10 AEs with exact
  Clopper-Pearson 95% CIs.
* TEAE listing by subject and start date, rendered with `gt`.

### Question 5: FastAPI clinical data API
* `GET /`, `POST /ae-query` (optional, combinable filters) and
  `GET /subject-risk/{subject_id}` (weighted score + category, 404 for
  unknown subjects).
* Business logic is in plain pandas functions, separate from the web layer, with `pytest` tests.

### Question 6: GenAI clinical data assistant
* `ClinicalTrialDataAgent`: schema-aware prompt -> structured JSON
  (`target_column`, `filter_value`) validated with pydantic -> pandas filter
  -> unique subjects.
* Uses OpenAI through LangChain when an API key is available, otherwise an
  offline mock that follows the same flow.

## Beyond the brief: extensions

The `extensions/` folder holds work that goes further than the six questions,
without changing any of the answers.

* **[Investigator app](extensions/investigator_app/README.md)**: *AE Safety
  Explorer*, a Streamlit web app that uses the Question 5 API as its backend.
  Investigators can find cohorts, see which subjects need attention first and
  open a subject's AE history, without writing code. It also answers
  plain-English questions that can combine conditions (e.g. "severe headaches
  on placebo"), building on the Question 6 agent. It reuses the Question 5 and
  6 code unchanged, adds four endpoints, and has its own tests.

