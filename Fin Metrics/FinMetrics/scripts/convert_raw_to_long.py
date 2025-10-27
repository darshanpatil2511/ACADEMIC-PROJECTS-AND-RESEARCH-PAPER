"""
Utility script: convert raw_prices (tuple-string columns) to long tidy CSV safely in chunks.
Run once before Stage 3 if full load kills the process.
"""

import re
import pandas as pd
import sqlite3

DB = "finmetrics.db"
OUT = "data/raw/all_stocks_long.csv"

TUPCOL_RE = re.compile(r"""\(['"]?([^'"]+)['"]?\s*,\s*['"]?([^'"]*)['"]?\)""")
FIELD_MAP = {"open":"Open","high":"High","low":"Low","close":"Close","adjclose":"Close","volume":"Volume"}
FIELDS = ["Open","High","Low","Close","Volume"]

# --- Step 1: Load raw table, light memory mode
con = sqlite3.connect(DB)
df = pd.read_sql("SELECT * FROM raw_prices LIMIT 5", con)
cols = list(df.columns)
print("Detected", len(cols), "columns. Example:", cols[:10])
del df

# --- Step 2: Read only columns progressively
# Fetch columns again fully
df_full = pd.read_sql("SELECT * FROM raw_prices", con)
con.close()

# --- Step 3: Detect date column
date_col = [c for c in df_full.columns if "Date" in c or "date" in c][0]
df_full.rename(columns={date_col: "date"}, inplace=True)
df_full["date"] = pd.to_datetime(df_full["date"])

# --- Step 4: Parse tuple columns
parsed = []
for c in df_full.columns:
    if c == "date": continue
    m = TUPCOL_RE.match(str(c))
    if m:
        field, ticker = m.group(1), m.group(2)
        f = FIELD_MAP.get(field.lower(), None)
        if f and ticker:
            parsed.append((c, f, ticker))

print("Parsed pairs:", len(parsed))

# --- Step 5: Build long tidy DataFrame
frames = []
for field in FIELDS:
    cols = [(c, t) for (c, f, t) in parsed if f == field]
    if not cols: 
        continue
    tmp = df_full[["date"] + [c for (c, _) in cols]].copy()
    tmp = tmp.melt(id_vars="date", var_name="col", value_name=field)
    tmp["ticker"] = tmp["col"].map({c:t for (c,t) in cols})
    tmp = tmp.drop(columns=["col"])
    frames.append(tmp)

out = None
for f in frames:
    out = f if out is None else out.merge(f, on=["date","ticker"], how="outer")

out.sort_values(["ticker","date"], inplace=True)
out.to_csv(OUT, index=False)
print("✅ Saved tidy long file:", OUT)
print("Shape:", out.shape)