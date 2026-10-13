# 01_clean_worldbank.R
# Reshapes the raw World Bank export (one column per year) into long format.
# Input:  data/raw/worldbank_data.csv
# Output: data/clean/worldbank_long.csv

library(tidyverse)

raw <- read_csv("data/raw/worldbank_data.csv", na = c("", "NA", ".."))

clean <- raw %>%
  # Rename the first four columns by position
  rename(
    country_name = 1,
    country_code = 2,
    series_name = 3,
    series_code = 4
  ) %>%
  # Drop footer rows the World Bank adds below the data
  filter(!is.na(country_code)) %>%
  # One row per country, series, and year
  pivot_longer(
    cols = -c(country_name, country_code, series_name, series_code),
    names_to = "year",
    values_to = "value"
  ) %>%
  # "2007 [YR2007]" becomes 2007
  mutate(
    year = as.numeric(str_extract(year, "\\d{4}")),
    value = as.numeric(value)
  ) %>%
  filter(year >= 2007 & year <= 2024) %>%
  distinct() %>%
  arrange(country_name, series_name, year)

write_csv(clean, "data/clean/worldbank_long.csv")
message("Saved data/clean/worldbank_long.csv: ", nrow(clean), " rows")
