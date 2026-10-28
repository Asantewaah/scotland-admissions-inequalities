# 06_dashboard_data.R
#
# Exports two small, tidy files for the dashboard. Unlike the raw and
# processed data, these are committed, because the dashboard runs in the
# browser and needs its data alongside it.
#
#   app/data/annual.csv     age-standardised rates and inequality by financial year
#   app/data/quarterly.csv  crude rates by quarter since 2020Q4
#
# Run from the project root after 05_its.R:
#   Rscript R/06_dashboard_data.R

library(dplyr)
library(readr)

dir.create(file.path("app", "data"), recursive = TRUE, showWarnings = FALSE)
short_name <- function(x) sub("^NHS ", "", x)

# ---- Annual ------------------------------------------------------------------

annual_rates <- read_csv(file.path("output", "tables", "annual_rates.csv"),
                         show_col_types = FALSE) |>
  select(financial_year, year, provisional, hb_name, simd, rate_per_100k)

annual_ineq <- read_csv(file.path("output", "tables", "inequality_annual.csv"),
                        show_col_types = FALSE) |>
  select(financial_year, hb_name, rii, rate_ratio)

annual <- annual_rates |>
  left_join(annual_ineq, by = c("financial_year", "hb_name")) |>
  mutate(hb_name = short_name(hb_name),
         rate_per_100k = round(rate_per_100k, 1),
         rii = round(rii, 4),
         rate_ratio = round(rate_ratio, 3)) |>
  arrange(hb_name, simd, year)

write_csv(annual, file.path("app", "data", "annual.csv"))

# ---- Quarterly ---------------------------------------------------------------

quarterly <- read_csv(file.path("data", "processed", "emergency_admissions_simd.csv"),
                      show_col_types = FALSE) |>
  transmute(quarter, quarter_start, provisional, hb_name = short_name(hb_name), simd,
            rate_per_100k = round(rate_per_100k, 1)) |>
  arrange(hb_name, simd, quarter_start)

write_csv(quarterly, file.path("app", "data", "quarterly.csv"))

for (f in c("annual.csv", "quarterly.csv")) {
  p <- file.path("app", "data", f)
  message(sprintf("  saved %s (%.0f KB)", p, file.size(p) / 1024))
}
