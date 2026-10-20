# Has the deprivation gap in emergency admissions changed since COVID?

People living in Scotland's most deprived areas are admitted to hospital as emergencies far more often than those in the least deprived areas. This project asks whether that gap has narrowed, widened or stayed the same since the COVID-19 pandemic, and how it differs across NHS health boards.

> Work in progress. This README grows as each stage of the analysis is completed.

## Data

- **Inpatient and daycase activity by health board of residence and deprivation** from [Public Health Scotland open data](https://www.opendata.nhs.scot/dataset/inpatient-and-daycase-activity). Quarterly episodes and stays by admission type and SIMD quintile (1 = most deprived, 5 = least deprived).
- **Population estimates by SIMD quintile** from [PHS open data](https://www.opendata.nhs.scot/dataset/population-estimates), used to turn counts into rates.

Both are published under the [UK Open Government Licence](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/). Raw data is downloaded by script and not stored in this repository.

## Approach

1. Download the data reproducibly from the PHS open data portal
2. Clean, check and join admissions to population
3. Describe emergency admission rates by deprivation quintile and health board over time
4. Measure inequality with the rate ratio and slope index of inequality
5. Interrupted time series around March 2020 to test whether the gap shifted
6. Interactive dashboard to explore boards and quintiles

## Progress

- [x] Project setup
- [ ] Data download
- [ ] Cleaning and joining
- [ ] Exploratory analysis
- [ ] Inequality measures
- [ ] Interrupted time series
- [ ] Dashboard
- [ ] Write-up of findings

## Repository structure

```
R/                 analysis scripts, run in numbered order
data/raw/          downloaded data (not tracked)
data/processed/    cleaned data (not tracked)
output/figures/    charts used in this README
app/               Shiny dashboard
```

## Reproducing the analysis

Requires R 4.3 or later. Package versions are pinned with [renv](https://rstudio.github.io/renv/).

```r
renv::restore()
```

Scripts will be added to `R/` as the project develops.

## Author

Juliet Asantewaa Sarpong, PhD researcher in Statistics, University of Edinburgh. [Portfolio](https://asantewaah.github.io)
