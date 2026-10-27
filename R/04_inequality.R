# 04_inequality.R
#
# Summarises the deprivation gap with four standard measures, for Scotland and
# each health board:
#
#   rate_ratio  most deprived rate / least deprived rate (simple, relative)
#   rate_diff   most deprived rate - least deprived rate (simple, absolute)
#   sii         slope index of inequality: the modelled absolute gap between
#               the most and least deprived ends of the population, using all
#               five quintiles weighted by population
#   rii         relative index of inequality: SII divided by the average rate,
#               so it can be compared over time as overall rates change
#
# Main analysis: annual age-standardised rates by financial year.
# Also computed for the quarterly crude rates, which feed the dashboard.
#
# SII and RII use every available quintile and still work for boards with no
# areas in one quintile (the island boards), as long as at least three remain.
#
# Run from the project root after 03_explore.R:
#   Rscript R/04_inequality.R
#
# Outputs:
#   output/tables/inequality_annual.csv
#   output/tables/inequality_quarterly.csv
#   output/figures/rii_scotland.png
#   output/figures/rii_by_board_change.png

library(dplyr)
library(readr)
library(ggplot2)
source(file.path("R", "plot_theme.R"))

scotland_code <- "S92000003"
base_year <- 2019  # financial year 2019/20, the last before the pandemic

annual <- read_csv(file.path("output", "tables", "annual_rates.csv"), show_col_types = FALSE)
quarterly_rates <- read_csv(file.path("data", "processed", "emergency_admissions_simd.csv"),
                            show_col_types = FALSE)

# ---- Inequality measures for one group of quintile rows ----------------------

inequality <- function(simd, rate, population) {
  # Skip quintiles with no rate (for example, suppressed small counts)
  keep <- !is.na(rate) & !is.na(population) & population > 0
  simd <- simd[keep]; rate <- rate[keep]; population <- population[keep]
  o <- order(simd)
  simd <- simd[o]; rate <- rate[o]; population <- population[o]

  r1 <- if (1 %in% simd) rate[simd == 1] else NA_real_
  r5 <- if (5 %in% simd) rate[simd == 5] else NA_real_

  # A slope across fewer than three quintiles is not meaningful
  if (length(simd) < 3) {
    return(tibble(quintiles = length(simd), mean_rate = NA_real_, rate_q1 = r1,
                  rate_q5 = r5, rate_ratio = r1 / r5, rate_diff = r1 - r5,
                  sii = NA_real_, rii = NA_real_))
  }

  # Ridit score: midpoint of each quintile's cumulative population share,
  # ranked from most deprived (0) to least deprived (1)
  share <- population / sum(population)
  ridit <- cumsum(share) - share / 2

  fit <- lm(rate ~ ridit, weights = population)
  sii <- -unname(coef(fit)["ridit"])
  mean_rate <- sum(rate * population) / sum(population)

  tibble(
    quintiles = length(simd),
    mean_rate = mean_rate,
    rate_q1 = r1,
    rate_q5 = r5,
    rate_ratio = r1 / r5,
    rate_diff = r1 - r5,
    sii = sii,
    rii = sii / mean_rate
  )
}

report_partial <- function(tab, label) {
  partial <- tab |>
    filter(quintiles < 5) |>
    group_by(hb_name, quintiles) |>
    summarise(periods = n(), .groups = "drop")
  if (nrow(partial) > 0) {
    message("  info (", label, "): boards with fewer than 5 quintiles in some periods:")
    print(partial, n = Inf)
  }
  if (any(tab$quintiles[tab$hb == scotland_code] < 5)) {
    stop("Scotland is missing a quintile in the ", label, " data.", call. = FALSE)
  }
}

# ---- Annual (main analysis) --------------------------------------------------

yearly <- annual |>
  group_by(financial_year, year, provisional, hb, hb_name) |>
  reframe(inequality(simd, rate_per_100k, population)) |>
  arrange(hb_name, year)
report_partial(yearly, "annual")

# ---- Quarterly (dashboard) ---------------------------------------------------

quarterly <- quarterly_rates |>
  group_by(quarter, quarter_start, year, provisional, hb, hb_name) |>
  reframe(inequality(simd, rate_per_100k, population)) |>
  arrange(hb_name, quarter_start)
