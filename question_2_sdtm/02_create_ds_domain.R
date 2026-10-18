# =============================================================================
# Program : 02_create_ds_domain.R
# Purpose : Create the SDTM Disposition (DS) domain from raw data with
#           {sdtm.oak}, following the approach of the pharmaverse SDTM AE
#           example (https://pharmaverse.github.io/examples/sdtm/ae.html).
# Input   : pharmaverseraw::ds_raw           raw disposition data (eCRF)
#           pharmaversesdtm::dm              for study day derivation
#           question_2_sdtm/metadata/sdtm_ct.csv  study controlled terminology
# Output  : question_2_sdtm/output/ds.rds and ds.csv
# Variables: STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
#            VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
#
# Run from the repository root.
#
# Raw data -> SDTM mapping (from the Subject Disposition aCRF and the
# structure of ds_raw):
#   STUDY                -> STUDYID
#   PATNUM               -> USUBJID = "01-" || PATNUM
#   IT.DSTERM / OTHERSP  -> DSTERM  (OTHERSP is used for "other" events,
#                                    where IT.DSTERM is not collected)
#   IT.DSDECOD / OTHERSP -> DSDECOD (C66727 "Completion/Reason for
#                                    Non-Completion" codelist; "Randomized"
#                                    is a protocol milestone)
#   derived              -> DSCAT   PROTOCOL MILESTONE / DISPOSITION EVENT /
#                                    OTHER EVENT
#   INSTANCE             -> VISIT, VISITNUM (study visit codelists)
#   DSDTCOL + DSTMCOL    -> DSDTC   (date/time of collection)
#   IT.DSSTDAT           -> DSSTDTC (start date of the disposition event)
#   DSSTDTC vs DM.RFSTDTC -> DSSTDY
# =============================================================================

library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr, warn.conflicts = FALSE)

# -----------------------------------------------------------------------------
# 1. Read in data
# -----------------------------------------------------------------------------
ds_raw <- pharmaverseraw::ds_raw
dm <- pharmaversesdtm::dm

# -----------------------------------------------------------------------------
# 2. Create oak_id_vars
#    Adds oak_id, raw_source and patient_number: the keys sdtm.oak uses to
#    join every mapped variable back to the corresponding raw record.
# -----------------------------------------------------------------------------
ds_raw <- ds_raw %>%
  generate_oak_id_vars(
    pat_var = "PATNUM",
    raw_src = "ds_raw"
  )

# -----------------------------------------------------------------------------
# 3. Read in study controlled terminology
#    Contains the C66727 (NCOMPLT) codelist given in the assessment brief plus
#    the study VISIT / VISITNUM codelists from the pharmaverse examples
#    repository (metadata/sdtm_ct.csv).
# -----------------------------------------------------------------------------
study_ct <- read.csv(
  file.path("question_2_sdtm", "metadata", "sdtm_ct.csv"),
  stringsAsFactors = FALSE,
  na.strings = ""
)

#note on the "terms could not be mapped per the controlled terminology" messages in the log:
#assign_ct() only maps raw values that exactly match (case-sensitive) collected_value or term_synonyms,
#e.g. raw "Completed" vs "Complete", "Screen Failure" vs "Trial Screen Failure", and unscheduled visits
#not in the VISIT codelist. unmatched values fall back to upper case, which gives the correct CDISC
#values (step 9 QC: 850/850 match). "Randomized" is also listed but is hardcoded in step 5 (a).
#fix: add the raw spellings to term_synonyms in sdtm_ct.csv so every value maps exactly.

# -----------------------------------------------------------------------------
# 4. Map the topic variable: DSTERM
#    Disposition events and protocol milestones: the collected reason
#    IT.DSTERM. "Other" events (e.g. final lab visit) are recorded in the
#    free-text OTHERSP field instead, with IT.DSTERM left blank.
#    When a target variable is mapped again, sdtm.oak only fills records that
#    are still missing, so the second call fills just the OTHERSP records.
# -----------------------------------------------------------------------------
ds_1 <-
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "IT.DSTERM",
    tgt_var = "DSTERM",
    id_vars = oak_id_vars()
  ) %>%
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "OTHERSP",
    tgt_var = "DSTERM",
    id_vars = oak_id_vars()
  )

