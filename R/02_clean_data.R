# 02_clean_data.R
#
# Cleans the raw PHS files and builds one analysis-ready table:
# quarterly emergency admissions (continuous inpatient stays) by health board
# and SIMD quintile, joined to population so counts can be expressed as rates.
#
# Run from the project root after 01_download_data.R:
#   Rscript R/02_clean_data.R
#
# Output: data/processed/emergency_admissions_simd.csv

library(dplyr)
library(readr)

raw_dir <- file.path("data", "raw")
out_dir <- file.path("data", "processed")

scotland_code <- "S92000003"

# ---- Helpers -----------------------------------------------------------------

read_raw <- function(name) {
  path <- file.path(raw_dir, paste0(name, ".csv"))
  if (!file.exists(path)) {
    stop(path, " not found. Run R/01_download_data.R first.", call. = FALSE)
  }
  read_csv(path, show_col_types = FALSE, guess_max = 100000)
}

require_cols <- function(df, cols, name) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0) {
    stop(sprintf(
      "%s is missing columns: %s\nColumns found: %s",
      name, paste(missing, collapse = ", "), paste(names(df), collapse = ", ")
    ), call. = FALSE)
  }
}

check <- function(ok, msg) {
  if (!isTRUE(ok)) stop("Check failed: ", msg, call. = FALSE)
  message("  ok: ", msg)
}

# Fife, Tayside, Greater Glasgow and Clyde and Lanarkshire got new codes when
# board boundaries changed in 2018-19. Map any older codes to the 2019 ones so
# every file uses the same boards.
hb_2014_to_2019 <- c(
  S08000018 = "S08000029",
  S08000027 = "S08000030",
  S08000021 = "S08000031",
  S08000023 = "S08000032"
)
recode_hb <- function(x) {
  x <- as.character(x)
  unname(ifelse(x %in% names(hb_2014_to_2019), hb_2014_to_2019[x], x))
}

# ---- Health board names ------------------------------------------------------

message("Health boards")
hb_raw <- read_raw("hb_labels")
require_cols(hb_raw, c("HB", "HBName"), "hb_labels")

if ("HBDateArchived" %in% names(hb_raw)) {
  hb_raw <- filter(hb_raw, is.na(HBDateArchived))
}

boards <- hb_raw |>
  filter(grepl("^S08", HB)) |>
  distinct(hb = HB, hb_name = HBName)

check(nrow(boards) == 14, "14 current NHS territorial health boards")

board_names <- bind_rows(boards, tibble(hb = scotland_code, hb_name = "Scotland"))

# ---- Emergency admissions ----------------------------------------------------

message("Admissions")
adm_raw <- read_raw("admissions_hb_simd")
require_cols(
  adm_raw,
  c("Quarter", "HB", "Location", "AdmissionType", "SIMD", "Episodes", "Stays"),
  "admissions_hb_simd"
)

if (!"Emergency Inpatients" %in% adm_raw$AdmissionType) {
  stop("No 'Emergency Inpatients' rows. Admission types found: ",
       paste(unique(adm_raw$AdmissionType), collapse = ", "), call. = FALSE)
}

if (!"QuarterQF" %in% names(adm_raw)) adm_raw$QuarterQF <- NA_character_

adm <- adm_raw |>
  # Board-level rows only: the file also breaks boards down by council area
  filter(AdmissionType == "Emergency Inpatients", Location == HB) |>
  mutate(
    hb = recode_hb(HB),
    simd = suppressWarnings(as.integer(SIMD)),
    provisional = !is.na(QuarterQF) & QuarterQF == "p",
    # PHS quarters are calendar quarters, e.g. 2020Q2 = April to June 2020
    year = as.integer(substr(Quarter, 1, 4)),
    q = as.integer(substr(Quarter, 6, 6)),
    quarter_start = as.Date(sprintf("%d-%02d-01", year, (q - 1) * 3 + 1))
  ) |>
  filter(hb %in% board_names$hb) |>
  select(quarter = Quarter, quarter_start, year, provisional, hb, simd,
         episodes = Episodes, stays = Stays)

check(!any(is.na(adm$quarter_start)), "every quarter parses as a date")
check(all(boards$hb %in% adm$hb), "all 14 boards appear in the admissions data")
check(scotland_code %in% adm$hb, "Scotland totals are present")

# Admissions with unknown deprivation (no valid postcode) cannot be assigned a
# quintile. Report how many there are, then drop them.
unknown_share <- adm |>
  filter(hb == scotland_code) |>
  summarise(share = sum(stays[is.na(simd)], na.rm = TRUE) / sum(stays, na.rm = TRUE)) |>
  pull(share)
message(sprintf(
  "  info: %.2f%% of Scotland's emergency stays have unknown SIMD and are excluded",
  100 * unknown_share
))

adm <- filter(adm, !is.na(simd))

check(all(adm$simd %in% 1:5), "SIMD quintiles are 1 to 5")
check(all(adm$stays >= 0, na.rm = TRUE), "no negative counts")
check(!any(duplicated(adm[c("quarter", "hb", "simd")])),
      "one row per quarter, board and quintile")

# Boards should add up to roughly the Scotland total. Small gaps are expected
# (disclosure control, patients with no board of residence).
totals <- adm |>
  group_by(quarter, is_scotland = hb == scotland_code) |>
  summarise(stays = sum(stays, na.rm = TRUE), .groups = "drop")
