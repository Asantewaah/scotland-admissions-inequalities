# 07_build_dashboard.R
#
# Turns the Shiny app into a static site with shinylive, so it runs entirely
# in the browser and can be hosted free on GitHub Pages.
#
# Run from the project root after 06_dashboard_data.R:
#   Rscript R/07_build_dashboard.R
#
# To preview locally before pushing:
#   httpuv::runStaticServer("docs")

if (!requireNamespace("shinylive", quietly = TRUE)) {
  stop("Install shinylive first: renv::install('shinylive')", call. = FALSE)
}

needed <- file.path("app", "data", c("annual.csv", "quarterly.csv"))
if (!all(file.exists(needed))) {
  stop(paste(needed[!file.exists(needed)], collapse = ", "),
       " not found. Run R/06_dashboard_data.R first.", call. = FALSE)
}

unlink("docs", recursive = TRUE)
shinylive::export("app", "docs")

# Tell GitHub Pages not to process the site with Jekyll
file.create(file.path("docs", ".nojekyll"))

message("Built docs/. Preview with httpuv::runStaticServer('docs'), then commit and push.")
