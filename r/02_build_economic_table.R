# 02_build_economic_table.R
# Turns the long World Bank data into one row per country and year, with
# GDP per capita, population, and unemployment as columns.
# Input:  data/clean/worldbank_long.csv (from 01_clean_worldbank.R)
# Output: data/raw/economic_demographic.csv (loaded into MySQL by
#         sql/01_build_database.sql)

library(tidyverse)

long <- read_csv("data/clean/worldbank_long.csv")

economic <- long %>%
  mutate(
    indicator = case_when(
      str_detect(series_name, "GDP per capita") ~ "gdp_per_capita",
      str_detect(series_name, "Population") ~ "population",
      str_detect(series_name, "Unemployment") ~ "unemployment_rate",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(indicator)) %>%
  # Use the short country names the database uses
  mutate(country_name = recode(country_name,
    "Congo, Rep." = "Congo",
    "Gambia, The" = "Gambia",
    "Somalia, Fed. Rep." = "Somalia"
  )) %>%
  select(country_name, country_code, year, indicator, value) %>%
  distinct() %>%
  pivot_wider(names_from = indicator, values_from = value) %>%
  select(country_name, country_code, year, gdp_per_capita, population, unemployment_rate) %>%
  arrange(country_name, year)

# Completeness check: how many country-years have each indicator
economic %>%
  summarise(
    rows = n(),
    countries = n_distinct(country_name),
    gdp_present = sum(!is.na(gdp_per_capita)),
    population_present = sum(!is.na(population)),
    unemployment_present = sum(!is.na(unemployment_rate))
  ) %>%
  print()

write_csv(economic, "data/raw/economic_demographic.csv", na = "NA")
message("Saved data/raw/economic_demographic.csv: ", nrow(economic), " rows")
