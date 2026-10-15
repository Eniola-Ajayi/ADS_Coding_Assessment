# =============================================================================
# Program : 03_create_listings.R
# Purpose : Listing of treatment-emergent adverse events by subject.
# Input   : pharmaverseadam::adae
# Output  : question_4_tlg/output/ae_listings.html
#
# Columns : Subject ID, treatment, AE term, severity, relationship to study
#           drug, start and end date/time
# Filter  : treatment-emergent events (TRTEMFL == "Y"), excluding screen
#           failures
# Sort    : subject, then event start date
#
# {gtsummary} produces summary tables rather than record-level listings, so
# the listing is rendered with {gt}, the table engine {gtsummary} is built
# on. As in a typical clinical listing, the subject ID and treatment are
# shown only on the first row of each subject.
# =============================================================================

library(dplyr, warn.conflicts = FALSE)
library(gt)

ae_listing <- pharmaverseadam::adae %>%
  filter(
    TRTEMFL == "Y",
    ACTARM != "Screen Failure"
  ) %>%
  arrange(USUBJID, ASTDT, AESTDTC, AETERM) %>%
  select(
    USUBJID, ACTARM, AETERM, AESEV, AEREL, AESTDTC, AEENDTC
  ) %>%
  # Show subject-level columns only on the first row of each subject
  group_by(USUBJID) %>%
  mutate(
    first_row = row_number() == 1L,
    ACTARM    = if_else(first_row, ACTARM, ""),
    USUBJID_d = if_else(first_row, USUBJID, "")
  ) %>%
  ungroup() %>%
  select(USUBJID = USUBJID_d, ACTARM, AETERM, AESEV, AEREL, AESTDTC, AEENDTC) %>%
  mutate(across(everything(), ~ if_else(is.na(.x) | .x == "", "", as.character(.x))))

listing_gt <- ae_listing %>%
  mutate(across(c(AESTDTC, AEENDTC), ~ if_else(.x == "", "NA", .x))) %>%
  gt() %>%
  tab_header(
    title = "Listing of Treatment-Emergent Adverse Events by Subject",
    subtitle = "Excluding Screen Failure Patients"
  ) %>%
  cols_label(
    USUBJID = "Unique Subject Identifier",
    ACTARM  = "Description of Actual Arm",
    AETERM  = "Reported Term for the Adverse Event",
    AESEV   = "Severity/Intensity",
    AEREL   = "Causality",
    AESTDTC = "Start Date/Time of Adverse Event",
    AEENDTC = "End Date/Time of Adverse Event"
  ) %>%
  opt_table_font(font = "Courier New") %>%
  tab_options(
    table.font.size = px(11),
    data_row.padding = px(2),
    heading.align = "left",
    column_labels.font.weight = "bold"
  ) %>%
  tab_source_note("Source: ADAE. Sorted by subject and AE start date. TRTEMFL = 'Y'.")

out_dir <- file.path("question_4_tlg", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
gtsave(listing_gt, file.path(out_dir, "ae_listings.html"))

message(
  "Saved: ", file.path(out_dir, "ae_listings.html"),
  " (", nrow(ae_listing), " AE records)"
)
