# FinMetrics – Quantitative Stock Performance Analyzer  

**FinMetrics** is a full-stack analytics project that quantifies, visualizes, and forecasts stock performance and risk using **Python**, **SQL**, and **Tableau**.  
It showcases an end-to-end data science pipeline — from raw market data ingestion to machine learning–driven forecasts and interactive BI dashboards.  

**Live Dashboard:**  
[FinMetrics Dashboard – Tableau Public](https://public.tableau.com/app/profile/darshan.patil4472/viz/FinMetrics_Dashboard_v1_Stable/FinMetricsDashboard?publish=yes)

---

## Project Overview  
FinMetrics was designed to replicate a **real-world analytics workflow**:
1. Ingest **10 years of daily OHLCV stock data** using `yfinance`.
2. Engineer **risk and momentum features** like MA7/MA30, volatility, and RSI14.
3. Build interpretable **logistic regression classifiers** to predict next-day price direction.
4. Tune thresholds to optimize **F1-score** per ticker and train **per-ticker models**.
5. Visualize insights in an interactive **Tableau dashboard** that updates dynamically.

It demonstrates practical experience in **data engineering**, **feature pipelines**, **ML modeling**, and **business intelligence integration** — all in one cohesive system.

---

## Tech Stack  

### **Languages & Frameworks**
- **Python 3.13** – Data processing, modeling, and ETL  
- **SQL (SQLite)** – Persistent data store for intermediate and processed datasets  
- **Tableau Public** – Visualization, storytelling, and dashboard publishing  

### **Python Libraries**
`pandas`, `numpy`, `ta`, `scikit-learn`, `statsmodels`, `SQLAlchemy`, `matplotlib`, `seaborn`, `yfinance`, `joblib`  

---

## Repository Structure  
data/raw/         # raw downloads
data/processed/   # cleaned + features
notebooks/        # analysis notebooks
scripts/          # CLI scripts
src/              # reusable modules
sql/              # reusable queries
models/           # saved models + forecasts
tableau/          # workbook + exports
---

## Pipeline Stages  

| Stage | Description |
|--------|-------------|
| **1. Scaffold & Config** | Environment setup, folder creation, and constants defined in `src/config.py`. |
| **2. Data Collection** | 10Y OHLCV data fetched via `yfinance` and stored in both CSV + SQLite (`raw_prices`). |
| **3. Cleaning & Feature Engineering** | Handles missing days, adds business-day calendars, computes technical indicators (returns, MA, RSI, volatility), and creates the next-day target label. |
| **4. SQL + EDA** | Performs summary stats, correlation matrices, and exports Tableau-ready datasets. |
| **5. ML Baseline** | Trains global and per-ticker logistic regression models, evaluates performance, and tunes thresholds for best F1. |
| **6. Tableau + README Polish** | Builds public Tableau dashboard with filters, visuals, and KPIs for risk, return, and forecast accuracy. |

---

## The ML Engine  

- **Label:** `target_up_next_day = 1` if `Close(t+1) > Close(t)` else `0`  
- **Features:**  
  - Daily returns (%), MA7/MA30  
  - 21-day rolling volatility  
  - RSI14 (momentum)  
  - Lag1/Lag2/Lag3 for each  
- **Models:**  
  - Pooled Logistic Regression (baseline global model)  
  - Per-Ticker Logistic Regression (15 models)  
  - Threshold Sweep (0.1–0.9) to optimize F1-score  
- **Key Metrics:** Accuracy ~85%, ROC-AUC ~0.50–0.61  

All model artifacts, thresholds, and predictions are saved under `models/` and `data/processed/`.

---

## Tableau Dashboard Highlights  

**Dashboard Name:** `FinMetrics – Market Performance & Risk Analytics`  
- **Risk vs Return:** Volatility vs. average daily returns by ticker  
- **Coverage:** Data span per stock  
- **Correlation Heatmap:** Close-to-close correlations (−1 to +1)  
- **Forecast vs Actual:** Predicted probability overlays on price charts  

Dynamic filters let you explore by ticker and model type (tuned / per-ticker).  

---

## Data & Storage  

- **Source:** Yahoo Finance via `yfinance` (10 years daily OHLCV)  
- **Storage:**  
  - `data/raw/all_stocks_raw.csv`  
  - `finmetrics.db` → tables: `raw_prices`, `prices_metrics`, `predictions`, `predictions_tuned`  
- **ETL Scripts:**  
  - `collect_data.py` – Fetch & merge data  
  - `clean_features.py` – Calendar alignment + feature engineering  
  - `train_baseline.py`, `train_per_ticker.py`, `tune_threshold.py` – Model training & evaluation  

---

## 🧭 Roadmap  

| Stage | Focus |
|--------|-------|
| 1 | Project Scaffolding & Config Setup |
| 2 | Data Ingestion via yfinance |
| 3 | Cleaning + Feature Engineering |
| 4 | SQL Queries & EDA in Notebooks |
| 5 | ML Baselines, Tuning & Forecasts |
| 6 | Tableau Dashboard & Documentation |
 Future | Add XGBoost / LSTM models, deploy API endpoint for forecasts |

---

## Tools Used  
- **Python 3.13**  
- **SQLite + SQLAlchemy**  
- **Tableau Public (Dashboard Publishing)**  
- **Visual Studio Code / Jupyter Notebook**  
- **Git + GitHub (Version Control)**  

---

## Author  
**Darshan Patil**  
Master of Science in Information Systems, Northeastern University (Boston)  
📫 [LinkedIn](https://www.linkedin.com/in/darshan-patil14/) | [Tableau Public](https://public.tableau.com/app/profile/darshan.patil4472) | [GitHub](https://github.com/darshanpatil14)  

---

### Summary  
FinMetrics is more than a project — it’s a **portfolio-grade demonstration** of how a data professional engineers, models, and visualizes real financial data end-to-end.  
It’s technically robust, visually clear, and analytically explainable — exactly what modern analytics teams look for.  