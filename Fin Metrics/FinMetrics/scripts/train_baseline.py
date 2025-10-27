"""
FinMetrics - Stage 5: ML Baseline (Up/Down Classifier)
- Reads cleaned features from SQLite table `prices_metrics`
- Builds lagged features (no leakage), trains Logistic Regression (baseline)
- Time-ordered split (80/20)
- Saves:
  * data/processed/predictions.csv
  * models/forecasts/forecasts.csv  (same file for convenience)
  * models/artifacts/logreg_baseline.joblib
- Prints evaluation metrics
"""

from __future__ import annotations
import os
import sqlite3
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score, classification_report
from sklearn.model_selection import TimeSeriesSplit
import joblib

from src.config import DB_PATH, DATA_PROCESSED, MODELS_DIR, FORECASTS_DIR, RANDOM_SEED

np.random.seed(RANDOM_SEED)

ARTIFACT_PATH = Path(MODELS_DIR) / "artifacts" / "logreg_baseline.joblib"
PREDICTIONS_PATH = Path(DATA_PROCESSED) / "predictions.csv"
FORECASTS_PATH = Path(FORECASTS_DIR) / "forecasts.csv"

FEATURES_BASE = [
    "daily_return", "ma7", "ma30", "volatility_21d", "rsi14"
]

def build_dataset() -> pd.DataFrame:
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

    # --- Lag features to avoid leakage ---
    def add_lags(g: pd.DataFrame) -> pd.DataFrame:
        g = g.copy()
        g["ret_lag1"] = g["daily_return"].shift(1)
        g["ret_lag2"] = g["daily_return"].shift(2)
        g["ma_ratio_7"] = (g["Close"] / g["ma7"]) - 1.0
        g["ma_ratio_30"] = (g["Close"] / g["ma30"]) - 1.0
        g["mom_5"] = g["daily_return"].rolling(5).sum()
        return g

    df = df.groupby("ticker", group_keys=False).apply(add_lags)

    # Drop rows with any NaNs (mainly from lags/rolls)
    df = df.dropna().reset_index(drop=True)
    return df

def train_and_evaluate(df: pd.DataFrame):
    # Chronological split (80/20 by date)
    min_d, max_d = df["date"].min(), df["date"].max()
    split_date = df["date"].quantile(0.8)
    train = df[df["date"] <= split_date].copy()
    test  = df[df["date"]  > split_date].copy()

    # One-hot for ticker (small number of categories)
    train = pd.get_dummies(train, columns=["ticker"], drop_first=False)
    test  = pd.get_dummies(test,  columns=["ticker"], drop_first=False)
    # align to same columns
    test = test.reindex(columns=train.columns, fill_value=0)

    y_train = train["target_up_next_day"].astype(int).values
    y_test  = test["target_up_next_day"].astype(int).values

    # Feature columns (exclude target & non-features)
    exclude = {"date","target_up_next_day"}
    feat_cols = [c for c in train.columns if c not in exclude]

    # Separate numeric features for scaling (everything except the one-hots)
    numeric_cols = [c for c in feat_cols if not c.startswith("ticker_")]
    passthrough_cols = [c for c in feat_cols if c.startswith("ticker_")]

    pre = ColumnTransformer(
        transformers=[
            ("num", StandardScaler(), numeric_cols),
            ("cat", "passthrough", passthrough_cols),
        ],
        remainder="drop"
    )

    clf = LogisticRegression(
        max_iter=2000,
        class_weight="balanced",
        solver="lbfgs",
        n_jobs=None
    )

    pipe = Pipeline([
        ("pre", pre),
        ("clf", clf)
    ])

    pipe.fit(train[feat_cols], y_train)
    prob_test = pipe.predict_proba(test[feat_cols])[:, 1]
    pred_test = (prob_test >= 0.5).astype(int)

    metrics = {
        "accuracy": accuracy_score(y_test, pred_test),
        "precision": precision_score(y_test, pred_test, zero_division=0),
        "recall": recall_score(y_test, pred_test, zero_division=0),
        "f1": f1_score(y_test, pred_test, zero_division=0),
        "roc_auc": roc_auc_score(y_test, prob_test),
        "train_start": str(train["date"].min().date()),
        "train_end": str(train["date"].max().date()),
        "test_start": str(test["date"].min().date()),
        "test_end": str(test["date"].max().date()),
        "n_train": int(len(train)),
        "n_test": int(len(test)),
    }

    # Build predictions DataFrame (only necessary columns)
    keep_cols = [c for c in test.columns if c in ["date","Close"] or c.startswith("ticker_")]
    preds = test[keep_cols].copy()
    # Recover ticker name from one-hots
    onehot_cols = [c for c in preds.columns if c.startswith("ticker_")]
    preds["ticker"] = preds[onehot_cols].idxmax(axis=1).str.replace("ticker_","",regex=False)
    preds = preds.drop(columns=onehot_cols)

    preds["prob_up"] = prob_test
    preds["pred_up"] = pred_test
    preds["true_up"] = y_test

    # Order & sort
    preds = preds[["date","ticker","Close","prob_up","pred_up","true_up"]].sort_values(["ticker","date"])
    return pipe, preds, metrics

def main():
    # Ensure dirs
    Path(DATA_PROCESSED).mkdir(parents=True, exist_ok=True)
    (Path(MODELS_DIR) / "artifacts").mkdir(parents=True, exist_ok=True)
    Path(FORECASTS_DIR).mkdir(parents=True, exist_ok=True)

    print("📚 Loading dataset...")
    df = build_dataset()
    print("Shape after lags:", df.shape)

    print("🤖 Training baseline Logistic Regression...")
    model, preds, metrics = train_and_evaluate(df)

    # Save artifacts
    joblib.dump(model, ARTIFACT_PATH)
    preds.to_csv(PREDICTIONS_PATH, index=False)
    preds.to_csv(FORECASTS_PATH, index=False)

    print("\n✅ Saved:")
    print(" - Model:", ARTIFACT_PATH)
    print(" - Predictions (processed):", PREDICTIONS_PATH)
    print(" - Forecasts (models/):", FORECASTS_PATH)

    print("\n📈 Evaluation (test set):")
    for k in ["accuracy","precision","recall","f1","roc_auc"]:
        print(f" {k:>9}: {metrics[k]:.3f}")
    print(f" Train: {metrics['train_start']} → {metrics['train_end']}  (n={metrics['n_train']})")
    print(f" Test : {metrics['test_start']}  → {metrics['test_end']}   (n={metrics['n_test']})")

if __name__ == "__main__":
    main()