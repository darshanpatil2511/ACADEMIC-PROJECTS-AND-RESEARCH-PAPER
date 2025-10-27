# src/features.py
from __future__ import annotations
import numpy as np
import pandas as pd

TRADING_DAYS = 252

def ensure_business_calendar(df: pd.DataFrame) -> pd.DataFrame:
    """
    Reindex each ticker to business days and forward-fill price fields.
    Handles duplicate dates per ticker safely.

    Expected columns: date, ticker, Open, High, Low, Close, Volume
    """
    df = df.copy()
    df["date"] = pd.to_datetime(df["date"])

    out = []
    for tkr, g in df.groupby("ticker", sort=True):
        # sort and drop duplicate dates (keep last to match yfinance melt behavior)
        g = g.sort_values("date").drop_duplicates(subset=["date"], keep="last")

        # make a continuous business-day index
        idx = pd.date_range(g["date"].min(), g["date"].max(), freq="B")

        # set index and reindex; forward-fill OHLC
        g = g.set_index("date").reindex(idx)
        g.index.name = "date"

        # restore ticker label
        g["ticker"] = tkr

        # forward-fill prices; volume: 0 for non-trading days then fillna(0)
        for col in ["Open", "High", "Low", "Close"]:
            g[col] = g[col].ffill()
        g["Volume"] = g["Volume"].fillna(0)

        # backfill first row if needed (in case the very first business day was missing)
        for col in ["Open", "High", "Low", "Close"]:
            if g[col].isna().any():
                g[col] = g[col].bfill()

        g = g.reset_index().rename(columns={"index": "date"})
        out.append(g)

    return pd.concat(out, ignore_index=True)

def rsi(series: pd.Series, window: int = 14) -> pd.Series:
    """Relative Strength Index (Wilder's smoothing)."""
    delta = series.diff()
    up = delta.clip(lower=0)
    down = -delta.clip(upper=0)
    # Wilder's RMA
    roll_up = up.ewm(alpha=1/window, adjust=False).mean()
    roll_down = down.ewm(alpha=1/window, adjust=False).mean()
    rs = roll_up / roll_down.replace(0, np.nan)
    return 100 - (100 / (1 + rs))

def add_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """
    Adds daily_return, ma7, ma30, volatility_21d, rsi14 and a classification label:
    target_up_next_day (1 if next day's Close > today's Close).
    """
    df = df.copy().sort_values(["ticker", "date"])
    df["daily_return"] = df.groupby("ticker")["Close"].pct_change()

    df["ma7"] = df.groupby("ticker")["Close"].transform(lambda s: s.rolling(7).mean())
    df["ma30"] = df.groupby("ticker")["Close"].transform(lambda s: s.rolling(30).mean())

    # annualized volatility from 21-day rolling std of daily returns
    df["volatility_21d"] = (
        df.groupby("ticker")["daily_return"]
          .transform(lambda s: s.rolling(21).std())
        * np.sqrt(TRADING_DAYS)
    )

    df["rsi14"] = df.groupby("ticker")["Close"].transform(lambda s: rsi(s, 14))

    # label for ML (used later)
    df["target_up_next_day"] = (
        df.groupby("ticker")["Close"].shift(-1) > df["Close"]
    ).astype(int)

    # drop first rows per ticker where indicators are NaN
    df = df.groupby("ticker", group_keys=False).apply(
        lambda g: g.iloc[30:]  # enough warm-up for MA30 & RSI
    )
    return df.reset_index(drop=True)