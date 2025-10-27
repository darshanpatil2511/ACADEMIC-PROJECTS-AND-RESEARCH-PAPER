"""
FinMetrics - Per-ticker baselines
Trains one LogisticRegression per ticker using the same features/labels as the baseline.
Outputs:
  - models/artifacts/per_ticker/<TICKER>_logreg.joblib
  - models/forecasts/predictions_per_ticker.csv (combined)
  - data/processed/per_ticker_metrics.csv (per-ticker test metrics)
"""

from __future__ import annotations
import os, sqlite3
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
import joblib

from src.config import DB_PATH, DATA_PROCESSED, MODELS_DIR, FORECASTS_DIR, RANDOM_SEED

np.random.seed(RANDOM_SEED)
ART_DIR = Path(MODELS_DIR) / "artifacts" / "per_ticker"
OUT_PRED = Path(FORECASTS_DIR) / "predictions_per_ticker.csv"
OUT_METRICS = Path(DATA_PROCESSED) / "per_ticker_metrics.csv"

BASE_FEATURES = ["daily_return","ma7","ma30","volatility_21d","rsi14","Close"]

def load_long() -> pd.DataFrame:
    con = sqlite3.connect(DB_PATH)
    df = pd.read_sql("""
        SELECT date, ticker, Close, daily_return, ma7, ma30, volatility_21d, rsi14, target_up_next_day
        FROM prices_metrics
        WHERE daily_return IS NOT NULL
          AND ma7 IS NOT NULL AND ma30 IS NOT NULL
          AND volatility_21d IS NOT NULL AND rsi14 IS NOT NULL
    """, con)
    con.close()
    df["date"] = pd.to_datetime(df["date"])
    df = df.sort_values(["ticker","date"]).reset_index(drop=True)

    # add lags (same as baseline)
    def add_lags(g: pd.DataFrame) -> pd.DataFrame:
        g = g.copy()
        g["ret_lag1"] = g["daily_return"].shift(1)
        g["ret_lag2"] = g["daily_return"].shift(2)
        g["ma_ratio_7"] = (g["Close"] / g["ma7"]) - 1.0
        g["ma_ratio_30"] = (g["Close"] / g["ma30"]) - 1.0
        g["mom_5"] = g["daily_return"].rolling(5).sum()
        return g

    df = df.groupby("ticker", group_keys=False).apply(add_lags)
    df = df.dropna().reset_index(drop=True)
    return df

def train_one_ticker(g: pd.DataFrame, tkr: str):
    # chronological 80/20
    split_date = g["date"].quantile(0.8)
    tr = g[g["date"] <= split_date].copy()
    te = g[g["date"]  > split_date].copy()

    y_tr = tr["target_up_next_day"].astype(int).values
    y_te = te["target_up_next_day"].astype(int).values

    feat_cols = [c for c in tr.columns if c not in {"date","ticker","target_up_next_day"}]

    pre = ColumnTransformer(
        [("num", StandardScaler(), feat_cols)],
        remainder="drop"
    )
    clf = LogisticRegression(max_iter=2000, class_weight="balanced")
    pipe = Pipeline([("pre", pre), ("clf", clf)])

    pipe.fit(tr[feat_cols], y_tr)
    prob = pipe.predict_proba(te[feat_cols])[:,1]
    pred = (prob >= 0.5).astype(int)

    metrics = {
        "ticker": tkr,
        "accuracy": accuracy_score(y_te, pred),
        "precision": precision_score(y_te, pred, zero_division=0),
        "recall": recall_score(y_te, pred, zero_division=0),
        "f1": f1_score(y_te, pred, zero_division=0),
        "roc_auc": roc_auc_score(y_te, prob) if len(np.unique(y_te))>1 else np.nan,
        "n_train": int(len(tr)),
        "n_test": int(len(te))
    }

    preds = te[["date","ticker","Close"]].copy()
    preds["prob_up"] = prob
    preds["pred_up"] = pred
    preds["true_up"] = y_te

    # save artifact
    ART_DIR.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipe, ART_DIR / f"{tkr}_logreg.joblib")

    return preds, metrics

def main():
    df = load_long()
    all_preds = []
    rows = []
    for tkr, g in df.groupby("ticker", sort=True):
        preds, m = train_one_ticker(g, tkr)
        all_preds.append(preds)
        rows.append(m)
        print(f"✅ {tkr}: acc={m['accuracy']:.3f}, f1={m['f1']:.3f}, auc={m['roc_auc']:.3f}")

    out_preds = pd.concat(all_preds, ignore_index=True).sort_values(["ticker","date"])
    out_preds.to_csv(OUT_PRED, index=False)
    pd.DataFrame(rows).sort_values("f1", ascending=False).to_csv(OUT_METRICS, index=False)

    print("\nSaved:")
    print(" -", OUT_PRED)
    print(" -", OUT_METRICS)
    print(" - Models:", ART_DIR, "(one file per ticker)")

if __name__ == "__main__":
    main()