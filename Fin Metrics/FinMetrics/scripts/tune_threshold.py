"""
FinMetrics - Threshold tuning (per ticker)
Reads baseline predictions.csv and finds the F1-optimal threshold per ticker.
Outputs:
  - data/processed/predictions_tuned.csv (adds pred_up_tuned, thresh_used)
  - data/processed/thresholds_by_ticker.csv (summary table)
"""

from __future__ import annotations
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import f1_score, precision_score, recall_score, accuracy_score, roc_auc_score
from src.config import DATA_PROCESSED

IN_PATH  = Path(DATA_PROCESSED) / "predictions.csv"
OUT_PATH = Path(DATA_PROCESSED) / "predictions_tuned.csv"
TH_PATH  = Path(DATA_PROCESSED) / "thresholds_by_ticker.csv"

def best_threshold_for_ticker(df_tk: pd.DataFrame, grid=None):
    if grid is None:
        grid = np.linspace(0.05, 0.95, 19)  # 0.05, 0.10, ..., 0.95
    y_true = df_tk["true_up"].astype(int).values
    p = df_tk["prob_up"].values
    best = {"threshold": 0.5, "f1": -1, "precision": 0.0, "recall": 0.0, "accuracy": 0.0}
    # handle degenerate AUC safely
    try:
        auc = roc_auc_score(y_true, p)
    except Exception:
        auc = np.nan
    for th in grid:
        y_pred = (p >= th).astype(int)
        f1 = f1_score(y_true, y_pred, zero_division=0)
        if f1 > best["f1"]:
            best.update({
                "threshold": float(th),
                "f1": float(f1),
                "precision": float(precision_score(y_true, y_pred, zero_division=0)),
                "recall": float(recall_score(y_true, y_pred, zero_division=0)),
                "accuracy": float(accuracy_score(y_true, y_pred)),
            })
    best["roc_auc"] = float(auc) if not np.isnan(auc) else np.nan
    return best

def main():
    df = pd.read_csv(IN_PATH, parse_dates=["date"])
    # sanity
    needed = {"date","ticker","prob_up","pred_up","true_up"}
    missing = needed - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns in {IN_PATH}: {missing}")

    rows = []
    tuned_parts = []
    for tkr, g in df.groupby("ticker", sort=True):
        g = g.sort_values("date").copy()
        stats = best_threshold_for_ticker(g)
        stats["ticker"] = tkr
        rows.append(stats)
        th = stats["threshold"]
        g["pred_up_tuned"] = (g["prob_up"] >= th).astype(int)
        g["thresh_used"] = th
        tuned_parts.append(g)

    th_df = pd.DataFrame(rows).sort_values("f1", ascending=False)
    tuned = pd.concat(tuned_parts, ignore_index=True)

    tuned.to_csv(OUT_PATH, index=False)
    th_df.to_csv(TH_PATH, index=False)

    print("✅ Wrote tuned predictions:", OUT_PATH)
    print("✅ Wrote thresholds summary:", TH_PATH)
    print("\nTop 5 thresholds by F1:")
    print(th_df[["ticker","threshold","f1","precision","recall","accuracy","roc_auc"]].head(5).to_string(index=False))

if __name__ == "__main__":
    main()