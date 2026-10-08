-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Sprint 1 · Bronze: land the raw EIA data
-- MAGIC
-- MAGIC **Question:** does the AI data-center energy story show up in real U.S. grid demand?
-- MAGIC
-- MAGIC Bronze keeps the data exactly as EIA sent it, plus two columns recording which file each row came from and when it landed. No cleaning here. If silver ever goes wrong, you rebuild it from bronze without calling the API again.
-- MAGIC
-- MAGIC **Before you run anything:** write your prediction in NOTES.md. Which regions do you expect grew fastest, and by roughly how much?

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 · Can this workspace reach the EIA API?
-- MAGIC Free Edition limits outbound internet to a short list of trusted domains. Run this and write the result in your notes. It decides the architecture: if the call is blocked, the data is fetched on your laptop and uploaded to a volume, which is the path this sprint assumes.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import urllib.request, urllib.error
-- MAGIC try:
-- MAGIC     urllib.request.urlopen("https://api.eia.gov/v2/", timeout=10)
-- MAGIC     print("Reachable: EIA answered.")
-- MAGIC except urllib.error.HTTPError as e:
-- MAGIC     print(f"Reachable: EIA answered with HTTP {e.code} (normal without a key).")
-- MAGIC except Exception as e:
-- MAGIC     print(f"Blocked: {type(e).__name__}: {e}")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 · Create the schema and the landing volume
-- MAGIC A volume is governed file storage inside Unity Catalog. The raw files sit under the same permission model as the tables built from them.

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS workspace.grid
COMMENT 'Sprint 1: U.S. grid demand from the EIA Open Data API';

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS workspace.grid.landing
COMMENT 'Raw EIA API responses, uploaded from fetch_eia.py';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 · Upload the files
-- MAGIC On your laptop, run `python fetch_eia.py` from the sprint folder. It writes 14 files to `data/landing/`, one per region, plus `manifest.json`.
-- MAGIC
-- MAGIC In Databricks: **Catalog** > `workspace` > `grid` > `landing` > **Upload to this volume**. Select the 14 `eia_region_demand_*.json` files. Then run the next cell to confirm they arrived.

-- COMMAND ----------

LIST '/Volumes/workspace/grid/landing/'

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 · Build the bronze table
-- MAGIC `read_files` reads every matching file. `_metadata.file_path` records the source file for each row, which is what lets you trace any bad number back to exactly where it came from.

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.grid.bronze_eia_region_demand
COMMENT 'Raw EIA-930 hourly region demand, as returned by the API'
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM read_files(
  '/Volumes/workspace/grid/landing/eia_region_demand_*.json',
  format => 'json'
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 · Check it against the manifest
-- MAGIC `manifest.json` on your laptop has the row count EIA reported for each region. These should match. Write down both numbers, and any mismatch, in your notes.

-- COMMAND ----------

SELECT
  respondent  AS region,
  count(*)    AS rows_landed,
  min(period) AS first_hour_utc,
  max(period) AS last_hour_utc
FROM workspace.grid.bronze_eia_region_demand
GROUP BY respondent
ORDER BY respondent;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Look at the column types below. Note what type `value` came in as, and what the column names look like. Both matter in silver.

-- COMMAND ----------

DESCRIBE TABLE workspace.grid.bronze_eia_region_demand;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 · Did anything fail to fit the schema?
-- MAGIC `read_files` puts any field it could not match into `_rescued_data` instead of failing the load. That is the behaviour you want, but it is silent, so it has to be checked. Zero means the schema held across all 14 files. Anything above zero is a finding: look at a sample and find out which file and which field.

-- COMMAND ----------

SELECT
  count(*)                                AS rows_total,
  count_if(_rescued_data IS NOT NULL)      AS rows_rescued,
  count(DISTINCT _source_file)             AS source_files
FROM workspace.grid.bronze_eia_region_demand;

-- COMMAND ----------

-- Only returns anything if the check above is non-zero.
SELECT _source_file, _rescued_data
FROM workspace.grid.bronze_eia_region_demand
WHERE _rescued_data IS NOT NULL
LIMIT 20;
