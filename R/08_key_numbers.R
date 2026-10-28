# 08_key_numbers.R
#
# Collects the headline numbers from every stage into one short Markdown file,
# used to write the findings section of the README.
#
# Run from the project root after 05_its.R:
#   Rscript R/08_key_numbers.R
#
# Output: output/key_numbers.md

library(dplyr)
library(readr)
source(file.path("R", "plot_theme.R"))

scotland_code <- "S92000003"
base_year <- 2019
tab <- function(name) read_csv(file.path("output", "tables", name), show_col_types = FALSE)

annual <- tab("annual_rates.csv")
ineq <- tab("inequality_annual.csv")
its <- tab("its_results.csv")
eff <- tab("its_effect_at_end.csv")
quarterly <- read_csv(file.path("data", "processed", "emergency_admissions_simd.csv"),
                      show_col_types = FALSE)

full_year <- latest_complete_fy(annual)

scot_ineq <- ineq |>
  filter(hb == scotland_code) |>
  select(financial_year, provisional, rate_q1, rate_q5, rate_ratio, rate_diff, sii, rii)

boards <- ineq |>
  filter(hb != scotland_code, year %in% c(base_year, full_year)) |>
  select(hb_name, year, rate_ratio, rii) |>
  tidyr::pivot_wider(names_from = year, values_from = c(rate_ratio, rii)) |>
  rename_with(~ sub(paste0("_", base_year), "_before", .x)) |>
  rename_with(~ sub(paste0("_", full_year), "_after", .x)) |>
  mutate(rii_change = rii_after - rii_before) |>
  arrange(desc(rate_ratio_after))

fmt <- function(df) {
  df <- mutate(df, across(where(is.numeric), ~ signif(.x, 4)))
  paste(c(
    paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, function(r) paste("|", paste(trimws(r), collapse = " | "), "|"))
  ), collapse = "\n")
}

out <- c(
  "# Key numbers",
  "",
  sprintf("Generated %s.", Sys.Date()),
  sprintf("Annual data: %s to %s (provisional: %s). Comparison: %s vs %s.",
          min(annual$financial_year), max(annual$financial_year),
          paste(unique(annual$financial_year[annual$provisional]), collapse = ", "),
          fy_label(base_year), fy_label(full_year)),
  sprintf("Quarterly data: %s to %s.", min(quarterly$quarter), max(quarterly$quarter)),
  "",
  "## Scotland: age-standardised rates and inequality by financial year",
  fmt(scot_ineq),
  "",
  "## Interrupted time series: difference from pre-pandemic trend in the latest year",
  fmt(eff),
  "",
  "## Interrupted time series: model terms",
  fmt(its),
  "",
  sprintf("## Health boards (sorted by %s rate ratio)", fy_label(full_year)),
  fmt(boards),
  ""
)

writeLines(out, file.path("output", "key_numbers.md"))
message("  saved output/key_numbers.md")
