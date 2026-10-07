# Sprint 1: U.S. grid demand

**The industry question:** every grid operator and utility is being asked whether AI data-center load is showing up in real demand, and where. Most answers come from slides, not from the data.

**Your question:** does the story hold up in five years of real hourly grid data, and can a person get the answer in ten seconds instead of a week?

**Data:** EIA Open Data API v2, EIA-930 hourly demand for the 13 U.S. regions plus the Lower 48 total, five years back. About 620,000 rows. Public and free.

## What this sprint is for

This is the audition for pre-sales work: Solution Engineer now, Solutions Architect later. Those jobs are judged on three things, so the sprint produces all three.

1. **A working lakehouse** on real messy data, including the parts that fought you.
2. **Python you can defend**, because every Solutions Architect posting asks for it.
3. **A 6 minute demo** that opens with a business problem and ends with a question, not a feature tour.

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
  |  04_python_forecast.py  (PySpark)
  v
gold_region_forecast_eval                three baselines scored, per region
  |
  v
AI/BI dashboard + Genie space            the last mile
  |
  v
6 minute demo video                      the deliverable that gets you hired
```

## Run it

Budget about 6 hours the first time, which is a weekend, not an evening. Later sprints get faster because the domain and the quirks are already known.

- [ ] **Prediction (5 min).** Before touching data, write in `NOTES.md` which regions you expect grew fastest and by how much. Being wrong in writing is content.
- [ ] **Fetch (15 min).** From this folder: `python fetch_eia.py`. Test your key first with `python fetch_eia.py --sample`. Record row counts and runtime.
- [ ] **Import the notebooks (5 min).** Databricks > Workspace > your `blueprints` folder > Import, and select `01_bronze.sql`, `02_silver.sql`, `03_gold.sql`, `04_python_forecast.py`. Once the Git folder is connected this step disappears.
- [ ] **Bronze (45 min).** Run `01_bronze.sql`. Step 0 tests whether the workspace can reach EIA. Upload the 14 files when the notebook says to.
- [ ] **Silver (60 min).** Run `02_silver.sql`. Make the DECIDE calls and write down each one. Whatever fights you here is the best part of the demo.
- [ ] **Gold (45 min).** Run `03_gold.sql`. Write the top three and bottom three regions with numbers. Find one public source on data-center load growth and compare it to what you found.
- [ ] **Python (60 min).** Run `04_python_forecast.py`. Three baselines, one winner, one error number you can say out loud.
- [ ] **Last mile (60 min).** Dashboard plus Genie space, below.
- [ ] **Demo (60 min).** Record the 6 minutes using `DEMO.md`. One take is fine.
- [ ] **Capture (20 min).** Finish `NOTES.md`. That file is the input to every post.
- [ ] **Discovery call (20 min, any time this sprint).** One conversation with someone who works with grid data. Questions and the outreach note are in `DEMO.md`.

If you run long, cut scope, not honesty. Bronze, silver, a real finding and a rough demo still beats a perfect pipeline nobody sees.

## The last mile

1. **AI/BI dashboard.** New > Dashboard on `gold_region_daily` and `gold_region_growth`. One region filter, one line chart of daily average load, one counter for year-over-year growth, one bar chart of the growth ranking. Add a chart from `gold_region_forecast_eval` showing baseline error by region.
2. **Genie space.** New > Genie space on the gold tables. Add instructions such as "load is in MW, growth is year over year, US48 is the national total." Test with: *Which region grew fastest in the last year? How did Texas compare to the national average?* Note one question it answers well and one it fumbles. Both go in the demo.

A React front end is a later sprint. It is not what these roles hire for.

## Deliverables checklist

- [ ] Tables through gold, plus `gold_region_forecast_eval`
- [ ] Dashboard and Genie space
- [ ] 6 minute demo on YouTube, linked from the repo, your resume and LinkedIn Featured
- [ ] 60 to 90 second cut posted natively on LinkedIn, YouTube link in the first comment
- [ ] `NOTES.md` filled in, including the discovery call
- [ ] Notebooks pushed to the public repo

## Cost and limits

Free Edition caps serverless compute daily. This sprint is small (about 620k rows), but do not loop the full dataset while debugging. If compute stops, you have hit the daily quota. Your data is safe and it resets tomorrow.
