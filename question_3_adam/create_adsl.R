# =============================================================================
# Program : create_adsl.R
# Purpose : Create the ADaM Subject-Level Analysis Dataset (ADSL) from SDTM
#           source data using {admiral} and tidyverse tools.
# Input   : pharmaversesdtm::dm, ex, vs, ds, ae
#           pharmaverseadam::adsl (independent check only, section 10b)
# Output  : question_3_adam/output/adsl.rds and adsl.csv
#
# Derived variables (per the assessment specification):
#   AGEGR9 / AGEGR9N   Age group "<18", "18 - 50", ">50"  (1, 2, 3)
#   TRTSDTM / TRTSTMF  Treatment start datetime (first valid-dose exposure)
#                      and its time imputation flag
#   TRTEDTM / TRTETMF  Treatment end datetime (last valid-dose exposure),
#                      needed for LSTALVDT
#   TRTSDT / TRTEDT    Date parts of the above
#   ITTFL              "Y" if randomised (DM.ARM populated, not "Screen Failure")
#   ABNSBPFL           "Y" if any systolic BP (mmHg) >= 140 or < 100, else "N"
#   LSTALVDT           Last known alive date (VS, AE, DS, exposure)
#   CARPOPFL           "Y" if any AE with SOC "CARDIAC DISORDERS", else NA
#
# Approach follows the {admiral} "Creating ADSL" vignette:
#   https://pharmaverse.github.io/admiral/cran-release/articles/adsl.html
# =============================================================================

library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(stringr)
library(pharmaversesdtm)

# -----------------------------------------------------------------------------
# 1. Read SDTM data
#    convert_blanks_to_na() turns SAS-style "" into NA so that is.na() checks
#    behave as expected in R.
# -----------------------------------------------------------------------------
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)

# -----------------------------------------------------------------------------
# 2. Start ADSL from DM (one record per subject)
# -----------------------------------------------------------------------------
adsl_1 <- dm %>%
  select(-DOMAIN) %>%
  mutate(TRT01P = ARM, TRT01A = ACTARM)

# -----------------------------------------------------------------------------
# 3. AGEGR9 / AGEGR9N: age groups based on DM.AGE
#    derive_vars_cat() creates both variables from one lookup table.
#    The first matching condition wins; missing AGE gives NA for both.
# -----------------------------------------------------------------------------
agegr9_lookup <- exprs(
  ~condition,           ~AGEGR9,   ~AGEGR9N,
  AGE < 18,             "<18",     1,
  between(AGE, 18, 50), "18 - 50", 2,
  AGE > 50,             ">50",     3
)

adsl_2 <- adsl_1 %>%
  derive_vars_cat(definition = agegr9_lookup)

# -----------------------------------------------------------------------------
# 4. TRTSDTM / TRTSTMF and TRTEDTM / TRTETMF
#
#    EXSTDTC/EXENDTC are converted to numeric datetimes with:
#      highest_imputation = "h": only the TIME part may be imputed. If any part
#        of the DATE is missing the result is NA, so incomplete dates are
#        excluded (spec: "datepart ... is complete").
#      time_imputation = "first" (start) / "last" (end): completely missing
#        time -> 00:00:00 (start); missing hours/minutes/seconds -> 00.
#      ignore_seconds_flag = TRUE: if ONLY the seconds are missing, the time
#        imputation flag (*TMF) is NOT populated (spec requirement).
# -----------------------------------------------------------------------------
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    highest_imputation = "h",
    time_imputation = "first",
    ignore_seconds_flag = TRUE
  ) %>%
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    highest_imputation = "h",
    time_imputation = "last",
    ignore_seconds_flag = TRUE
  )


adsl_3 <- adsl_2 %>%
  # First valid-dose exposure, sorted in date/time order -> TRTSDTM.
  # Valid dose: EXDOSE > 0, or EXDOSE == 0 for a placebo treatment.
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(toupper(EXTRT), "PLACEBO"))) &
      !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  ) %>%
  # Last valid-dose exposure -> TRTEDTM (used for LSTALVDT below)
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(toupper(EXTRT), "PLACEBO"))) &
      !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  ) %>%
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))

# -----------------------------------------------------------------------------
# 5. ITTFL: "Y" if the subject was randomised, else "N"
#    The spec contradicts itself: the detailed rule (DM.ARM not missing) flags
#    all 306 subjects, because screen failures carry ARM = "Screen Failure"
#    rather than a missing value. This follows the intent ("randomized")
#    instead, giving 254: the same as the CDISC Pilot ITT population.
# -----------------------------------------------------------------------------
adsl_4 <- adsl_3 %>%
  mutate(ITTFL = if_else(!is.na(ARM) & ARM != "Screen Failure", "Y", "N"))

