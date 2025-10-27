"""
FinMetrics - Stage 2: Data Collection
Fetches 10 years of OHLCV data for tickers in src/config.py,
saves raw CSVs, and writes a combined table into finmetrics.db.
"""

import os
from datetime import datetime, timedelta
import pandas as pd
import yfinance as yf
from sqlalchemy import create_engine
from tqdm import tqdm
import warnings
from src.config import DATA_RAW, DB_PATH, SQLALCHEMY_URL, TICKERS, YEARS_HISTORY

warnings.filterwarnings("ignore")

def fetch_ticker_data(ticker: str, start: datetime, end: datetime) -> pd.DataFrame:
    """Download one ticker's OHLCV data and return a tidy DataFrame."""
    df = yf.download(ticker, start=start, end=end, auto_adjust=True, progress=False)
    if df.empty:
        print(f"⚠️ No data for {ticker}")
        return pd.DataFrame()
    df.reset_index(inplace=True)
    df["ticker"] = ticker
    return df

def main():
    print("📡 Starting FinMetrics data collection ...")
    os.makedirs(DATA_RAW, exist_ok=True)

    end_date = datetime.today()
    start_date = end_date - timedelta(days=365 * YEARS_HISTORY)
    print(f"Collecting data from {start_date.date()} to {end_date.date()}")

    all_data = []
    for ticker in tqdm(TICKERS, desc="Fetching tickers"):
        df = fetch_ticker_data(ticker, start_date, end_date)
        if not df.empty:
            # save individual CSV
            raw_path = DATA_RAW / f"{ticker}.csv"
            df.to_csv(raw_path, index=False)
            all_data.append(df)

    if not all_data:
        print("❌ No data fetched. Check internet or tickers.")
        return

    combined = pd.concat(all_data, ignore_index=True)
    print(f"✅ Combined shape: {combined.shape}")

    # Save combined CSV
    combined_path = DATA_RAW / "all_stocks_raw.csv"
    combined.to_csv(combined_path, index=False)
    print(f"💾 Saved combined CSV to {combined_path}")

    # Write to SQLite
    engine = create_engine(SQLALCHEMY_URL)
    with engine.begin() as conn:
        combined.to_sql("raw_prices", conn, if_exists="replace", index=False)
    print(f"📘 Data written to SQLite at {DB_PATH}")

if __name__ == "__main__":
    main()