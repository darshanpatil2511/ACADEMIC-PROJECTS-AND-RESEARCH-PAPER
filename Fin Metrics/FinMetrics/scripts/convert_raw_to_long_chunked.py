"""
Chunked converter: raw_prices (tuple-string columns) → long tidy CSV.
Processes each ticker separately to avoid memory overflow.
"""

import re
import pandas as pd
import sqlite3
from pathlib import Path

DB = "finmetrics.db"
OUT = Path("data/raw/all_stocks_long.csv")

TUPCOL_RE = re.compile(r"""\(['"]?([^'"]+)['"]?\s*,\s*['"]?([^'"]*)['"]?\)""")
FIELD_MAP = {"open":"Open","high":"High","low":"Low","close":"Close","adjclose":"Close","volume":"Volume"}
FIELDS = ["Open","High","Low","Close","Volume"]

# Connect
con = sqlite3.connect(DB)
df = pd.read_sql("SELECT * FROM raw_prices LIMIT 2", con)
cols = list(df.columns)
print("Detected", len(cols), "columns. Example:", cols[:8])
del df

# Find date column
date_col = [c for c in cols if "Date" in c or "date" in c][0]

# Build mapping {ticker: {field: column_name}}
mapping = {}
for c in cols:
    if c == date_col:
        continue
    m = TUPCOL_RE.match(str(c))
    if not m:
        continue
    field, ticker = m.group(1), m.group(2)
    f = FIELD_MAP.get(field.lower(), None)
    if not f or not ticker:
        continue
    mapping.setdefault(ticker.upper(), {})[f] = c

tickers = sorted(mapping.keys())
print("Found", len(tickers), "tickers:", tickers)

# Output file
if OUT.exists():
    OUT.unlink()

# Process one ticker at a time
chunks = []
for i, t in enumerate(tickers, 1):
    cols_needed = [date_col] + list(mapping[t].values())
    q = f"SELECT {', '.join([f'[{c}]' for c in cols_needed])} FROM raw_prices"
    df_t = pd.read_sql(q, con)
    df_t.rename(columns={date_col: "date"}, inplace=True)
    df_t["date"] = pd.to_datetime(df_t["date"])
    for f, orig in mapping[t].items():
        df_t.rename(columns={orig: f}, inplace=True)
    df_t["ticker"] = t
    df_t = df_t[["date","ticker","Open","High","Low","Close","Volume"]]
    df_t.to_csv(OUT, mode="a", index=False, header=not OUT.exists())
    print(f"{i:02d}/{len(tickers)} ✅ {t} rows:", len(df_t))

con.close()
print("✅ Finished writing:", OUT)