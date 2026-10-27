# 03_explore.R
#
# First look at the data: how age-standardised emergency admission rates
# differ by deprivation, how they changed through the pandemic, and how the gap
# varies by health board.
#
# Run from the project root after 02_clean_data.R:
#   Rscript R/03_explore.R
#
# Outputs:
#   output/figures/rates_by_quintile_scotland.png
#   output/figures/rate_ratio_by_board.png
#   output/tables/annual_rates.csv

library(dplyr)
library(readr)
library(ggplot2)
source(file.path("R", "plot_theme.R"))

scotland_code <- "S92000003"
base_year <- 2019  # financial year 2019/20, the last before the pandemic

annual <- read_csv(file.path("data", "processed", "emergency_admissions_simd_annual.csv"),
                   show_col_types = FALSE)

full_year <- latest_complete_fy(annual)
message("Latest complete financial year: ", fy_label(full_year))

dir.create(file.path("output", "tables"), recursive = TRUE, showWarnings = FALSE)
write_csv(annual, file.path("output", "tables", "annual_rates.csv"))
message("  saved output/tables/annual_rates.csv")

# ---- Figure 1: Scotland rates by quintile over time --------------------------

scot <- annual |>
  filter(hb == scotland_code, !provisional) |>
  mutate(simd = factor(simd, levels = 1:5))

ratio_in <- function(y) {
  d <- filter(scot, year == y)
  d$rate_per_100k[d$simd == "1"] / d$rate_per_100k[d$simd == "5"]
}
ratio_latest <- ratio_in(full_year)
ratio_base <- ratio_in(base_year)

end_points <- scot |>
  filter(year == max(year), simd %in% c("1", "5")) |>
  mutate(label = quintile_labels[as.character(simd)])

fig1 <- ggplot(scot, aes(year, rate_per_100k, group = simd, colour = simd)) +
  covid_band_fy() +
  geom_line(data = filter(scot, simd %in% c("2", "3", "4")), linewidth = 0.6) +
  geom_line(data = filter(scot, simd %in% c("1", "5")), linewidth = 1.1) +
  geom_point(data = filter(scot, simd %in% c("1", "5")), size = 1.8) +
  geom_text(data = end_points, aes(label = label), hjust = -0.12, size = 3.5,
            colour = col_text, fontface = "bold") +
  scale_colour_manual(values = quintile_cols) +
  scale_x_fy(scot$year, expand_right = 0.2) +
  scale_y_continuous(labels = scales::comma, limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.05))) +
  coord_cartesian(clip = "off") +
  labs(
    title = sprintf(
      "People in Scotland's most deprived areas had %.1f times as many emergency admissions as the least deprived in %s, compared with %.1f times in %s",
      ratio_latest, fy_label(full_year), ratio_base, fy_label(base_year)
    ),
    subtitle = "Emergency admissions per 100,000 people, age-standardised, by SIMD quintile. Middle quintiles in grey.",
    x = NULL, y = NULL,
    caption = source_note
  ) +
  theme_project()

save_figure(fig1, "rates_by_quintile_scotland")

# ---- Figure 2: rate ratio by board -------------------------------------------
# Boards with no areas in the most deprived national quintile (the island
# boards) have no ratio and are listed in the caption.

ratios <- annual |>
  filter(year == full_year, simd %in% c(1, 5)) |>
  select(hb, hb_name, simd, rate_per_100k) |>
  tidyr::pivot_wider(names_from = simd, values_from = rate_per_100k,
                     names_prefix = "q") |>
  filter(!is.na(q1), !is.na(q5)) |>
  mutate(
    ratio = q1 / q5,
    is_scotland = hb == scotland_code,
    hb_name = sub("^NHS ", "", hb_name),
    hb_name = reorder(hb_name, ratio)
  )

excluded <- setdiff(unique(annual$hb_name[annual$hb != scotland_code]),
                    paste("NHS", as.character(ratios$hb_name)))

top_board <- ratios |> filter(!is_scotland) |> slice_max(ratio, n = 1)
low_board <- ratios |> filter(!is_scotland) |> slice_min(ratio, n = 1)

fig2 <- ggplot(ratios, aes(ratio, hb_name, fill = is_scotland)) +
  geom_col(width = 0.7) +
  geom_vline(xintercept = 1, colour = col_muted, linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.1f", ratio)), hjust = -0.2, size = 3.3,
            colour = col_text) +
  scale_fill_manual(values = c(`FALSE` = col_indigo, `TRUE` = col_marigold)) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = sprintf("The deprivation gap ranges from %.1f times in %s to %.1f times in %s",
                    low_board$ratio, low_board$hb_name, top_board$ratio, top_board$hb_name),
    subtitle = sprintf(
      "Age-standardised emergency admission rate in the most deprived quintile divided by the least deprived, %s. Scotland in gold.",
      fy_label(full_year)
    ),
    x = NULL, y = NULL,
    caption = paste0(
      source_note,
      if (length(excluded) > 0) {
        paste0("\n", paste(excluded, collapse = ", "),
               " not shown: no areas in the most deprived national quintile.")
      } else ""
    )
  ) +
  theme_project() +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(colour = col_text))

save_figure(fig2, "rate_ratio_by_board", height = 6)

message(sprintf("Scotland rate ratio: %s %.2f, %s %.2f",
                fy_label(base_year), ratio_base, fy_label(full_year), ratio_latest))
