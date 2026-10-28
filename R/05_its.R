# 05_its.R
#
# Interrupted time series: after the COVID-19 pandemic, was the deprivation
# gap in emergency admissions different from where its pre-pandemic trend was
# heading?
#
# Data: annual age-standardised rates by financial year. 2016/17 to 2019/20 are
# pre-pandemic; 2020/21 is treated as a transition year and left out of the
# models, so the lockdown collapse in admissions does not drive the estimates;
# 2021/22 onwards is post-pandemic. Provisional years are excluded.
#
# Outcomes: relative index of inequality (RII) and slope index of inequality
# (SII, per 100,000).
#
# With only four pre-pandemic years, three models are fitted and reported:
#
#   1. Scotland, segmented: y = b0 + b1*time + b2*post + b3*time_since
#      (level change and slope change). Most flexible, least precise.
#   2. Scotland, level only: y = b0 + b1*time + b2*post
#      (assumes the trend did not change). More stable with few points.
#   3. Board panel, segmented: the same model as 1, fitted to every board with
#      an RII in all years, with board fixed effects and standard errors
#      clustered by board. Uses far more data, and estimates the average
#      within-board shift.
#
# The headline is the difference from the pre-pandemic trend in the latest
# year: level change + slope change x years since the pandemic.
#
# Run from the project root after 04_inequality.R:
#   Rscript R/05_its.R
#
# Outputs:
#   output/tables/its_results.csv
#   output/tables/its_effect_at_end.csv
#   output/figures/its_rii_scotland.png

library(dplyr)
library(readr)
library(ggplot2)
library(sandwich)
source(file.path("R", "plot_theme.R"))

scotland_code <- "S92000003"
transition_year <- 2020  # financial year 2020/21
post_start <- 2021

ineq <- read_csv(file.path("output", "tables", "inequality_annual.csv"),
                 show_col_types = FALSE) |>
  filter(!provisional) |>
  mutate(
    time = year - min(year) + 1,
    phase = case_when(
      year < transition_year ~ "pre",
      year == transition_year ~ "transition",
      TRUE ~ "post"
    ),
    post = as.integer(year >= post_start),
    time_since = if_else(post == 1L, year - post_start + 1, 0)
  )

model_data <- filter(ineq, phase != "transition")
scot <- filter(model_data, hb == scotland_code)
panel <- model_data |>
  filter(hb != scotland_code) |>
  group_by(hb) |>
  filter(all(!is.na(rii)), n() == nrow(scot)) |>
  ungroup()

message(sprintf("Years: %d pre-pandemic, %d post (%s to %s); %d boards in the panel",
                sum(scot$phase == "pre"), sum(scot$phase == "post"),
                fy_label(min(scot$year)), fy_label(max(scot$year)), n_distinct(panel$hb)))

# ---- Model helpers -----------------------------------------------------------

fit_model <- function(d, outcome, type) {
  rhs <- switch(type,
    scotland_segmented = "time + post + time_since",
    scotland_level = "time + post",
    panel_segmented = "factor(hb) + time + post + time_since"
  )
  fit <- lm(as.formula(paste(outcome, "~", rhs)), data = d)
  V <- if (type == "panel_segmented") {
    vcovCL(fit, cluster = ~hb, type = "HC1")
  } else {
    vcov(fit)
  }
  df <- if (type == "panel_segmented") n_distinct(d$hb) - 1 else df.residual(fit)
  list(fit = fit, V = V, df = df, data = d)
}

model_label <- c(
  scotland_segmented = "Scotland: level and slope change",
  scotland_level = "Scotland: level change only",
  panel_segmented = "Boards pooled: level and slope change"
)

tidy_model <- function(m, outcome, type) {
  est <- coef(m$fit)
  se <- sqrt(diag(m$V))
  keep <- intersect(c("time", "post", "time_since"), names(est))
  tibble(
    outcome = outcome, model = model_label[[type]],
    term = keep, estimate = unname(est[keep]), std_error = unname(se[keep]),
    conf_low = estimate - qt(0.975, m$df) * std_error,
    conf_high = estimate + qt(0.975, m$df) * std_error,
    p_value = 2 * pt(-abs(estimate / std_error), m$df)
  ) |>
    mutate(term = recode(term,
                         time = "pre-pandemic trend (per year)",
                         post = "level change",
                         time_since = "slope change (per year)"))
}

effect_at_end <- function(m, outcome, type) {
  k <- max(m$data$time_since)
  b <- coef(m$fit)
  g <- setNames(rep(0, length(b)), names(b))
  g["post"] <- 1
  if ("time_since" %in% names(b)) g["time_since"] <- k
  est <- sum(g * b)
  se <- sqrt(drop(t(g) %*% m$V %*% g))
  tibble(outcome = outcome, model = model_label[[type]],
         year = fy_label(max(m$data$year)), years_since = k, effect = est,
         conf_low = est - qt(0.975, m$df) * se,
         conf_high = est + qt(0.975, m$df) * se,
         p_value = 2 * pt(-abs(est / se), m$df))
}