# -----------------------------------------------------------------------------
# 6. ABNSBPFL: "Y" if any systolic BP observation in mmHg is >= 140 or < 100,
#    "N" otherwise (including subjects with no vital signs).
#    The headline says "supine" but the detailed spec does not restrict by
#    position, so all positions are included. In normal work this would be
#    clarified with the spec author; if supine only is confirmed, add
#    `& VSPOS == "SUPINE"` to the condition.
# -----------------------------------------------------------------------------
adsl_5 <- adsl_4 %>%
  derive_var_merged_exist_flag(
    dataset_add = vs,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = ABNSBPFL,
    condition = VSTESTCD == "SYSBP" & VSSTRESU == "mmHg" &
      (VSSTRESN >= 140 | VSSTRESN < 100),
    false_value = "N",
    missing_value = "N"
  )

# -----------------------------------------------------------------------------
# 7. LSTALVDT: last date the subject is known to be alive. The maximum of:
#    (1) last complete VS date with a valid result (VSSTRESN and VSSTRESC
#        not both missing)
#    (2) last complete AE onset date (AESTDTC)
#    (3) last complete disposition date (DSSTDTC)
#    (4) last valid-dose treatment date (date part of TRTEDTM)
#
#    convert_dtc_to_dt() without imputation (the default) returns NA for a
#    partial date, so a non-missing converted date means the date is COMPLETE.
#    The dates are added as columns first, so each event condition below only
#    refers to variables of its source dataset.
# -----------------------------------------------------------------------------
vs_dt <- vs %>% mutate(VSDT = convert_dtc_to_dt(VSDTC))
ae_dt <- ae %>% mutate(AESTDT = convert_dtc_to_dt(AESTDTC))
ds_dt <- ds %>% mutate(DSSTDT = convert_dtc_to_dt(DSSTDTC))

adsl_6 <- adsl_5 %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      # (1) Vital signs with a complete date and a valid test result
      event(
        dataset_name = "vs",
        order = exprs(VSDT, VSSEQ),
        condition = !is.na(VSDT) & !(is.na(VSSTRESN) & is.na(VSSTRESC)),
        set_values_to = exprs(LSTALVDT = VSDT, seq = VSSEQ)
      ),
      # (2) Adverse event onset (complete date)
      event(
        dataset_name = "ae",
        order = exprs(AESTDT, AESEQ),
        condition = !is.na(AESTDT),
        set_values_to = exprs(LSTALVDT = AESTDT, seq = AESEQ)
      ),
      # (3) Disposition (complete date)
      event(
        dataset_name = "ds",
        order = exprs(DSSTDT, DSSEQ),
        condition = !is.na(DSSTDT),
        set_values_to = exprs(LSTALVDT = DSSTDT, seq = DSSEQ)
      ),
      # (4) Last valid-dose treatment date
      event(
        dataset_name = "adsl_5",
        condition = !is.na(TRTEDT),
        set_values_to = exprs(LSTALVDT = TRTEDT, seq = 0)
      )
    ),
    source_datasets = list(vs = vs_dt, ae = ae_dt, ds = ds_dt, adsl_5 = adsl_5),
    tmp_event_nr_var = event_nr,
    order = exprs(LSTALVDT, seq, event_nr),
    mode = "last",
    new_vars = exprs(LSTALVDT)
  )

# -----------------------------------------------------------------------------
# 8. CARPOPFL: "Y" if the subject has any AE whose (upper-cased) system organ
#    class is "CARDIAC DISORDERS"; otherwise missing (NA).
# -----------------------------------------------------------------------------
adsl_final <- adsl_6 %>%
  derive_var_merged_exist_flag(
    dataset_add = ae,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = CARPOPFL,
    condition = toupper(AESOC) == "CARDIAC DISORDERS"
    # false_value / missing_value default to NA, as specified
  )

# -----------------------------------------------------------------------------
# 9. Final dataset: DM variables first, then the derived variables
# -----------------------------------------------------------------------------
derived_vars <- c(
  "TRT01P", "TRT01A", "AGEGR9", "AGEGR9N",
  "TRTSDTM", "TRTSTMF", "TRTEDTM", "TRTETMF", "TRTSDT", "TRTEDT",
  "ITTFL", "ABNSBPFL", "LSTALVDT", "CARPOPFL"
)

adsl <- adsl_final %>%
  select(-all_of(derived_vars), all_of(derived_vars)) %>%
  arrange(STUDYID, USUBJID)

# -----------------------------------------------------------------------------
# 10. Quality checks
# -----------------------------------------------------------------------------
stopifnot(
  "ADSL must have one record per subject" = !anyDuplicated(adsl$USUBJID),
  "ADSL must contain every DM subject"    = nrow(adsl) == nrow(dm),
  "LSTALVDT must not precede TRTSDT" =
    all(is.na(adsl$TRTSDT) | is.na(adsl$LSTALVDT) | adsl$LSTALVDT >= adsl$TRTSDT)
)

message("ADSL created: ", nrow(adsl), " subjects, ", ncol(adsl), " variables")
print(count(adsl, AGEGR9N, AGEGR9))
print(count(adsl, ITTFL))
print(count(adsl, ABNSBPFL))
print(count(adsl, CARPOPFL))
print(count(adsl, TRTSTMF))

