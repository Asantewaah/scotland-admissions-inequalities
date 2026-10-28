# Deprivation and emergency admissions in Scotland: dashboard
#
# Explore emergency admission rates by deprivation for Scotland and each NHS
# health board. Built with Shiny and exported with shinylive so it runs in the
# browser with no server.
#
# Run locally from the project root:
#   shiny::runApp("app")

library(shiny)
library(ggplot2)

annual <- read.csv(file.path("data", "annual.csv"), stringsAsFactors = FALSE)
annual <- annual[!annual$provisional, ]  # match the analysis: complete years only
annual$simd <- factor(annual$simd, levels = 1:5)

quarterly <- read.csv(file.path("data", "quarterly.csv"), stringsAsFactors = FALSE)
quarterly$quarter_start <- as.Date(quarterly$quarter_start)
quarterly$simd <- factor(quarterly$simd, levels = 1:5)

boards <- c("Scotland", sort(setdiff(unique(annual$hb_name), "Scotland")))

col_indigo <- "#1D1B4C"
col_marigold <- "#F2A900"
col_mid <- "#B9B8C8"
col_text <- "#1F1F1F"
col_muted <- "#6B6B6B"
col_band <- "#F1F0F5"
quintile_cols <- c("1" = col_indigo, "2" = col_mid, "3" = col_mid, "4" = col_mid,
                   "5" = col_marigold)
quintile_labels <- c("1" = "Most deprived", "5" = "Least deprived")

fy_label <- function(year) sprintf("%d/%02d", year, (year + 1) %% 100)

theme_dash <- theme_minimal(base_size = 14) +
  theme(
    panel.grid.minor = element_blank(),
    axis.text = element_text(colour = col_muted),
    axis.title = element_text(colour = col_muted, size = 12),
    legend.position = "none",
    plot.margin = margin(10, 20, 10, 10)
  )

# Shared line chart: thick lines for the two extreme quintiles, grey for the rest
quintile_chart <- function(d, x, ends_at) {
  ends <- d[d[[x]] == ends_at & d$simd %in% c("1", "5"), ]
  ends$label <- quintile_labels[as.character(ends$simd)]
  ggplot(d, aes(.data[[x]], rate_per_100k, group = simd, colour = simd)) +
    geom_line(data = d[d$simd %in% c("2", "3", "4"), ], linewidth = 0.7) +
    geom_line(data = d[d$simd %in% c("1", "5"), ], linewidth = 1.3) +
    geom_text(data = ends, aes(label = label), hjust = -0.08, size = 4.5,
              fontface = "bold", colour = col_text) +
    scale_colour_manual(values = quintile_cols) +
    scale_y_continuous(labels = function(v) format(v, big.mark = ","),
                       limits = c(0, NA), expand = expansion(mult = c(0, 0.05))) +
    coord_cartesian(clip = "off") +
    theme_dash
}

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family: system-ui, -apple-system, 'Segoe UI', sans-serif; color: #1F1F1F; }
    h2 { font-weight: 700; font-size: 1.5rem; margin-bottom: 0.25rem; }
    .lede { color: #6B6B6B; margin-bottom: 1.25rem; max-width: 60rem; }
    .headline { font-size: 1.15rem; font-weight: 600; margin: 0.5rem 0 0.25rem; }
    .note { color: #6B6B6B; font-size: 0.85rem; }
  "))),
  h2("Deprivation and emergency hospital admissions in Scotland"),
  p(class = "lede",
    "People in Scotland's most deprived areas are admitted to hospital as emergencies far more often than those in the least deprived areas. Choose a health board to see how that gap has changed, including through the COVID-19 pandemic (shaded)."),
  fluidRow(
    column(
      3,
      selectInput("board", "Health board", choices = boards, selected = "Scotland"),
      radioButtons("view", "Show",
                   choices = c("Admission rates by deprivation" = "rates",
                               "Size of the gap (relative index of inequality)" = "rii",
                               "Recent quarters" = "quarterly"),
                   selected = "rates"),
      p(class = "note",
        "Yearly views use age-standardised rates per 100,000 people by financial year, by Scottish Index of Multiple Deprivation (SIMD) quintile. Middle quintiles are shown in grey."),
      p(class = "note",
        "The relative index of inequality is the modelled gap between the most and least deprived ends of the population, as a share of the average rate."),
      p(class = "note",
        "Recent quarters show crude rates, not age-standardised, so they are not directly comparable with the yearly views.")
    ),
    column(
      9,
      div(class = "headline", textOutput("headline")),
      plotOutput("chart", height = "430px"),
      p(class = "note",
        "Source: Public Health Scotland open data. ",
        a("Code and method", href = "https://github.com/Asantewaah/scotland-admissions-inequalities",
          target = "_blank"))
    )
  )
)

server <- function(input, output, session) {
  board_annual <- reactive(annual[annual$hb_name == input$board, ])
  board_quarterly <- reactive(quarterly[quarterly$hb_name == input$board, ])

  output$headline <- renderText({
    d <- board_annual()
    d <- d[!d$provisional, ]
    latest <- d[d$year == max(d$year), ][1, ]
    if (is.na(latest$rate_ratio)) {
      return(sprintf(
        "%s has no areas in Scotland's most deprived fifth. Relative index of inequality in %s: %s.",
        input$board, latest$financial_year,
        if (is.na(latest$rii)) "not available" else paste0(round(100 * latest$rii), "%")
      ))
    }
    sprintf("In %s, the most deprived areas of %s had %.1f times the age-standardised emergency admission rate of the least deprived.",
            latest$financial_year, input$board, latest$rate_ratio)
  })

  output$chart <- renderPlot({
    if (input$view == "quarterly") {
      d <- board_quarterly()
      quintile_chart(d, "quarter_start", max(d$quarter_start)) +
        scale_x_date(expand = expansion(mult = c(0.01, 0.2))) +
        labs(x = NULL, y = "Crude emergency admissions per 100,000 per year")
    } else {
      d <- board_annual()
      yrs <- sort(unique(d$year))
      covid <- annotate("rect", xmin = 2019.5, xmax = 2020.5, ymin = -Inf, ymax = Inf,
                        fill = col_band)
      x_fy <- scale_x_continuous(breaks = yrs[seq(1, length(yrs), by = 2)], labels = fy_label,
                                 expand = expansion(mult = c(0.02, 0.2)))
      if (input$view == "rates") {
        p <- quintile_chart(d, "year", max(d$year))
        p$layers <- c(covid, p$layers)
        p + x_fy + labs(x = NULL, y = "Age-standardised admissions per 100,000")
      } else {
        r <- unique(d[!is.na(d$rii), c("year", "rii")])
        ggplot(r, aes(year, rii)) +
          covid +
          geom_line(colour = col_indigo, linewidth = 1.3) +
          geom_point(colour = col_indigo, size = 2.5) +
          x_fy +
          scale_y_continuous(labels = scales::label_percent()) +
          labs(x = NULL, y = "Relative index of inequality") +
          theme_dash
      }
    }
  }, res = 96)
}

shinyApp(ui, server)
