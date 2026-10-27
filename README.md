# Has the deprivation gap in emergency admissions changed since COVID?

People living in Scotland's most deprived areas are admitted to hospital as emergencies far more often than those in the least deprived areas. This project asks whether that gap has narrowed, widened or stayed the same since the COVID-19 pandemic, and how it differs across NHS health boards.

> Work in progress. This README grows as each stage of the analysis is completed.

## Data

All from the [Public Health Scotland open data portal](https://www.opendata.nhs.scot):

| File | Source | Used for |
|---|---|---|
| `admissions_hb_simd.csv` | [Inpatient and daycase activity by board of residence and deprivation](https://www.opendata.nhs.scot/dataset/inpatient-and-daycase-activity/resource/77d3d413-d7d6-4ad7-b89c-9e30ae75c64e) | Quarterly emergency admissions by health board and SIMD quintile (1 = most deprived, 5 = least deprived) |
| `simd2020v2_datazone.csv` | [SIMD 2020v2 lookup](https://www.opendata.nhs.scot/dataset/scottish-index-of-multiple-deprivation/resource/acade396-8430-4b34-895a-b3e757fa346e) | Assigning each data zone to a health board and deprivation quintile |
| `population_datazone.csv` | [Data zone population estimates](https://www.opendata.nhs.scot/dataset/population-estimates/resource/c505f490-c201-44bd-abd1-1bd7a64285ee) | Population denominators for rates |
| `hb_labels.csv` | [Health board codes and labels](https://www.opendata.nhs.scot/dataset/geography-codes-and-labels/resource/652ff726-e676-4a20-abda-435b98dd7bdc) | Health board names |

All are published under the [UK Open Government Licence](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/). Raw data is downloaded by script and not stored in this repository. Each run records the source URL, portal update date and file checksum in `data/raw/download_log.csv`.

### Definitions and data notes

- **Emergency admission** means a continuous inpatient stay that began as an emergency admission (PHS "Emergency Inpatients", counted as stays rather than episodes, so transfers between specialties are not double counted).
- **Rates** are annualised crude rates per 100,000 people: each quarter's stays multiplied by four, divided by that board and quintile's population. They are not age-standardised, because the published admissions are not broken down by age. Deprived areas in Scotland have younger populations on average, so crude rates if anything understate the gap.
- **Deprivation** uses Scotland-wide SIMD quintiles. Population denominators use SIMD 2020v2 for every year, while PHS assigns each admission to the SIMD release closest to its year, so rates for earlier years are slightly approximate.
- **Population** for quarters beyond the latest published estimates uses the most recent year available. These rows are flagged in the processed data.
- Admissions with unknown deprivation (no valid postcode) are excluded; the cleaning script reports their share.
- A few board and quintile combinations have no population under SIMD 2020v2 (for example, the island boards have no data zones in the most deprived national quintile). Their admissions cannot be turned into rates and are dropped; the cleaning script lists them and confirms they are under 1% of stays.

## Approach

1. Download the data reproducibly from the PHS open data portal
2. Clean, check and join admissions to population
3. Describe emergency admission rates by deprivation quintile and health board over time
4. Measure inequality with the rate ratio and slope index of inequality
5. Interrupted time series around March 2020 to test whether the gap shifted
6. Interactive dashboard to explore boards and quintiles

## Progress

- [x] Project setup
- [x] Data download
- [x] Cleaning and joining
- [x] Exploratory analysis
- [ ] Inequality measures
- [ ] Interrupted time series
- [ ] Dashboard
- [ ] Write-up of findings

## Results so far

### Emergency admission rates by deprivation, Scotland

![Emergency admission rates by SIMD quintile](output/figures/rates_by_quintile_scotland.png)

### The gap in each health board

![Rate ratio of most to least deprived by health board](output/figures/rate_ratio_by_board.png)

## Repository structure

```
R/                 analysis scripts, run in numbered order
data/raw/          downloaded data (not tracked)
data/processed/    cleaned data (not tracked)
output/figures/    charts used in this README
output/tables/     summary tables (annual rates, inequality measures)
app/               Shiny dashboard
```

## Reproducing the analysis

Requires R 4.3 or later. Package versions are pinned with [renv](https://rstudio.github.io/renv/).

From the project root:

```r
renv::restore()
```

```bash
Rscript R/01_download_data.R   # download raw data from PHS
Rscript R/02_clean_data.R      # clean, check and build the analysis table
Rscript R/03_explore.R         # annual rates and first charts
```

Further scripts will be added to `R/` as the project develops.

## Author

Juliet Asantewaa Sarpong, PhD researcher in Statistics, University of Edinburgh. [Portfolio](https://asantewaah.github.io)
