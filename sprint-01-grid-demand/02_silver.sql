-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Sprint 1 · Silver: clean, typed, one row per region per hour
-- MAGIC
-- MAGIC Silver is where the real story usually lives. Four jobs:
-- MAGIC 1. **Types.** EIA sends demand as text and the hour as a string like `2024-07-15T21`. Cast both.
-- MAGIC 2. **Time zone.** EIA hours are UTC. Pin the session to UTC so nothing shifts silently.
-- MAGIC 3. **Duplicates.** Keep exactly one row per region and hour.
-- MAGIC 4. **Quality flags.** Flag bad values instead of deleting them, so you can count them and explain them.
-- MAGIC
-- MAGIC Every judgment call is marked **DECIDE**. Write down what you chose and why. Those notes become your posts.

-- COMMAND ----------

SET TIME ZONE 'UTC';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 · Typed, deduplicated, flagged
-- MAGIC **DECIDE:** the spike and drop thresholds (3x and 0.2x of the region's median). Run Step 2 with these first, look at what gets flagged, then adjust if the flags catch real demand or miss obvious junk.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.silver_hourly_demand
COMMENT 'Hourly demand per EIA region: typed, UTC, deduplicated, quality-flagged'
AS
WITH typed AS (
  SELECT
    respondent                              AS region_code,
    `respondent-name`                       AS region_name,
    to_timestamp(period, "yyyy-MM-dd'T'HH") AS hour_utc,
    try_cast(value AS DOUBLE)               AS demand_mwh,
    value                                   AS demand_raw,
    `value-units`                           AS units,
    _source_file,
    _ingested_at
  FROM workspace.grid.bronze_eia_region_demand
  WHERE type = 'D'
),
deduped AS (
  SELECT *
  FROM typed
  QUALIFY row_number() OVER (
    PARTITION BY region_code, hour_utc
    ORDER BY _ingested_at DESC, _source_file DESC
  ) = 1
),
medians AS (
  SELECT region_code, percentile_approx(demand_mwh, 0.5) AS median_mwh
  FROM deduped
  WHERE demand_mwh > 0
  GROUP BY region_code
)
SELECT
  d.region_code,
  d.region_name,
  d.hour_utc,
  d.demand_mwh,
  d.demand_raw,
  d.units,
  CASE
    WHEN d.demand_mwh IS NULL              THEN 'missing'
    WHEN d.demand_mwh <= 0                 THEN 'non_positive'
    WHEN d.demand_mwh > 3.0 * m.median_mwh THEN 'spike'
    WHEN d.demand_mwh < 0.2 * m.median_mwh THEN 'drop'
    ELSE 'ok'
  END AS quality_flag,
  d._source_file,
  d._ingested_at
FROM deduped d
LEFT JOIN medians m ON d.region_code = m.region_code;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 · What did cleaning catch?
-- MAGIC Write these numbers in your notes. "X duplicate rows and Y impossible values in a federal dataset" is a real post line.

-- COMMAND ----------

SELECT
  (SELECT count(*) FROM workspace.grid.bronze_eia_region_demand WHERE type = 'D') AS bronze_rows,
  (SELECT count(*) FROM workspace.grid.silver_hourly_demand)                       AS silver_rows,
  (SELECT count(*) FROM workspace.grid.bronze_eia_region_demand WHERE type = 'D')
    - (SELECT count(*) FROM workspace.grid.silver_hourly_demand)                   AS duplicates_removed,
  (SELECT count(*) FROM workspace.grid.silver_hourly_demand
     WHERE demand_raw IS NOT NULL AND demand_mwh IS NULL)                          AS non_numeric_values;

-- COMMAND ----------

SELECT region_code, quality_flag, count(*) AS hours
FROM workspace.grid.silver_hourly_demand
GROUP BY region_code, quality_flag
ORDER BY region_code, quality_flag;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Eyeball the flagged rows. Are they genuinely broken, or real events (a heat wave, a storm outage) that your threshold caught by mistake? **DECIDE** and note it.

-- COMMAND ----------

SELECT region_code, hour_utc, demand_mwh, demand_raw, quality_flag
FROM workspace.grid.silver_hourly_demand
WHERE quality_flag <> 'ok'
ORDER BY region_code, hour_utc
LIMIT 100;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 · Coverage: how many hours are missing entirely?
-- MAGIC Flags catch bad values. This catches hours that never arrived at all, which a row count alone would hide.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.silver_dq_coverage
COMMENT 'Per-region coverage: expected vs present vs usable hours'
AS
SELECT
  region_code,
  min(hour_utc) AS first_hour_utc,
  max(hour_utc) AS last_hour_utc,
  CAST((unix_timestamp(max(hour_utc)) - unix_timestamp(min(hour_utc))) / 3600 AS BIGINT) + 1 AS hours_expected,
  count(*)                    AS hours_present,
  count_if(quality_flag = 'ok') AS hours_ok
FROM workspace.grid.silver_hourly_demand
GROUP BY region_code;

-- COMMAND ----------

SELECT
  *,
  hours_expected - hours_present             AS hours_missing,
  round(100 * hours_ok / hours_expected, 2)  AS pct_usable
FROM workspace.grid.silver_dq_coverage
ORDER BY pct_usable;
