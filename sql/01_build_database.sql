-- ============================================================================
-- 01_build_database.sql
-- HIV Analysis Database: Sub-Saharan Africa, 2007-2024
-- Team: Rabiat Blessing Ibrahim, Jennifer Flora Bastian,
--       Thaise Gusson Silva Domingos, Stella Kafui Sabuki
-- Course: ITC6000 Database Management Systems, Northeastern University
--
-- Revised 2026: HIV indicators now load from the long-format UNAIDS file
-- (data/raw/hiv_indicators_long.csv) and are pivoted here in SQL. The
-- original build loaded a hand-made wide file in which 116 death and
-- new-infection values had lost two zeros, and six countries were split
-- across two rows because UNAIDS and the World Bank spell their names
-- differently. See the README for details.
-- ============================================================================

DROP DATABASE IF EXISTS SubSahara_HIV_DB;
CREATE DATABASE SubSahara_HIV_DB;
USE SubSahara_HIV_DB;

-- ============================================================================
-- 1. CORE TABLES
-- ============================================================================
CREATE TABLE country (
    country_id INT PRIMARY KEY AUTO_INCREMENT,
    country_name VARCHAR(35) NOT NULL UNIQUE,
    country_code VARCHAR(5),
    INDEX idx_country_name (country_name)
);

CREATE TABLE hiv_indicators (
    indicator_id INT PRIMARY KEY AUTO_INCREMENT,
    country_id INT NOT NULL,
    year INT NOT NULL,
    people_living_with_hiv INT,
    deaths_due_to_hiv INT,
    women_15plus_living_with_hiv INT,
    pregnant_women_known_status_pct INT,
    mother_to_child_transmission_rate DECIMAL(5,2),
    new_hiv_infections_annual INT,
    hiv_prevalence_15_49_pct DECIMAL(5,2),
    FOREIGN KEY (country_id) REFERENCES country(country_id),
    UNIQUE KEY uk_hiv_country_year (country_id, year)
);

CREATE TABLE economic_demographic (
    econ_id INT PRIMARY KEY AUTO_INCREMENT,
    country_id INT NOT NULL,
    year INT NOT NULL,
    gdp_per_capita FLOAT,
    population INT,
    unemployment_rate DECIMAL(5,3),
    FOREIGN KEY (country_id) REFERENCES country(country_id),
    UNIQUE KEY uk_econ_country_year (country_id, year)
);

-- ============================================================================
-- 2. STAGING TABLES
-- ============================================================================
-- Long format: one row per country, indicator, and year, the way UNAIDS
-- and the World Bank publish it. Values stay as text until they are checked.
CREATE TABLE temp_hiv_long_staging (
    country VARCHAR(60),
    indicator VARCHAR(80),
    year INT,
    value VARCHAR(50),
    lower_bound VARCHAR(50),
    upper_bound VARCHAR(50),
    footnote VARCHAR(255)
);

CREATE TABLE temp_econ_staging (
    country_name VARCHAR(35),
    country_code VARCHAR(5),
    year INT,
    gdp_per_capita VARCHAR(50),
    population VARCHAR(50),
    unemployment_rate VARCHAR(50)
);

-- Maps the names UNAIDS and the World Bank use to the single name
-- stored in the country table (taken from the World Bank file).
CREATE TABLE country_name_map (
    source_name VARCHAR(60) PRIMARY KEY,
    country_name VARCHAR(35) NOT NULL
);

INSERT INTO country_name_map (source_name, country_name) VALUES
    ('Côte d''Ivoire', 'Cote d''Ivoire'),
    ('Democratic Republic of the Congo', 'Congo, Dem. Rep.'),
    ('Congo, Rep.', 'Congo'),
    ('Gambia, The', 'Gambia'),
    ('Somalia, Fed. Rep.', 'Somalia'),
    ('United Republic of Tanzania', 'Tanzania');

-- ============================================================================
-- 3. IMPORT THE CSV FILES (MySQL Workbench Table Data Import Wizard)
-- ============================================================================
-- Right-click each staging table > Table Data Import Wizard > "Use existing table":
--   temp_econ_staging      <- data/raw/economic_demographic.csv
--   temp_hiv_long_staging  <- data/raw/hiv_indicators_long.csv
--      Map columns: Country > country, Indicator > indicator, Year > year,
--      Value > value, Lower > lower_bound, Upper > upper_bound,
--      Footnote > footnote
-- Then run the rest of this script.

