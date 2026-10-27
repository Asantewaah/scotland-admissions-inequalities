# plot_theme.R
#
# Shared chart style for every figure in this project: a bold headline that
# states the finding, a grey subtitle, direct labels instead of legends, and a
# source note. Sourced by the analysis scripts; not run on its own.

library(ggplot2)

col_indigo   <- "#1D1B4C"  # most deprived quintile / main series
col_marigold <- "#F2A900"  # least deprived quintile / comparison
col_mid      <- "#B9B8C8"  # middle quintiles, context series
col_text     <- "#1F1F1F"
col_muted    <- "#6B6B6B"
col_grid     <- "#E6E6E6"
col_band     <- "#F1F0F5"  # shading for the first COVID-19 year

quintile_cols <- c(
  "1" = col_indigo,
  "2" = col_mid,
  "3" = col_mid,
  "4" = col_mid,
  "5" = col_marigold
)

quintile_labels <- c(
  "1" = "Most deprived",
  "2" = "Quintile 2",
  "3" = "Quintile 3",
  "4" = "Quintile 4",
  "5" = "Least deprived"
)

# First year of the pandemic, used as the shaded band and ITS transition
covid_start <- as.Date("2020-04-01")
covid_end   <- as.Date("2021-03-31")

source_note <- "Source: Public Health Scotland open data. Crude annualised rates per 100,000 people."

theme_project <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", colour = col_text, size = rel(1.15),
                                margin = margin(b = 4)),
      plot.subtitle = element_text(colour = col_muted, margin = margin(b = 12)),
      plot.caption = element_text(colour = col_muted, size = rel(0.75), hjust = 0,
                                  margin = margin(t = 10)),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      axis.title = element_text(colour = col_muted, size = rel(0.85)),
      axis.text = element_text(colour = col_muted),
      panel.grid.major = element_line(colour = col_grid, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      legend.position = "none",
      plot.margin = margin(14, 18, 10, 14),
      plot.background = element_rect(fill = "white", colour = NA)
    )
}

covid_band <- function(label = TRUE) {
  layers <- list(
    annotate("rect", xmin = covid_start, xmax = covid_end, ymin = -Inf, ymax = Inf,
             fill = col_band)
  )
  if (label) {
    layers <- c(layers, list(
      annotate("text", x = covid_start, y = Inf, label = "First COVID-19 year",
               hjust = -0.05, vjust = 1.5, size = 3, colour = col_muted)
    ))
  }
  layers
}

# Year ticks every `by` years, only within the range of the data
year_breaks <- function(dates, by = 2) {
  years <- as.integer(format(range(dates), "%Y"))
  first <- ceiling(years[1] / by) * by
  as.Date(paste0(seq(first, years[2], by = by), "-01-01"))
}

wrap <- function(text, width = 80) paste(strwrap(text, width), collapse = "\n")

save_figure <- function(plot, name, width = 8, height = 5) {
  # Wrap long titles and subtitles so they never run off the image
  if (!is.null(plot$labels$title)) plot$labels$title <- wrap(plot$labels$title, 72)
  if (!is.null(plot$labels$subtitle)) plot$labels$subtitle <- wrap(plot$labels$subtitle, 95)
  dir.create(file.path("output", "figures"), recursive = TRUE, showWarnings = FALSE)
  path <- file.path("output", "figures", paste0(name, ".png"))
  ggsave(path, plot, width = width, height = height, dpi = 200, bg = "white")
  message("  saved ", path)
  invisible(path)
}

# Latest calendar year with all four quarters and no provisional data
latest_full_year <- function(df) {
  complete <- df |>
    dplyr::group_by(year) |>
    dplyr::summarise(n_q = dplyr::n_distinct(quarter), any_prov = any(provisional),
                     .groups = "drop") |>
    dplyr::filter(n_q == 4, !any_prov)
  max(complete$year)
}
