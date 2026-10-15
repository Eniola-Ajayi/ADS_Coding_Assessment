# =============================================================================
# Program : 02_create_visualizations.R
# Purpose : Two adverse event graphs with {ggplot2}:
#             Plot 1 - AE severity distribution by treatment (stacked bars)
#             Plot 2 - Top 10 most frequent AEs with 95% Clopper-Pearson CIs
# Input   : pharmaverseadam::adae
# Output  : question_4_tlg/output/ae_severity_by_treatment.png
#           question_4_tlg/output/top10_ae_incidence.png
#
# Note: both plots use all AE records in ADAE, matching the sample outputs in
#       the brief (e.g. "n = 225 subjects" = all subjects with an AE record).
# =============================================================================

library(dplyr, warn.conflicts = FALSE)
library(ggplot2)

adae <- pharmaverseadam::adae

out_dir <- file.path("question_4_tlg", "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# Plot 1: AE severity distribution by treatment
#   Each bar counts AE records in an arm, split by severity (AESEV).
# =============================================================================
severity_counts <- adae %>%
  filter(!is.na(AESEV)) %>%
  mutate(AESEV = factor(AESEV, levels = c("MILD", "MODERATE", "SEVERE"))) %>%
  count(ACTARM, AESEV, name = "n_events")

plot_severity <- ggplot(severity_counts, aes(x = ACTARM, y = n_events, fill = AESEV)) +
  geom_col(width = 0.8) +
  labs(
    title = "AE severity distribution by treatment",
    x = "Treatment Arm",
    y = "Count of AEs",
    fill = "Severity/Intensity"
  ) +
  theme_gray(base_size = 12)

ggsave(
  file.path(out_dir, "ae_severity_by_treatment.png"),
  plot_severity, width = 8, height = 6, dpi = 300
)

# =============================================================================
# Plot 2: Top 10 most frequent AEs with 95% confidence intervals
#
#   Incidence = subjects with the event / all subjects in ADAE.
#   Each subject is counted once per term (distinct USUBJID x AETERM).
#   95% CIs use the exact Clopper-Pearson method. It has a closed form via the
#   beta distribution (identical to stats::binom.test()$conf.int) and is
#   vectorised:
#     lower = qbeta(alpha / 2,     x,     n - x + 1)   (0 when x = 0)
#     upper = qbeta(1 - alpha / 2, x + 1, n - x)       (1 when x = n)
# =============================================================================
n_subjects <- n_distinct(adae$USUBJID)

clopper_pearson <- function(x, n, conf_level = 0.95) {
  alpha <- 1 - conf_level
  tibble(
    lower = if_else(x == 0, 0, stats::qbeta(alpha / 2, x, n - x + 1)),
    upper = if_else(x == n, 1, stats::qbeta(1 - alpha / 2, x + 1, n - x))
  )
}

top10 <- adae %>%
  filter(!is.na(AETERM)) %>%
  distinct(USUBJID, AETERM) %>%            # one count per subject per term
  count(AETERM, name = "n_subj") %>%
  slice_max(n_subj, n = 10, with_ties = FALSE) %>%
  mutate(pct = n_subj / n_subjects) %>%
  bind_cols(clopper_pearson(.$n_subj, n_subjects)) %>%
  mutate(AETERM = reorder(AETERM, pct))     # most frequent at the top

plot_top10 <- ggplot(top10, aes(x = pct, y = AETERM)) +
  geom_errorbar(aes(xmin = lower, xmax = upper), width = 0.25, orientation = "y") +
  geom_point(size = 3) +
  scale_x_continuous(labels = scales::percent) +
  labs(
    title = "Top 10 Most Frequent Adverse Events",
    subtitle = sprintf("n = %d subjects; 95%% Clopper-Pearson CIs", n_subjects),
    x = "Percentage of Patients (%)",
    y = NULL
  ) +
  theme_gray(base_size = 12)

ggsave(
  file.path(out_dir, "top10_ae_incidence.png"),
  plot_top10, width = 8, height = 6, dpi = 300
)

message("Saved plots to ", out_dir)
print(top10)