gap <- full_join(
  filter(totals, !is_scotland) |> select(quarter, boards = stays),
  filter(totals, is_scotland) |> select(quarter, scotland = stays),
  by = "quarter"
) |>
  mutate(pct_gap = 100 * abs(boards - scotland) / scotland)
message(sprintf("  info: boards differ from the Scotland total by at most %.2f%% in any quarter",
                max(gap$pct_gap, na.rm = TRUE)))
check(max(gap$pct_gap, na.rm = TRUE) < 2, "boards sum to within 2% of Scotland")

# ---- Population by board and quintile ----------------------------------------
#
# Denominators are built from data zone populations grouped by SIMD 2020v2
# quintile. PHS assigns admissions to the SIMD release closest to each year, so
# early years are slightly approximate. See the README for this limitation.

message("Population")
simd_raw <- read_raw("simd2020v2_datazone")
require_cols(simd_raw, c("DataZone", "HB", "SIMD2020V2CountryQuintile"),
             "simd2020v2_datazone")

simd_lookup <- simd_raw |>
  transmute(DataZone, hb = recode_hb(HB),
            simd = as.integer(SIMD2020V2CountryQuintile))

check(n_distinct(simd_lookup$DataZone) == 6976, "6,976 data zones in the SIMD lookup")

pop_raw <- read_raw("population_datazone")
require_cols(pop_raw, c("Year", "DataZone", "Sex", "AllAges"), "population_datazone")

# Use the all-persons rows if the file has them, otherwise add males and females
pop_dz <- if ("All" %in% pop_raw$Sex) {
  filter(pop_raw, Sex == "All")
} else {
  filter(pop_raw, Sex %in% c("Male", "Female"))
}

pop_dz <- pop_dz |>
  filter(DataZone %in% simd_lookup$DataZone) |>
  group_by(year = Year, DataZone) |>
  summarise(population = sum(AllAges), .groups = "drop") |>
  inner_join(simd_lookup, by = "DataZone")

pop_boards <- pop_dz |>
  group_by(year, hb, simd) |>
  summarise(population = sum(population), .groups = "drop")

pop_scotland <- pop_boards |>
  group_by(year, simd) |>
  summarise(population = sum(population), .groups = "drop") |>
  mutate(hb = scotland_code)

pop <- bind_rows(pop_boards, pop_scotland)

check(all(boards$hb %in% pop$hb), "all 14 boards appear in the population data")
check(all(pop$population > 0), "every board and quintile has a positive population")

pop_years <- range(pop$year)
message(sprintf("  info: population estimates cover %d to %d", pop_years[1], pop_years[2]))

# ---- Join and compute rates --------------------------------------------------
#
# Each quarter uses that year's population. Quarters outside the years
# covered use the nearest available year, and are flagged.

analysis <- adm |>
  mutate(pop_year = pmin(pmax(year, pop_years[1]), pop_years[2])) |>
  left_join(rename(pop, pop_year = year), by = c("pop_year", "hb", "simd")) |>
  left_join(board_names, by = "hb") |>
  mutate(
    pop_estimated = pop_year != year,
    # Quarterly count scaled to an annual rate so it reads like published figures
    rate_per_100k = 4 * stays / population * 1e5
  ) |>
  select(quarter, quarter_start, year, provisional, hb, hb_name, simd,
         stays, episodes, population, pop_year, pop_estimated, rate_per_100k) |>
  arrange(hb_name, simd, quarter_start)

# Some board and quintile combinations have no population under SIMD 2020v2.
# For example, the island boards have no data zones in the most deprived
# national quintile, but PHS can still assign a few admissions there using
# older SIMD releases. These rows cannot have a rate, so report and drop them.
no_pop <- filter(analysis, is.na(population))
if (nrow(no_pop) > 0) {
  no_pop_summary <- no_pop |>
    group_by(hb_name, simd) |>
    summarise(quarters = n(), stays = sum(stays, na.rm = TRUE), .groups = "drop")
  dropped_share <- sum(no_pop$stays, na.rm = TRUE) /
    sum(analysis$stays[analysis$hb != scotland_code], na.rm = TRUE)
  message("  info: board and quintile combinations with no population (dropped):")
  print(no_pop_summary, n = Inf)
  message(sprintf("  info: these are %.3f%% of board-level emergency stays", 100 * dropped_share))
  check(all(no_pop$hb != scotland_code), "Scotland-level rows all have a population")
  check(dropped_share < 0.01, "rows without a population are under 1% of stays")
  analysis <- filter(analysis, !is.na(population))
}

check(!any(is.na(analysis$population)), "every row has a population")
check(!any(is.na(analysis$hb_name)), "every row has a board name")

n_estimated <- n_distinct(analysis$quarter[analysis$pop_estimated])
if (n_estimated > 0) {
  message(sprintf("  info: %d quarters use the nearest year's population", n_estimated))
}

# ---- Save --------------------------------------------------------------------

out_path <- file.path(out_dir, "emergency_admissions_simd.csv")
write_csv(analysis, out_path)

scot <- filter(analysis, hb == scotland_code)
message(sprintf(
  "Done. %s rows, %s to %s, saved to %s",
  format(nrow(analysis), big.mark = ","),
  min(scot$quarter), max(scot$quarter), out_path
))