SELECT 'Economic rows' AS staging_table, COUNT(*) AS row_count FROM temp_econ_staging   -- expect 882
UNION ALL
SELECT 'HIV long rows', COUNT(*) FROM temp_hiv_long_staging;                               -- expect 5701

-- ============================================================================
-- 4. POPULATE COUNTRY
-- ============================================================================
INSERT INTO country (country_name, country_code)
SELECT DISTINCT country_name, country_code
FROM temp_econ_staging
WHERE country_name IS NOT NULL;

SELECT COUNT(*) AS total_countries FROM country;   -- expect 49

-- Every HIV country name must resolve to a country row. Expect 0 rows.
SELECT DISTINCT staging.country AS unmatched_country
FROM temp_hiv_long_staging staging
LEFT JOIN country_name_map name_map ON TRIM(staging.country) = name_map.source_name
LEFT JOIN country ON country.country_name = COALESCE(name_map.country_name, TRIM(staging.country))
WHERE country.country_id IS NULL;

-- ============================================================================
-- 5. POPULATE HIV INDICATORS (pivot long to wide)
-- ============================================================================
-- Values use a comma as the decimal mark ("100000,00"), so the comma is
-- replaced with a period before casting. Entries that are not numbers
-- ("...", blanks) become NULL instead of being cast to 0.
INSERT INTO hiv_indicators (
    country_id, year,
    people_living_with_hiv,
    deaths_due_to_hiv,
    women_15plus_living_with_hiv,
    pregnant_women_known_status_pct,
    mother_to_child_transmission_rate,
    new_hiv_infections_annual,
    hiv_prevalence_15_49_pct
)
SELECT
    country_id,
    year,
    MAX(CASE WHEN indicator = 'Estimated number of people living with HIV' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'Estimated number of deaths due to HIV' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'Estimated number of women (15+) living with HIV' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'Percent of pregnant women with known HIV status' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'Estimated mother-to-child transmission rate (%)' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'New HIV Infections (Annual)' THEN numeric_value END),
    MAX(CASE WHEN indicator = 'Prevalence of HIV, total (% of population ages 15-49)' THEN numeric_value END)
FROM (
    SELECT
        country.country_id,
        staging.year,
        TRIM(staging.indicator) AS indicator,
        CASE
            WHEN REPLACE(TRIM(staging.value), ',', '.') REGEXP '^[0-9]+([.][0-9]+)?$'
            THEN CAST(REPLACE(TRIM(staging.value), ',', '.') AS DECIMAL(15,2))
        END AS numeric_value
    FROM temp_hiv_long_staging staging
    LEFT JOIN country_name_map name_map ON TRIM(staging.country) = name_map.source_name
    INNER JOIN country ON country.country_name = COALESCE(name_map.country_name, TRIM(staging.country))
    WHERE staging.year BETWEEN 2007 AND 2024
) parsed
GROUP BY country_id, year
HAVING COUNT(numeric_value) > 0;

SELECT COUNT(*) AS total_hiv_records FROM hiv_indicators;   -- expect 810 (45 countries x 18 years)

-- ============================================================================
-- 6. POPULATE ECONOMIC DEMOGRAPHIC
-- ============================================================================
INSERT INTO economic_demographic (
    country_id, year,
    gdp_per_capita,
    population,
    unemployment_rate
)
SELECT
    country.country_id,
    temp_econ_staging.year,
    NULLIF(NULLIF(TRIM(temp_econ_staging.gdp_per_capita), ''), 'NA'),
    NULLIF(NULLIF(TRIM(temp_econ_staging.population), ''), 'NA'),
    NULLIF(NULLIF(TRIM(temp_econ_staging.unemployment_rate), ''), 'NA')
FROM temp_econ_staging
INNER JOIN country ON temp_econ_staging.country_name = country.country_name
WHERE temp_econ_staging.year BETWEEN 2007 AND 2024;

SELECT COUNT(*) AS total_econ_records FROM economic_demographic;   -- expect 882

-- ============================================================================
-- 7. VALIDATION
-- ============================================================================
-- a) Spot checks against the published UNAIDS figures.
--    Expect: Nigeria 2016 = 100000 new infections, Cameroon 2009 = 40000
--    new infections, Zimbabwe 2007 = 110000 deaths.
SELECT country.country_name, hiv.year, hiv.new_hiv_infections_annual, hiv.deaths_due_to_hiv
FROM hiv_indicators hiv
JOIN country ON hiv.country_id = country.country_id
WHERE (country.country_name = 'Nigeria' AND hiv.year = 2016)
   OR (country.country_name = 'Cameroon' AND hiv.year = 2009)
   OR (country.country_name = 'Zimbabwe' AND hiv.year = 2007);