# -----------------------------------------------------------------------------
# 5. Map the qualifier, identifier and timing variables
# -----------------------------------------------------------------------------
ds_2 <- ds_1 %>%
  # --- DSDECOD -------------------------------------------------------------
  # (a) Randomisation is a protocol milestone, not a reason for
  #     non-completion, so it is not in C66727: hardcode its decode.
  #     Conditions use %in% / !is.na() so that missing IT.DSDECOD values
  #     (the "other" events) evaluate to FALSE rather than NA.
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, IT.DSDECOD %in% "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSDECOD",
    tgt_val = "RANDOMIZED",
    id_vars = oak_id_vars()
  ) %>%
  # (b) All other collected decodes are mapped with the C66727 codelist.
  #     Values with no exact match in the codelist are returned upper-cased
  #     by sdtm.oak (and listed in a message), which gives the CDISC
  #     submission value (e.g. "Completed" -> "COMPLETED").
  assign_ct(
    raw_dat = condition_add(ds_raw, !is.na(IT.DSDECOD) & IT.DSDECOD != "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSDECOD",
    ct_spec = study_ct,
    ct_clst = "C66727",
    id_vars = oak_id_vars()
  ) %>%
  # (c) "Other" events: the decode is the OTHERSP term (upper-cased below).
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "OTHERSP",
    tgt_var = "DSDECOD",
    id_vars = oak_id_vars()
  ) %>%
  # --- DSCAT ---------------------------------------------------------------
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, IT.DSDECOD %in% "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "PROTOCOL MILESTONE",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, !is.na(IT.DSDECOD) & IT.DSDECOD != "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "DISPOSITION EVENT",
    id_vars = oak_id_vars()
  ) %>%
  hardcode_no_ct(
    raw_dat = ds_raw,
    raw_var = "OTHERSP",       # only records where OTHERSP is populated
    tgt_var = "DSCAT",
    tgt_val = "OTHER EVENT",
    id_vars = oak_id_vars()
  ) %>%
  # --- VISIT -----------------------------------------------------------------
  # Mapped from INSTANCE with the study VISIT codelist. INSTANCE values that
  # differ only in case from the codelist (e.g. "Ambul Ecg Removal") fall back
  # to upper case, which is the correct VISIT value.
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISIT",
    ct_spec = study_ct,
    ct_clst = "VISIT",
    id_vars = oak_id_vars()
  ) %>%
  # --- DSDTC: date (MM-DD-YYYY) + time (HH:MM) of collection ----------------
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL", "DSTMCOL"),
    tgt_var = "DSDTC",
    raw_fmt = c("m-d-y", "H:M"),
    id_vars = oak_id_vars()
  ) %>%
  # --- DSSTDTC: start date of the disposition event (MM-DD-YYYY) ------------
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    tgt_var = "DSSTDTC",
    raw_fmt = c("m-d-y"),
    id_vars = oak_id_vars()
  ) %>%
  # --- STUDYID ---------------------------------------------------------------
  assign_no_ct(
    raw_dat = ds_raw,
    raw_var = "STUDY",
    tgt_var = "STUDYID",
    id_vars = oak_id_vars()
  )

# -----------------------------------------------------------------------------
# 6. VISITNUM
#    Looked up from the mapped VISIT using the study VISITNUM codelist.
#    Matching on the standardised VISIT (rather than mapping INSTANCE a second
#    time) means case differences in the raw INSTANCE cannot produce a
#    non-numeric VISITNUM.
#    The codelist only lists one unscheduled visit (3.1). Unscheduled visits
#    are numbered by their label, so for the others VISITNUM is the number in
#    the label: "UNSCHEDULED 4.1" -> 4.1.
# -----------------------------------------------------------------------------
visitnum_lookup <- study_ct %>%
  filter(codelist_code == "VISITNUM") %>%
  transmute(VISIT = toupper(collected_value), VISITNUM = as.numeric(term_value)) %>%
  distinct(VISIT, .keep_all = TRUE)

ds_3 <- ds_2 %>%
  left_join(visitnum_lookup, by = "VISIT") %>%
  mutate(
    VISITNUM = coalesce(
      VISITNUM,
      as.numeric(stringr::str_match(VISIT, "^UNSCHEDULED (\\d+(?:\\.\\d+)?)$")[, 2])
    )
  )