# ---- Fit ---------------------------------------------------------------------

results <- list(); effects <- list(); models <- list()
for (outcome in c("rii", "sii")) {
  for (type in names(model_label)) {
    d <- if (type == "panel_segmented") panel else scot
    m <- fit_model(d, outcome, type)
    models[[paste(outcome, type)]] <- m
    results[[length(results) + 1]] <- tidy_model(m, outcome, type)
    effects[[length(effects) + 1]] <- effect_at_end(m, outcome, type)
  }
}
results <- bind_rows(results)
effects <- bind_rows(effects)

write_csv(results, file.path("output", "tables", "its_results.csv"))
write_csv(effects, file.path("output", "tables", "its_effect_at_end.csv"))
message("  saved output/tables/its_results.csv")
message("  saved output/tables/its_effect_at_end.csv")
print(effects |> mutate(across(where(is.numeric), ~ signif(.x, 3))), width = Inf)

# ---- Figure 5: observed RII against its pre-pandemic trend -------------------

m <- models[["rii scotland_segmented"]]
scot_all <- filter(ineq, hb == scotland_code)
lines <- scot |>
  mutate(
    fitted = predict(m$fit, newdata = scot),
    counterfactual = predict(m$fit, newdata = mutate(scot, post = 0L, time_since = 0))
  )

eff_s <- filter(effects, outcome == "rii", model == model_label[["scotland_segmented"]])
eff_p <- filter(effects, outcome == "rii", model == model_label[["panel_segmented"]])
eff_all <- filter(effects, outcome == "rii")
pp <- 100 * eff_s$effect

# Only claim a shift when every model agrees on its direction and the pooled
# board model (the most data) is clearly different from zero. Otherwise say
# plainly that four pre-pandemic years cannot settle it.
same_sign <- length(unique(sign(eff_all$effect))) == 1
pooled_clear <- eff_p$conf_low > 0 || eff_p$conf_high < 0
rii_pre <- scot_all$rii[scot_all$year == transition_year - 1]
rii_end <- tail(scot$rii, 1)

title <- if (same_sign && pooled_clear) {
  sprintf("By %s, the relative deprivation gap was %.1f to %.1f percentage points %s its pre-pandemic trend",
          eff_s$year, min(abs(100 * eff_all$effect)), max(abs(100 * eff_all$effect)),
          if (eff_p$effect > 0) "above" else "below")
} else {
  # When the models share a direction but the pooled interval includes zero,
  # they do not disagree: the data are just too few to tell.
  verdict <- if (same_sign) {
    "it is too uncertain to say whether this departs from the earlier trend"
  } else {
    "the models disagree on whether this departs from the earlier trend"
  }
  sprintf("The relative gap %s from %.0f%% in %s to %.0f%% in %s, but with only four pre-pandemic years %s",
          if (rii_end > rii_pre) "rose" else "fell", 100 * rii_pre,
          fy_label(transition_year - 1), 100 * rii_end, eff_s$year, verdict)
}

fig5 <- ggplot() +
  covid_band_fy(label = FALSE) +
  geom_line(data = filter(lines, phase == "pre"), aes(year, fitted),
            colour = col_indigo, linewidth = 1.1) +
  geom_line(data = filter(lines, phase == "post"), aes(year, fitted),
            colour = col_indigo, linewidth = 1.1) +
  geom_line(data = filter(lines, phase == "post"), aes(year, counterfactual),
            colour = col_marigold, linewidth = 1.1, linetype = "22") +
  geom_point(data = scot_all, aes(year, rii, colour = phase == "transition"), size = 2.4) +
  annotate("text", x = max(lines$year), y = tail(lines$fitted, 1),
           label = "Observed trend", hjust = -0.1, size = 3.4, fontface = "bold",
           colour = col_text) +
  annotate("text", x = max(lines$year), y = tail(lines$counterfactual, 1),
           label = "Pre-pandemic\ntrend continued", hjust = -0.1, size = 3.4,
           fontface = "bold", colour = col_text, lineheight = 0.9) +
  scale_colour_manual(values = c(`FALSE` = col_indigo, `TRUE` = col_mid)) +
  scale_x_fy(scot_all$year, expand_right = 0.22) +
  scale_y_continuous(labels = scales::label_percent()) +
  coord_cartesian(clip = "off") +
  labs(
    title = title,
    subtitle = sprintf(
      "Relative index of inequality in age-standardised emergency admissions, Scotland. Lines show the Scotland model. Difference from trend in %s: %+.1f points (95%% CI %+.1f to %+.1f); pooling the health boards: %+.1f points (95%% CI %+.1f to %+.1f).",
      eff_s$year, pp, 100 * eff_s$conf_low, 100 * eff_s$conf_high,
      100 * eff_p$effect, 100 * eff_p$conf_low, 100 * eff_p$conf_high
    ),
    x = NULL, y = NULL,
    caption = paste0(source_note,
                     "\nSegmented regression; 2020/21 (grey) is a transition year excluded from the models.")
  ) +
  theme_project()

save_figure(fig5, "its_rii_scotland", height = 5.5)