-- b) Exactly one row per country and year. Expect 0 rows.
SELECT country_id, year, COUNT(*) AS rows_found
FROM hiv_indicators
GROUP BY country_id, year
HAVING COUNT(*) > 1;

-- c) Every loaded death and new-infection value must equal its source
--    value. Expect 0 rows.
SELECT parsed.country_id, parsed.year, parsed.indicator, parsed.numeric_value
FROM (
    SELECT
        country.country_id,
        staging.year,
        TRIM(staging.indicator) AS indicator,
        CAST(REPLACE(TRIM(staging.value), ',', '.') AS DECIMAL(15,2)) AS numeric_value
    FROM temp_hiv_long_staging staging
    LEFT JOIN country_name_map name_map ON TRIM(staging.country) = name_map.source_name
    JOIN country ON country.country_name = COALESCE(name_map.country_name, TRIM(staging.country))
    WHERE REPLACE(TRIM(staging.value), ',', '.') REGEXP '^[0-9]+([.][0-9]+)?$'
      AND TRIM(staging.indicator) IN ('New HIV Infections (Annual)', 'Estimated number of deaths due to HIV')
      AND staging.year BETWEEN 2007 AND 2024
) parsed
JOIN hiv_indicators hiv ON hiv.country_id = parsed.country_id AND hiv.year = parsed.year
WHERE (parsed.indicator = 'New HIV Infections (Annual)' AND hiv.new_hiv_infections_annual <> parsed.numeric_value)
   OR (parsed.indicator = 'Estimated number of deaths due to HIV' AND hiv.deaths_due_to_hiv <> parsed.numeric_value);

-- ============================================================================
-- 8. DROP STAGING TABLES
-- ============================================================================
DROP TABLE temp_hiv_long_staging;
DROP TABLE temp_econ_staging;

-- ============================================================================
-- 9. ANALYSIS VIEW
-- ============================================================================
CREATE OR REPLACE VIEW combined_analysis AS
SELECT
    country.country_name,
    country.country_code,
    hiv_indicators.year,
    hiv_indicators.people_living_with_hiv,
    hiv_indicators.deaths_due_to_hiv,
    hiv_indicators.women_15plus_living_with_hiv,
    hiv_indicators.pregnant_women_known_status_pct,
    hiv_indicators.mother_to_child_transmission_rate,
    hiv_indicators.new_hiv_infections_annual,
    hiv_indicators.hiv_prevalence_15_49_pct,
    economic_demographic.population,
    economic_demographic.gdp_per_capita,
    economic_demographic.unemployment_rate,
    ROUND((hiv_indicators.people_living_with_hiv / economic_demographic.population) * 100, 4) AS hiv_population_ratio_pct
FROM hiv_indicators
INNER JOIN country ON hiv_indicators.country_id = country.country_id
LEFT JOIN economic_demographic
    ON hiv_indicators.country_id = economic_demographic.country_id
    AND hiv_indicators.year = economic_demographic.year
ORDER BY country.country_name, hiv_indicators.year;

-- ============================================================================
-- 10. DATA QUALITY: MISSING VALUES PER INDICATOR
-- ============================================================================
SELECT 'People living with HIV' AS indicator,
    SUM(people_living_with_hiv IS NULL) AS missing_count, COUNT(*) AS total_records FROM hiv_indicators
UNION ALL SELECT 'Deaths due to HIV', SUM(deaths_due_to_hiv IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'Women 15+ living with HIV', SUM(women_15plus_living_with_hiv IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'Pregnant women with known HIV status (%)', SUM(pregnant_women_known_status_pct IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'Mother-to-child transmission rate (%)', SUM(mother_to_child_transmission_rate IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'New HIV infections', SUM(new_hiv_infections_annual IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'HIV prevalence, ages 15-49 (%)', SUM(hiv_prevalence_15_49_pct IS NULL), COUNT(*) FROM hiv_indicators
UNION ALL SELECT 'Population', SUM(population IS NULL), COUNT(*) FROM economic_demographic
UNION ALL SELECT 'GDP per capita', SUM(gdp_per_capita IS NULL), COUNT(*) FROM economic_demographic
UNION ALL SELECT 'Unemployment rate', SUM(unemployment_rate IS NULL), COUNT(*) FROM economic_demographic;
