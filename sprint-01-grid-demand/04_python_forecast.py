# Databricks notebook source
# MAGIC %md
# MAGIC # Sprint 1 · Python: can a boring baseline forecast the load?
# MAGIC
# MAGIC This is the Python and PySpark part of the sprint. It exists for two reasons.
# MAGIC
# MAGIC 1. **Every Solutions Architect posting asks for production programming in Python.** SQL alone does not answer that question in an interview.
# MAGIC 2. **It produces a finding you can post.** Three dumb baselines compete to predict tomorrow's average load. Whichever wins, you have a number, and "the simplest one won" is the kind of honest result almost nobody publishes.
# MAGIC
# MAGIC The three baselines:
# MAGIC - `yesterday`: tomorrow looks like today.
# MAGIC - `last_week`: tomorrow looks like the same day last week.
# MAGIC - `ma7`: tomorrow is the average of the last 7 days.
# MAGIC
# MAGIC **DECIDE** as you go, and write each choice in `NOTES.md`:
# MAGIC - how many days to score (`DAYS_EVAL`)
# MAGIC - how many good hours a day needs before it counts (`MIN_HOURS`)
# MAGIC - whether MAPE (percentage error) or MAE (error in megawatts) is the fairer score across regions of very different size

# COMMAND ----------

from pyspark.sql import functions as F, Window

spark.sql("SET TIME ZONE 'UTC'")

DAYS_EVAL = 90   # DECIDE: how long a window to score
MIN_HOURS = 20   # DECIDE: a day needs this many good hours to count

daily = (
    spark.table("workspace.grid.gold_region_daily")
    .filter(F.col("hours_ok") >= MIN_HOURS)
)

print(f"days after the quality filter: {daily.count():,}")
display(daily.orderBy(F.col("day_utc").desc()).limit(5))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1 · Build the three predictions
# MAGIC
# MAGIC A window partitioned by region and ordered by day lets each row see earlier rows of the same region.
# MAGIC `rowsBetween(-7, -1)` means the seven days before this one, never this one, so the forecast cannot peek at the answer.

# COMMAND ----------

by_region = Window.partitionBy("region_code").orderBy("day_utc")
last_7_days = by_region.rowsBetween(-7, -1)

predictions = (
    daily
    .withColumn("pred_yesterday", F.lag("avg_load_mw", 1).over(by_region))
    .withColumn("pred_last_week", F.lag("avg_load_mw", 7).over(by_region))
    .withColumn("pred_ma7", F.avg("avg_load_mw").over(last_7_days))
)

latest_day = daily.agg(F.max("day_utc")).collect()[0][0]
scored_from = F.date_sub(F.lit(latest_day), DAYS_EVAL)
print(f"latest day in the data: {latest_day}. Scoring the {DAYS_EVAL} days before it.")

window_rows = predictions.filter(F.col("day_utc") > scored_from)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2 · Score them
# MAGIC
# MAGIC `stack` turns the three prediction columns into three rows per day, so one grouping scores every method at once.

# COMMAND ----------

long = window_rows.selectExpr(
    "region_code",
    "region_name",
    "day_utc",
    "avg_load_mw AS actual_mw",
    "stack(3, 'yesterday', pred_yesterday, 'last_week', pred_last_week, 'ma7', pred_ma7) AS (method, prediction_mw)",
).filter(F.col("prediction_mw").isNotNull() & (F.col("actual_mw") > 0))

eval_by_region = (
    long
    .withColumn("abs_error_mw", F.abs(F.col("actual_mw") - F.col("prediction_mw")))
    .withColumn("abs_pct_error", F.col("abs_error_mw") / F.col("actual_mw"))
    .groupBy("region_code", "region_name", "method")
    .agg(
        F.round(100 * F.avg("abs_pct_error"), 2).alias("mape_pct"),
        F.round(F.avg("abs_error_mw"), 1).alias("mae_mw"),
        F.count("*").alias("days_scored"),
    )
)

(eval_by_region.write.mode("overwrite")
 .option("overwriteSchema", "true")
 .saveAsTable("workspace.grid.gold_region_forecast_eval"))

display(eval_by_region.orderBy("region_code", "mape_pct"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3 · Which baseline wins, and by how much
# MAGIC
# MAGIC This is the slide in your demo. Copy these numbers into `NOTES.md` exactly as they come out.

# COMMAND ----------

rank_by_error = Window.partitionBy("region_code").orderBy("mape_pct")

winners = (
    eval_by_region
    .withColumn("rank", F.rank().over(rank_by_error))
    .filter(F.col("rank") == 1)
    .select("region_code", "region_name", "method", "mape_pct", "mae_mw")
)

print("Winning baseline per region:")
display(winners.orderBy("mape_pct"))

print("How often each method wins:")
display(winners.groupBy("method").agg(F.count("*").alias("regions_won")).orderBy(F.col("regions_won").desc()))

print("National picture (all regions pooled):")
display(
    eval_by_region.groupBy("method")
    .agg(
        F.round(F.avg("mape_pct"), 2).alias("avg_mape_pct"),
        F.round(F.min("mape_pct"), 2).alias("best_region_mape_pct"),
        F.round(F.max("mape_pct"), 2).alias("worst_region_mape_pct"),
    )
    .orderBy("avg_mape_pct")
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## What to write down before you close this notebook
# MAGIC
# MAGIC In `NOTES.md`, under Python:
# MAGIC - Which baseline won, in how many regions, and the MAPE gap between first and second.
# MAGIC - The region that was hardest to predict, and your guess at why (small region, more weather-driven, more renewables on the system).
# MAGIC - Any region where the error is suspiciously low or high, which usually means a data problem rather than a forecasting one.
# MAGIC - How long this notebook took to run.
# MAGIC
# MAGIC The demo line you are aiming for: "a seven-day average predicts tomorrow's regional load within X percent, so any model a vendor sells you has to beat that first."
