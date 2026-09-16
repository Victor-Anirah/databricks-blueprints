"""Fetch 5 years of hourly U.S. grid demand from the EIA Open Data API (v2)
and land it as raw JSON Lines files, one per region.

Why this runs on your laptop: Databricks Free Edition only allows outbound
calls to a short list of trusted domains, so a notebook cannot reach
api.eia.gov. You fetch here, then upload data/landing/ to a Unity Catalog
volume (see 01_bronze.sql).

Usage:
    python fetch_eia.py            # full run, about 620k rows
    python fetch_eia.py --sample   # one page of US48, to test your key

The API key is read from EIA_API_KEY in the environment or the repo's .env
file. It is never printed.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://api.eia.gov/v2/electricity/rto/region-data/data/"
PAGE = 5000  # EIA's maximum rows per request
# The 13 EIA-930 regions plus the Lower 48 total, verified against the API's
# respondent facet on 2026-09-15.
REGIONS = ["CAL", "CAR", "CENT", "FLA", "MIDA", "MIDW", "NE", "NW", "NY",
           "SE", "SW", "TEN", "TEX", "US48"]
ROOT = Path(__file__).resolve().parent.parent


def api_key():
    key = os.environ.get("EIA_API_KEY")
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("EIA_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("EIA_API_KEY not found. Copy .env.example to .env and add your key.")
    return key


def get_page(key, region, start, offset):
    params = [
        ("api_key", key),
        ("frequency", "hourly"),
        ("data[0]", "value"),
        ("facets[respondent][]", region),
        ("facets[type][]", "D"),
        ("start", start),
        # Oldest first, so hours EIA publishes during the run land on the last
        # page instead of shifting rows between pages.
        ("sort[0][column]", "period"),
        ("sort[0][direction]", "asc"),
        ("offset", str(offset)),
        ("length", str(PAGE)),
    ]
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        wait = 5 * 2 ** attempt
        try:
            with urllib.request.urlopen(url, timeout=90) as r:
                return json.load(r)["response"]
        except urllib.error.HTTPError as e:
            # Never print the URL or the exception text: the URL carries the key.
            if e.code in (429, 500, 502, 503, 504) and attempt < 4:
                print(f"    HTTP {e.code}, retrying in {wait}s")
                time.sleep(wait)
                continue
            sys.exit(f"EIA returned HTTP {e.code} for {region} at offset {offset}.")
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < 4:
                print(f"    network error ({type(e).__name__}), retrying in {wait}s")
                time.sleep(wait)
                continue
            sys.exit(f"Network error for {region} at offset {offset}: {type(e).__name__}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--years", type=int, default=5, help="how far back to fetch (default 5)")
    ap.add_argument("--sample", action="store_true", help="one page of US48 only")
    ap.add_argument("--out", default=str(ROOT / "data" / "landing"), help="output folder")
    args = ap.parse_args()

    key = api_key()
    now = datetime.now(timezone.utc)
    start = f"{now.year - args.years}-{now.month:02d}-01T00"
    regions = ["US48"] if args.sample else REGIONS
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source": API,
        "series": "EIA-930 hourly demand (type D), UTC",
        "start": start,
        "fetched_at_utc": now.isoformat(timespec="seconds"),
        "regions": {},
    }
    print(f"Fetching hourly demand since {start} UTC for {len(regions)} region(s)\n")
    t0 = time.time()
    total_rows = 0

    for region in regions:
        r0 = time.time()
        rows = pages = 0
        api_total = None
        first = last = None
        path = out / f"eia_region_demand_{region}.json"
        with path.open("w", encoding="utf-8") as f:
            offset = 0
            while True:
                resp = get_page(key, region, start, offset)
                api_total = int(resp["total"])
                data = resp["data"]
                pages += 1
                for rec in data:
                    # Written exactly as EIA returned it. Cleaning is silver's job.
                    f.write(json.dumps(rec) + "\n")
                rows += len(data)
                if data:
                    first = first or data[0]["period"]
                    last = data[-1]["period"]
                offset += PAGE
                if args.sample or not data or offset >= api_total:
                    break
                time.sleep(0.3)

        secs = time.time() - r0
        total_rows += rows
        manifest["regions"][region] = {
            "rows": rows, "api_total": api_total, "pages": pages,
            "first_period": first, "last_period": last, "seconds": round(secs, 1),
        }
        mismatch = "" if args.sample or rows == api_total else f"   <-- EIA reported {api_total:,}"
        print(f"  {region:<5} {rows:>8,} rows  {pages:>2} pages  {first} to {last}  {secs:5.1f}s{mismatch}")

    manifest["total_rows"] = total_rows
    manifest["seconds"] = round(time.time() - t0, 1)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"\nDone: {total_rows:,} rows across {len(regions)} region(s) in {manifest['seconds']}s")
    print(f"Files: {out}")
    print("Next: write the row counts and runtime in NOTES.md, then upload the .json files to your volume.")


if __name__ == "__main__":
    main()