# -----------------------------------------------------------------------------
# 7. SDTM derived variables
# -----------------------------------------------------------------------------
ds <- ds_3 %>%
  mutate(
    DOMAIN  = "DS",
    USUBJID = paste0("01-", patient_number),
    DSTERM  = toupper(DSTERM),   # raw terms are title case
    DSDECOD = toupper(DSDECOD),
    # --DTC variables are ISO 8601 character strings in SDTM; drop the
    # sdtm.oak "iso8601" class so they are plain character columns.
    across(c(DSDTC, DSSTDTC), as.character)
  ) %>%
  derive_seq(
    tgt_var = "DSSEQ",
    rec_vars = c("USUBJID", "DSSTDTC", "DSCAT", "DSDECOD")
  ) %>%
  # Study day relative to the reference start date (DM.RFSTDTC), as defined
  # in the SDTMIG: no day 0, days before the reference date are negative.
  # derive_study_day() converts the target date column to class Date, so the
  # ISO 8601 string is kept in a copy and put back afterwards.
  mutate(DSSTDTC_ISO = DSSTDTC) %>%
  derive_study_day(
    sdtm_in = .,
    dm_domain = dm,
    tgdt = "DSSTDTC",
    refdt = "RFSTDTC",
    study_day_var = "DSSTDY"
  ) %>%
  mutate(DSSTDTC = DSSTDTC_ISO) %>%
  select(
    "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", "DSCAT",
    "VISITNUM", "VISIT", "DSDTC", "DSSTDTC", "DSSTDY"
  ) %>%
  arrange(USUBJID, DSSEQ)

# -----------------------------------------------------------------------------
# 8. Checks
# -----------------------------------------------------------------------------
stopifnot(
  "Every raw record must produce one DS record" = nrow(ds) == nrow(ds_raw),
  "DSSEQ must be unique within subject" = !anyDuplicated(ds[c("USUBJID", "DSSEQ")]),
  "DSCAT must always be populated" = !anyNA(ds$DSCAT),
  "DSDECOD must always be populated" = !anyNA(ds$DSDECOD),
  "VISITNUM must be populated for every visit" = !anyNA(ds$VISITNUM[!is.na(ds$VISIT)]),
  "DSDTC/DSSTDTC must be character" = is.character(ds$DSDTC) && is.character(ds$DSSTDTC)
)

message("DS domain created: ", nrow(ds), " records, ",
        n_distinct(ds$USUBJID), " subjects")
print(count(ds, DSCAT, DSDECOD))
print(count(ds, VISITNUM, VISIT))

# -----------------------------------------------------------------------------
# 9. Independent check against the published SDTM DS dataset
#    pharmaverseraw::ds_raw was created from pharmaversesdtm::ds, so the
#    re-derived DS should reproduce it. Records are matched on subject, decode
#    and start date, then each variable is compared.
# -----------------------------------------------------------------------------
reference <- pharmaversesdtm::ds %>%
  mutate(across(where(is.character), ~ na_if(.x, "")))

key <- c("USUBJID", "DSDECOD", "DSSTDTC")
compare_vars <- c("STUDYID", "DSTERM", "DSCAT", "VISITNUM", "VISIT", "DSDTC", "DSSTDY")

comparison <- inner_join(
  ds, reference,
  by = key, suffix = c("", ".ref"), relationship = "many-to-many"
)

same_value <- function(a, b) {
  a <- as.character(a)
  b <- as.character(b)
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
}

qc_summary <- tibble(
  variable = compare_vars,
  records_compared = nrow(comparison),
  matching = vapply(
    compare_vars,
    function(v) sum(same_value(comparison[[v]], comparison[[paste0(v, ".ref")]])),
    numeric(1)
  )
)

message("Records matched to pharmaversesdtm::ds on ", paste(key, collapse = ", "),
        ": ", nrow(comparison), " of ", nrow(ds))
print(qc_summary)

# -----------------------------------------------------------------------------
# 10. Save
# -----------------------------------------------------------------------------
out_dir <- file.path("question_2_sdtm", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(ds, file.path(out_dir, "ds.rds"))
write.csv(ds, file.path(out_dir, "ds.csv"), row.names = FALSE, na = "")
