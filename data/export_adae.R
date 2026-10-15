# =============================================================================
# Program : export_adae.R
# Purpose : Export the adverse events data used by the Python questions
#           (Question 5 API and Question 6 GenAI assistant) to data/adae.csv.
#
# Why ADaM ADAE rather than SDTM AE:
#   Question 5 filters on the actual treatment arm (ACTARM), which is not part
#   of the SDTM AE domain (pharmaversesdtm::ae). pharmaverseadam::adae is
#   derived from SDTM AE and already carries ACTARM from ADSL, alongside the
#   SDTM AE variables both questions need (USUBJID, AETERM, AEDECOD, AESOC,
#   AESEV, ...). Exporting one file keeps both questions consistent.
#
# Run from the repository root.
# =============================================================================

library(dplyr, warn.conflicts = FALSE)

adae <- pharmaverseadam::adae %>%
  select(
    STUDYID, USUBJID, ACTARM, AESEQ, AETERM, AEDECOD, AEBODSYS, AESOC,
    AESEV, AESER, AEREL, AEOUT, AESTDTC, AEENDTC, TRTEMFL
  )

dir.create("data", showWarnings = FALSE)
write.csv(adae, file.path("data", "adae.csv"), row.names = FALSE, na = "")

message("Wrote data/adae.csv: ", nrow(adae), " records, ",
        n_distinct(adae$USUBJID), " subjects")
