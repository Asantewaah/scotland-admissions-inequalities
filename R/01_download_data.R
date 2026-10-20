# 01_download_data.R
#
# Downloads the raw data for this project from the Public Health Scotland
# open data portal. File URLs are looked up through the portal's API each
# time the script runs, so it keeps working when PHS publishes a new release.
#
# Run from the project root:
#   Rscript R/01_download_data.R
#
# Re-download everything (for example after a new PHS release):
#   Rscript R/01_download_data.R --overwrite

library(jsonlite)
library(readr)

# Large files can take a while on a slow connection
options(timeout = max(600, getOption("timeout")))

raw_dir <- file.path("data", "raw")
if (!dir.exists(raw_dir)) {
  stop("Run this script from the project root (data/raw not found).", call. = FALSE)
}

overwrite <- "--overwrite" %in% commandArgs(trailingOnly = TRUE)

# ---- What we need ------------------------------------------------------------

resources <- data.frame(
  name = c(
    "admissions_hb_simd",
    "simd2020v2_datazone",
    "population_datazone",
    "hb_labels"
  ),
  resource_id = c(
    "77d3d413-d7d6-4ad7-b89c-9e30ae75c64e",
    "acade396-8430-4b34-895a-b3e757fa346e",
    "c505f490-c201-44bd-abd1-1bd7a64285ee",
    "652ff726-e676-4a20-abda-435b98dd7bdc"
  ),
  description = c(
    "Quarterly inpatient and daycase activity by health board of residence and SIMD quintile",
    "SIMD 2020v2 lookup: data zone to health board and deprivation quintile",
    "Mid-year population estimates by data zone, sex and age",
    "Health board codes and names"
  )
)

# ---- Helpers -----------------------------------------------------------------

api_url <- "https://www.opendata.nhs.scot/api/3/action/resource_show?id="

value_or_na <- function(x) if (is.null(x)) NA_character_ else as.character(x)

get_resource_info <- function(resource_id) {
  info <- fromJSON(paste0(api_url, resource_id))
  if (!isTRUE(info$success)) {
    stop("PHS API lookup failed for resource ", resource_id, call. = FALSE)
  }
  info$result
}

download_resource <- function(name, resource_id, description) {
  dest <- file.path(raw_dir, paste0(name, ".csv"))
  info <- get_resource_info(resource_id)

  if (file.exists(dest) && !overwrite) {
    message("Skipping ", name, ": already downloaded (use --overwrite to refresh)")
  } else {
    message("Downloading ", name, " ...")
    download.file(info$url, dest, mode = "wb", quiet = TRUE)
  }

  data.frame(
    name = name,
    description = description,
    resource_id = resource_id,
    source_url = info$url,
    portal_last_modified = value_or_na(info$last_modified),
    downloaded_at = format(file.mtime(dest), "%Y-%m-%d %H:%M:%S"),
    size_mb = round(file.size(dest) / 1e6, 2),
    md5 = unname(tools::md5sum(dest))
  )
}

# ---- Download ----------------------------------------------------------------

log <- do.call(
  rbind,
  Map(download_resource, resources$name, resources$resource_id, resources$description)
)
rownames(log) <- NULL

write_csv(log, file.path(raw_dir, "download_log.csv"))

# ---- Quick check -------------------------------------------------------------
# Confirms each file reads cleanly. Proper checks come in the cleaning step.

for (name in log$name) {
  df <- read_csv(file.path(raw_dir, paste0(name, ".csv")), show_col_types = FALSE)
  message(sprintf(
    "%-22s %8s rows  %3d columns  first columns: %s",
    name, format(nrow(df), big.mark = ","), ncol(df),
    paste(head(names(df), 5), collapse = ", ")
  ))
}

message("Done. Download details saved to ", file.path(raw_dir, "download_log.csv"))
