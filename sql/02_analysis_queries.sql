-- ============================================================================
-- 02_analysis_queries.sql
-- HIV Analysis Database: Sub-Saharan Africa, 2007-2024
-- Run after 01_build_database.sql.
-- ============================================================================

USE SubSahara_HIV_DB;

-- ============================================================================
-- 1. REGIONAL TRENDS
-- ============================================================================
-- Yearly totals across the 43 countries that report both new infections
-- and deaths for every year, so the trend isn't distorted by countries
-- dropping in and out of the data.
WITH complete_countries AS (
    SELECT country_id
    FROM hiv_indicators
    GROUP BY country_id
    HAVING COUNT(new_hiv_infections_annual) = 18
       AND COUNT(deaths_due_to_hiv) = 18
)
SELECT
    hiv.year,
    SUM(hiv.new_hiv_infections_annual) AS total_new_infections,
    SUM(hiv.deaths_due_to_hiv) AS total_deaths
FROM hiv_indicators hiv
JOIN complete_countries USING (country_id)
GROUP BY hiv.year
ORDER BY hiv.year;

-- ============================================================================
-- 2. CHANGE BY COUNTRY, 2007 TO 2024
-- ============================================================================
SELECT
    country.country_name,
    start_year.new_hiv_infections_annual AS new_infections_2007,
    end_year.new_hiv_infections_annual AS new_infections_2024,
    ROUND((end_year.new_hiv_infections_annual - start_year.new_hiv_infections_annual)
          / start_year.new_hiv_infections_annual * 100, 1) AS new_infections_change_pct,
    start_year.deaths_due_to_hiv AS deaths_2007,
    end_year.deaths_due_to_hiv AS deaths_2024,
    ROUND((end_year.deaths_due_to_hiv - start_year.deaths_due_to_hiv)
          / start_year.deaths_due_to_hiv * 100, 1) AS deaths_change_pct
FROM hiv_indicators start_year
JOIN hiv_indicators end_year
    ON end_year.country_id = start_year.country_id AND end_year.year = 2024
JOIN country ON country.country_id = start_year.country_id
WHERE start_year.year = 2007
ORDER BY new_infections_change_pct DESC;

-- ============================================================================
-- 3. PEOPLE LIVING WITH HIV AS A SHARE OF POPULATION
-- ============================================================================
SELECT
    country_name,
    year,
    people_living_with_hiv,
    population,
    hiv_population_ratio_pct
FROM combined_analysis
WHERE people_living_with_hiv IS NOT NULL
  AND population IS NOT NULL
ORDER BY hiv_population_ratio_pct DESC;

-- ============================================================================
-- 4. HIV PREVALENCE BY GDP PER CAPITA BAND
-- ============================================================================
SELECT
    CASE
        WHEN gdp_per_capita < 1000 THEN 'Low (<$1,000)'
        WHEN gdp_per_capita < 2000 THEN 'Lower-middle ($1,000-$2,000)'
        WHEN gdp_per_capita < 5000 THEN 'Upper-middle ($2,000-$5,000)'
        ELSE 'Higher (>$5,000)'
    END AS gdp_band,
    COUNT(DISTINCT country_name) AS countries,
    COUNT(*) AS country_years,
    ROUND(AVG(hiv_prevalence_15_49_pct), 2) AS avg_hiv_prevalence_pct,
    ROUND(AVG(new_hiv_infections_annual), 0) AS avg_new_infections,
    ROUND(AVG(deaths_due_to_hiv), 0) AS avg_deaths,
    ROUND(AVG(gdp_per_capita), 2) AS avg_gdp_per_capita
FROM combined_analysis
WHERE gdp_per_capita IS NOT NULL
  AND hiv_prevalence_15_49_pct IS NOT NULL
GROUP BY gdp_band
ORDER BY avg_gdp_per_capita;

-- ============================================================================
-- 5. HIV PREVALENCE BY UNEMPLOYMENT BAND
-- ============================================================================
SELECT
    CASE
        WHEN unemployment_rate < 5 THEN 'Low (<5%)'
        WHEN unemployment_rate < 10 THEN 'Moderate (5-10%)'
        WHEN unemployment_rate < 20 THEN 'High (10-20%)'
        ELSE 'Very high (>20%)'
    END AS unemployment_band,
    COUNT(DISTINCT country_name) AS countries,
    COUNT(*) AS country_years,
    ROUND(AVG(hiv_prevalence_15_49_pct), 2) AS avg_hiv_prevalence_pct,
    ROUND(AVG(unemployment_rate), 2) AS avg_unemployment_rate,
    ROUND(AVG(gdp_per_capita), 2) AS avg_gdp_per_capita
FROM combined_analysis
WHERE unemployment_rate IS NOT NULL
  AND hiv_prevalence_15_49_pct IS NOT NULL
GROUP BY unemployment_band
ORDER BY avg_unemployment_rate;