# -----------------------------------------------------------------------------
# 10b. Independent checks (information only: the script does not stop on
#      differences)
#  (a) Treatment dates vs pharmaverseadam::adsl. That dataset is built from
#      the same SDTM data with the {admiral} ADSL template, which uses the
#      same TRTSDTM/TRTEDTM rules as this spec.
#  (b) LSTALVDT is re-derived independently with plain dplyr (no admiral).
#      It cannot be compared with pharmaverseadam::adsl, because the template
#      uses different sources (AE start/end, LB, exposure) from this spec
#      (VS, AE start, DS, exposure).
#  (c) AGEGR9/AGEGR9N, ABNSBPFL and CARPOPFL are specific to this spec (not in
#      pharmaverseadam::adsl) and ITTFL follows this spec's rule, so they are
#      also re-derived independently with plain dplyr.
# -----------------------------------------------------------------------------
reference <- pharmaverseadam::adsl

trt_vars <- intersect(
  c("TRTSDTM", "TRTSTMF", "TRTEDTM", "TRTETMF", "TRTSDT", "TRTEDT"),
  names(reference)
)

# (b) A complete date is an ISO 8601 string starting YYYY-MM-DD
complete_date <- function(dtc) {
  as.Date(ifelse(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", dtc), substr(dtc, 1, 10), NA_character_))
}

lstalvdt_check <- bind_rows(
  vs %>%
    filter(!(is.na(VSSTRESN) & is.na(VSSTRESC))) %>%
    transmute(USUBJID, dt = complete_date(VSDTC)),
  ae %>% transmute(USUBJID, dt = complete_date(AESTDTC)),
  ds %>% transmute(USUBJID, dt = complete_date(DSSTDTC)),
  adsl %>% transmute(USUBJID, dt = TRTEDT)
) %>%
  filter(!is.na(dt)) %>%
  group_by(USUBJID) %>%
  summarise(LSTALVDT.ref = max(dt), .groups = "drop")

# (c) Subjects with an abnormal systolic BP, and with a cardiac AE
abnsbp_subjects <- vs %>%
  filter(VSTESTCD == "SYSBP", VSSTRESU == "mmHg", VSSTRESN >= 140 | VSSTRESN < 100) %>%
  pull(USUBJID)
cardiac_subjects <- ae %>%
  filter(toupper(AESOC) == "CARDIAC DISORDERS") %>%
  pull(USUBJID)

flags_check <- dm %>%
  transmute(
    USUBJID,
    AGEGR9.ref   = case_when(AGE < 18 ~ "<18", AGE <= 50 ~ "18 - 50", AGE > 50 ~ ">50"),
    AGEGR9N.ref  = case_when(AGE < 18 ~ 1, AGE <= 50 ~ 2, AGE > 50 ~ 3),
    ITTFL.ref    = if_else(is.na(ARM) | ARM == "Screen Failure", "N", "Y"),
    ABNSBPFL.ref = if_else(USUBJID %in% abnsbp_subjects, "Y", "N"),
    CARPOPFL.ref = if_else(USUBJID %in% cardiac_subjects, "Y", NA_character_)
  )
flag_vars <- c("AGEGR9", "AGEGR9N", "ITTFL", "ABNSBPFL", "CARPOPFL")

qc <- adsl %>%
  select(STUDYID, USUBJID, all_of(c(trt_vars, "LSTALVDT", flag_vars))) %>%
  inner_join(
    reference[c("STUDYID", "USUBJID", trt_vars)],
    by = c("STUDYID", "USUBJID"), suffix = c("", ".ref")
  ) %>%
  left_join(lstalvdt_check, by = "USUBJID") %>%
  left_join(flags_check, by = "USUBJID")

qc_vars <- c(trt_vars, "LSTALVDT", flag_vars)

# Dates and datetimes are compared as numbers, everything else as text
as_comparable <- function(x) {
  if (inherits(x, c("POSIXct", "Date"))) as.character(as.numeric(x)) else as.character(x)
}
n_matching <- function(v) {
  a <- as_comparable(qc[[v]])
  b <- as_comparable(qc[[paste0(v, ".ref")]])
  sum((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
}

message("Subjects matched to pharmaverseadam::adsl: ", nrow(qc), " of ", nrow(adsl))
print(tibble(
  variable = qc_vars,
  compared_with = c(
    rep("pharmaverseadam::adsl", length(trt_vars)),
    rep("independent re-derivation", 1 + length(flag_vars))
  ),
  records_compared = nrow(qc),
  matching = vapply(qc_vars, n_matching, numeric(1))
))

# -----------------------------------------------------------------------------
# 11. Save
# -----------------------------------------------------------------------------
out_dir <- file.path("question_3_adam", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(adsl, file.path(out_dir, "adsl.rds"))

# R leaves out a midnight time (00:00:00) when printing or writing a datetime,
# so the imputed time in TRTSDTM would look missing in the CSV. Write the
# datetimes as ISO 8601 text instead (the .rds keeps them as datetimes).
adsl_csv <- adsl %>%
  mutate(across(c(TRTSDTM, TRTEDTM), ~ format(.x, "%Y-%m-%dT%H:%M:%S", tz = "UTC")))
write.csv(adsl_csv, file.path(out_dir, "adsl.csv"), row.names = FALSE, na = "")
