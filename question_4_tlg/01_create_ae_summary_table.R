# =============================================================================
# Program : 01_create_ae_summary_table.R
# Purpose : Summary table of treatment-emergent adverse events (TEAEs) by
#           system organ class and reported term, by actual treatment arm.
#           Modelled on FDA Table 10 from the pharmaverse {cardinal} catalogue.
# Input   : pharmaverseadam::adae, pharmaverseadam::adsl
# Output  : question_4_tlg/output/ae_summary_table.html
# =============================================================================

library(dplyr, warn.conflicts = FALSE)
library(gtsummary)
library(gt)

# -----------------------------------------------------------------------------
# 1. Data
#    Denominator (N per arm): the safety population from ADSL, which excludes
#    screen failures. The `by` variable (ACTARM) must exist in both datasets.
# -----------------------------------------------------------------------------
adsl <- pharmaverseadam::adsl %>%
  filter(SAFFL == "Y")

adae <- pharmaverseadam::adae %>%
  filter(
    SAFFL == "Y",
    TRTEMFL == "Y"   # treatment-emergent AEs only
  )

# -----------------------------------------------------------------------------
# 2. Hierarchical summary: SOC -> reported term
#    tbl_hierarchical() counts each SUBJECT once per row (id = USUBJID), so
#    cells are "number of subjects with at least one such event (%)".
#    overall_row = TRUE adds the top "any TEAE" row across all subjects.
#    sort_hierarchical() orders SOCs, and terms within each SOC, by
#    descending frequency.
# -----------------------------------------------------------------------------
ae_table <- adae %>%
  tbl_hierarchical(
    variables   = c(AESOC, AETERM),
    by          = ACTARM,
    id          = USUBJID,
    denominator = adsl,
    overall_row = TRUE,
    label       = list(
      "..ard_hierarchical_overall.." ~ "Treatment Emergent AEs",
      AESOC ~ "Primary System Organ Class",
      AETERM ~ "Reported Term for the Adverse Event"
    )
  ) %>%
  sort_hierarchical(sort = everything() ~ "descending") %>%
  modify_caption(
    "**Table 1. Subjects with Treatment-Emergent Adverse Events by System Organ Class and Reported Term (Safety Population)**"
  )

# -----------------------------------------------------------------------------
# 3. Render to HTML
# -----------------------------------------------------------------------------
out_dir <- file.path("question_4_tlg", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

ae_table %>%
  as_gt() %>%
  tab_source_note(
    "Treatment-emergent AEs: TRTEMFL = 'Y'. Subjects are counted once per system organ class and once per term. Percentages use the number of subjects in each arm of the safety population as the denominator."
  ) %>%
  gtsave(file.path(out_dir, "ae_summary_table.html"))

message("Saved: ", file.path(out_dir, "ae_summary_table.html"))
