"""
FinMetrics - Stage 3: Cleaning & Feature Engineering (tuple-column robust)
- Handles raw_prices with columns like "('Close','AAPL')" from a MultiIndex wide frame.
- Converts WIDE -> LONG (date, ticker, Open, High, Low, Close, Volume)
- Ensures business-day calendar, forward-fills prices
- Adds indicators (daily_return, MA7/MA30, volatility_21d, RSI14, target label)
- Writes CSV + SQLite table 'prices_metrics'
"""

import os
import re
import pandas as pd
from sqlalchemy import create_engine
from pandas.api.types import is_datetime64_any_dtype as is_datetime

from src.config import DATA_PROCESSED, DB_PATH, SQLALCHEMY_URL, DATA_RAW
from src.features import ensure_business_calendar, add_indicators

RAW_TABLE = "raw_prices"
OUT_TABLE = "prices_metrics"
OUT_CSV = DATA_PROCESSED / "metrics_long.csv"

FIELD_ALIASES = {
    "open": "Open",
    "high": "High",
    "low": "Low",
    "close": "Close",
    "adjclose": "Close",
    "adj_close": "Close",
    "adj close": "Close",
    "volume": "Volume",
}
CANON_FIELDS = ["Open", "High", "Low", "Close", "Volume"]

# Regex to capture columns like:  ('Close', 'AAPL')  OR  ("Close","AAPL")
TUPCOL_RE = re.compile(r"""\(['"]?([^'"]+)['"]?\s*,\s*['"]?([^'"]*)['"]?\)""")

def canon_field(token: str) -> str | None:
    key = re.sub(r"[^A-Za-z]", "", str(token)).lower()
    return FIELD_ALIASES.get(key, None)

def detect_date_column(df: pd.DataFrame) -> str:
    # Try obvious names (including tuple-string form)
    candidates = ["date","Date","DATE","Index","index","Unnamed: 0","Unnamed_0","('Date', '')","(\"Date\", \"\")"]
    for c in candidates:
        if c in df.columns:
            try:
                pd.to_datetime(df[c], errors="raise")
                return c
            except Exception:
                pass
    # Any datetime typed column?
    for c in df.columns:
        if is_datetime(df[c]):
            return c
    # Heuristic: most-parsable column
    best, rate = None, 0.0
    for c in df.columns:
        try:
            parsed = pd.to_datetime(df[c], errors="coerce")
            r = parsed.notna().mean()
            if r > rate and r >= 0.7:
                best, rate = c, r
        except Exception:
            continue
    if best is None:
        raise ValueError(f"Could not detect a date column. First 20 cols: {list(df.columns)[:20]}")
    return best

def parse_tuple_col(colname: str) -> tuple[str | None, str | None]:
    """
    Parse "('Close','AAPL')" -> ('Close','AAPL').
    Returns (field, ticker) or (None, None) if not matched.
    """
    m = TUPCOL_RE.match(str(colname))
    if not m:
        return (None, None)
    field_raw, ticker_raw = m.group(1), m.group(2)
    field = canon_field(field_raw)
    ticker = ticker_raw.upper().strip() if ticker_raw else ""
    return (field, ticker or None)

def wide_to_long_tuple_columns(df_raw: pd.DataFrame) -> pd.DataFrame:
    """
    Convert a WIDE df with tuple-string columns into LONG tidy:
        columns -> (date, ticker, Open, High, Low, Close, Volume)
    """
    df = df_raw.copy()
    date_col = detect_date_column(df)
    value_cols = [c for c in df.columns if c != date_col]

    parsed = []
    for c in value_cols:
        field, ticker = parse_tuple_col(c)
        if field in CANON_FIELDS and ticker:
            parsed.append((c, field, ticker))

    if not parsed:
        # Fallback: handle underscores like 'Close_AAPL'
        for c in value_cols:
            parts = re.split(r"[_\. ]+", str(c))
            if len(parts) >= 2:
                f = canon_field(parts[0]) or canon_field(parts[-1])
                t = (parts[1] if canon_field(parts[0]) else parts[0]).upper()
                if f in CANON_FIELDS:
                    parsed.append((c, f, t))

    if not parsed:
        raise ValueError("Could not parse any (field,ticker) from wide columns.")

    # Build per-field long frames and merge
    long_frames = []
    for field in CANON_FIELDS:
        cols = [(c, t) for (c, f, t) in parsed if f == field]
        if not cols:
            continue
        tmp = df[[date_col] + [c for (c, _) in cols]].copy()
        tmp = tmp.rename(columns={date_col: "date"})
        melted = tmp.melt(id_vars="date", var_name="col", value_name=field)
        col2ticker = {c: t for (c, t) in cols}
        melted["ticker"] = melted["col"].map(col2ticker)
        melted = melted.drop(columns=["col"])
        long_frames.append(melted)

    out = None
    for f in long_frames:
        out = f if out is None else out.merge(f, on=["date", "ticker"], how="outer")

    out["date"] = pd.to_datetime(out["date"])
    out = out.sort_values(["ticker", "date"]).reset_index(drop=True)

    # Ensure numeric types
    for c in ["Open","High","Low","Close","Volume"]:
        out[c] = pd.to_numeric(out[c], errors="coerce")
    return out[["date","ticker","Open","High","Low","Close","Volume"]]

def to_long_if_needed(df: pd.DataFrame) -> pd.DataFrame:
    cols = set(df.columns)
    # Already long?
    if {"date","ticker","Open","High","Low","Close","Volume"}.issubset(cols) or \
       {"Date","ticker","Open","High","Low","Close","Volume"}.issubset(cols):
        g = df.rename(columns={"Date":"date"}).copy()
        g["date"] = pd.to_datetime(g["date"])
        for c in ["Open","High","Low","Close","Volume"]:
            g[c] = pd.to_numeric(g[c], errors="coerce")
        return g[["date","ticker","Open","High","Low","Close","Volume"]]
    # Tuple-string wide
    if any(str(c).startswith("(") for c in df.columns):
        return wide_to_long_tuple_columns(df)
    # Fallback wide
    # (underscored forms like Close_AAPL)
    return wide_to_long_tuple_columns(df)  # reuse parser; it has a fallback too

def main():
    print("🧽 Stage 3: Cleaning & Feature Engineering")
    engine = create_engine(SQLALCHEMY_URL)

    print(f"Reading table 'raw_prices' from {DB_PATH} ...")
    raw = pd.read_csv(DATA_RAW / "all_stocks_long.csv")
    # raw = pd.read_sql(f"SELECT * FROM {RAW_TABLE}", engine) !!!!!REPLACEd file path
    print("Raw shape:", raw.shape)

    # Normalize spacing in column names
    raw.columns = [c.replace(" ", "_") for c in raw.columns]

    # Convert to long
    tidy = to_long_if_needed(raw)
    print("Tidy shape:", tidy.shape)

    # Business-day calendar + forward fill
    tidy = ensure_business_calendar(tidy)
    print("After calendar fix:", tidy.shape)

    # Indicators + label
    metrics = add_indicators(tidy)
    print("With indicators:", metrics.shape)

    # Save outputs
    os.makedirs(DATA_PROCESSED, exist_ok=True)
    metrics.to_csv(OUT_CSV, index=False)
    print(f"💾 Saved: {OUT_CSV}")

    with engine.begin() as conn:
        metrics.to_sql(OUT_TABLE, conn, if_exists="replace", index=False)
    print(f"📘 Wrote table '{OUT_TABLE}' to {DB_PATH}")

    print("\nPreview:")
    print(metrics.head(3).to_string(index=False))

if __name__ == "__main__":
    main()