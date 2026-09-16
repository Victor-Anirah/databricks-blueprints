# Sprint 1: U.S. grid demand

**Question:** does the AI data-center energy story actually show up in real U.S. grid demand?

**Data:** EIA Open Data API v2, EIA-930 hourly demand for the 13 U.S. regions plus the Lower 48 total, five years back. About 620,000 rows. Public and free.

## Architecture

```
EIA API
  |  fetch_eia.py, run on your laptop (Free Edition blocks outbound API calls)
  v
data/landing/*.json  (raw JSON Lines, one file per region)
  |  upload
  v
/Volumes/workspace/grid/landing          Unity Catalog volume
  |  01_bronze.sql
  v
bronze_eia_region_demand                 raw rows + source file + ingest time
  |  02_silver.sql
  v
silver_hourly_demand, silver_dq_coverage typed, UTC, deduplicated, quality-flagged
  |  03_gold.sql
  v
gold_region_daily, gold_region_monthly, gold_region_growth
  |
  v
AI/BI dashboard + Genie space            the Last Mile
```

## Run it (about 3 hours)

- [ ] **Prediction (5 min).** Before touching data, write in `NOTES.md` which regions you expect grew fastest and by how much.
- [ ] **Fetch (10 min).** From this folder: `python fetch_eia.py`. Test your key first with `python fetch_eia.py --sample` if you like. Write the row counts and runtime in your notes.
- [ ] **Import the notebooks (5 min).** In Databricks: **Workspace** > your `blueprints` folder > **Import**, and select `01_bronze.sql`, `02_silver.sql`, and `03_gold.sql`. They open as SQL notebooks. (Once this repo is on GitHub, a Git folder replaces this step.)
- [ ] **Bronze (30 min).** Run `01_bronze.sql` top to bottom. Step 0 tests whether the workspace can reach EIA; write down the result. Upload the 14 files when the notebook tells you to.
- [ ] **Silver (45 min).** Run `02_silver.sql`. Make the DECIDE calls. Whatever fights you here is the content.
- [ ] **Gold (30 min).** Run `03_gold.sql`. Write the top three and bottom three regions with numbers. Find one public source on where data-center load is growing and compare.
- [ ] **Last Mile (60 min).** See below.
- [ ] **Capture (15 min).** Finish `NOTES.md`: what you built, what broke, row counts, runtime, the finding, what you would do differently.

If it runs past three hours, cut scope, not honesty. Bronze and silver with a real finding and no dashboard is still a post.

## The Last Mile

Recommended for this sprint:

1. **AI/BI dashboard.** New > Dashboard. Use `gold_region_daily` and `gold_region_growth`. Add one region filter, one line chart of daily average load, one counter for year-over-year growth, and one bar chart of the growth ranking.
2. **Genie space.** New > Genie space on the three gold tables. Add instructions like "load is in MW, growth is year over year, US48 is the national total." Test questions: *Which region grew fastest in the last year? How did Texas compare to the national average?* Record a 60 to 90 second clip of it answering. That's your Thursday post.

A React front end is the bigger Last Mile statement. Save it for a later sprint so this one fits in a weekend.

## Cost and limits

Free Edition caps serverless compute daily. This sprint is small (about 620k rows), but don't loop the full dataset while debugging. If compute stops, you've hit the daily quota. Your data is safe and it resets tomorrow.