report_partial(quarterly, "quarterly")

message("  ok: Scotland has all 5 quintiles in every period")
message("  info: SII and RII need at least 3 quintiles; with fewer they are left blank")

write_csv(yearly, file.path("output", "tables", "inequality_annual.csv"))
write_csv(quarterly, file.path("output", "tables", "inequality_quarterly.csv"))
message("  saved output/tables/inequality_annual.csv")
message("  saved output/tables/inequality_quarterly.csv")

# ---- Figure 3: Scotland RII over time ----------------------------------------

full_year <- latest_complete_fy(annual)
scot_y <- filter(yearly, hb == scotland_code, !provisional)
rii_base <- scot_y$rii[scot_y$year == base_year]
rii_now <- scot_y$rii[scot_y$year == full_year]
if (length(rii_base) == 0) stop("No Scotland data for ", fy_label(base_year), call. = FALSE)
direction <- if (rii_now > rii_base) "wider" else "narrower"

fig3 <- ggplot(scot_y, aes(year, rii)) +
  covid_band_fy() +
  geom_line(colour = col_indigo, linewidth = 1.1) +
  geom_point(colour = col_indigo, size = 2.2) +
  scale_x_fy(scot_y$year) +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(
    title = sprintf(
      "Scotland's relative deprivation gap in emergency admissions was %s in %s than in %s",
      direction, fy_label(full_year), fy_label(base_year)
    ),
    subtitle = sprintf(
      "Relative index of inequality: the modelled gap between the most and least deprived, as a share of the average rate. %s: %.0f%%, %s: %.0f%%.",
      fy_label(base_year), 100 * rii_base, fy_label(full_year), 100 * rii_now
    ),
    x = NULL, y = NULL,
    caption = source_note
  ) +
  theme_project()

save_figure(fig3, "rii_scotland")

# ---- Figure 4: change in RII by board, 2019/20 vs latest year -----------------

change <- yearly |>
  filter(year %in% c(base_year, full_year)) |>
  select(hb, hb_name, year, rii) |>
  tidyr::pivot_wider(names_from = year, values_from = rii, names_prefix = "y") |>
  rename(before = paste0("y", base_year), after = paste0("y", full_year)) |>
  filter(!is.na(before), !is.na(after)) |>
  mutate(
    is_scotland = hb == scotland_code,
    hb_name = sub("^NHS ", "", hb_name),
    hb_name = reorder(hb_name, after)
  )

n_wider <- sum(change$after > change$before & !change$is_scotland)
n_boards <- sum(!change$is_scotland)

fig4 <- ggplot(change, aes(y = hb_name)) +
  geom_segment(aes(x = before, xend = after, yend = hb_name), colour = col_mid,
               linewidth = 1) +
  geom_point(aes(x = before), colour = col_marigold, size = 3) +
  geom_point(aes(x = after), colour = col_indigo, size = 3) +
  annotate("text", x = change$before[change$is_scotland], y = "Scotland",
           label = fy_label(base_year), vjust = -1.2, size = 3.2, colour = col_text,
           fontface = "bold") +
  annotate("text", x = change$after[change$is_scotland], y = "Scotland",
           label = fy_label(full_year), vjust = -1.2, size = 3.2, colour = col_text,
           fontface = "bold") +
  scale_x_continuous(labels = scales::label_percent()) +
  labs(
    title = sprintf("The relative gap was wider in %s than in %s in %d of %d health boards",
                    fy_label(full_year), fy_label(base_year), n_wider, n_boards),
    subtitle = sprintf("Relative index of inequality in age-standardised emergency admissions, %s (gold) and %s (indigo).",
                       fy_label(base_year), fy_label(full_year)),
    x = NULL, y = NULL,
    caption = source_note
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text))

save_figure(fig4, "rii_by_board_change", height = 6.5)

message(sprintf("Scotland RII: %s %.3f, %s %.3f. SII: %s %.0f, %s %.0f per 100,000.",
                fy_label(base_year), rii_base, fy_label(full_year), rii_now,
                fy_label(base_year), scot_y$sii[scot_y$year == base_year],
                fy_label(full_year), scot_y$sii[scot_y$year == full_year]))
