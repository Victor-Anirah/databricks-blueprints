-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Sprint 1 · Gold: answer the question
-- MAGIC
-- MAGIC Three tables:
-- MAGIC - `gold_region_daily`: daily average load per region, for the trend chart
-- MAGIC - `gold_region_monthly`: energy, average load, peak, and completeness per month
-- MAGIC - `gold_region_growth`: last 12 months vs the 12 before, plus the 4-year trend, ranked
-- MAGIC
-- MAGIC **Why average load (MW) instead of total energy (MWh):** some months are missing hours. Summing MWh makes a month with gaps look like lower demand. Average hourly load isn't fooled by missing hours. That's a design decision worth one sentence in your post.
-- MAGIC
-- MAGIC **Time zone note:** days and months are cut at UTC midnight. For monthly and yearly growth that moves a few hours at the edges and barely changes the numbers. For a peak-hour analysis it would matter, and you'd convert to each region's local time first.

-- COMMAND ----------

SET TIME ZONE 'UTC';

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.gold_region_daily
COMMENT 'Daily average and peak load per region (UTC days, usable hours only)'
AS
SELECT
  region_code,
  region_name,
  CAST(date_trunc('DAY', hour_utc) AS DATE) AS day_utc,
  avg(demand_mwh) AS avg_load_mw,
  max(demand_mwh) AS peak_load_mw,
  count(*)        AS hours_ok
FROM workspace.grid.silver_hourly_demand
WHERE quality_flag = 'ok'
GROUP BY ALL;

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.gold_region_monthly
COMMENT 'Monthly energy, average load, peak and completeness per region'
AS
WITH hourly AS (
  SELECT
    region_code,
    region_name,
    CAST(date_trunc('MONTH', hour_utc) AS DATE) AS month_utc,
    demand_mwh
  FROM workspace.grid.silver_hourly_demand
  WHERE quality_flag = 'ok'
)
SELECT
  region_code,
  region_name,
  month_utc,
  sum(demand_mwh) AS energy_mwh,
  avg(demand_mwh) AS avg_load_mw,
  max(demand_mwh) AS peak_load_mw,
  count(*)        AS hours_ok,
  round(count(*) / (day(last_day(month_utc)) * 24), 4) AS completeness
FROM hourly
GROUP BY region_code, region_name, month_utc;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Growth
-- MAGIC Only complete calendar months count. Average load over a window is total usable energy divided by usable hours, which weights every hour equally.
-- MAGIC - **yoy_growth_pct:** last 12 complete months vs the 12 before
-- MAGIC - **cagr_4y_pct:** last 12 months vs the first 12 in the dataset, annualized over the 4 years between them
-- MAGIC
-- MAGIC US48 is the national baseline, so it's ranked separately from the 13 regions.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.gold_region_growth
COMMENT 'Average-load growth per region: year over year and 4-year CAGR, ranked'
AS
WITH complete_months AS (
  SELECT *
  FROM workspace.grid.gold_region_monthly
  WHERE month_utc < date_trunc('MONTH', current_date())
),
bounds AS (
  SELECT max(month_utc) AS last_month, min(month_utc) AS first_month
  FROM complete_months
),
tagged AS (
  SELECT
    c.*,
    CASE
      WHEN c.month_utc > add_months(b.last_month, -12) THEN 'last_12'
      WHEN c.month_utc > add_months(b.last_month, -24) THEN 'prior_12'
    END AS yoy_window,
    c.month_utc < add_months(b.first_month, 12) AS in_first_12
  FROM complete_months c
  CROSS JOIN bounds b
),
windows AS (
  SELECT
    region_code,
    region_name,
    sum(CASE WHEN yoy_window = 'last_12'  THEN energy_mwh END)
      / sum(CASE WHEN yoy_window = 'last_12'  THEN hours_ok END) AS avg_load_last_12_mw,
    sum(CASE WHEN yoy_window = 'prior_12' THEN energy_mwh END)
      / sum(CASE WHEN yoy_window = 'prior_12' THEN hours_ok END) AS avg_load_prior_12_mw,
    sum(CASE WHEN in_first_12 THEN energy_mwh END)
      / sum(CASE WHEN in_first_12 THEN hours_ok END)             AS avg_load_first_12_mw,
    min(CASE WHEN yoy_window = 'last_12' THEN completeness END)  AS worst_month_completeness_last_12
  FROM tagged
  GROUP BY region_code, region_name
)
SELECT
  *,
  region_code = 'US48' AS is_national,
  round(100 * (avg_load_last_12_mw / avg_load_prior_12_mw - 1), 2)                AS yoy_growth_pct,
  round(100 * (power(avg_load_last_12_mw / avg_load_first_12_mw, 1.0 / 4) - 1), 2) AS cagr_4y_pct,
  rank() OVER (
    PARTITION BY region_code = 'US48'
    ORDER BY avg_load_last_12_mw / avg_load_prior_12_mw DESC
  ) AS yoy_rank
FROM windows;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## The answer
-- MAGIC Write the top three and bottom three regions, with their numbers, in your notes. Compare them with the prediction you wrote before you started.

-- COMMAND ----------

SELECT
  region_code,
  region_name,
  yoy_rank,
  yoy_growth_pct,
  cagr_4y_pct,
  round(avg_load_last_12_mw) AS avg_load_last_12_mw,
  worst_month_completeness_last_12
FROM workspace.grid.gold_region_growth
ORDER BY is_national DESC, yoy_rank;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## DECIDE · Does it line up with the data-center story?
-- MAGIC The ranking alone doesn't prove anything about data centers. To connect them, find **one credible public source** on where data-center load is growing, such as a grid operator's load forecast, an EIA analysis, or Lawrence Berkeley National Lab's data center energy report. Write the regions it names and the link in your notes, then compare them with this ranking.
-- MAGIC
-- MAGIC Don't guess which regions are "data-center heavy". The source is part of the post, and it's the first thing a senior reader will ask for.
