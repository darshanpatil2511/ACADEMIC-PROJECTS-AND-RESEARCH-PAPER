from pathlib import Path

# ---- Paths ----
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_RAW = PROJECT_ROOT / "data" / "raw"
DATA_PROCESSED = PROJECT_ROOT / "data" / "processed"
DB_PATH = PROJECT_ROOT / "finmetrics.db"  # SQLite file in project root
TABLEAU_EXPORTS = PROJECT_ROOT / "tableau" / "exports"
MODELS_DIR = PROJECT_ROOT / "models"
FORECASTS_DIR = MODELS_DIR / "forecasts"

# Ensure important dirs exist at import-time
for p in [DATA_RAW, DATA_PROCESSED, TABLEAU_EXPORTS, FORECASTS_DIR]:
    p.mkdir(parents=True, exist_ok=True)

# ---- Data scope ----
YEARS_HISTORY = 10
TICKERS = [
    "AAPL","MSFT","NVDA","AMZN","GOOGL","META","TSLA",
    "JPM","V","UNH","XOM","PG","KO","PEP","HD"
]

# ---- Database ----
SQLALCHEMY_URL = f"sqlite:///{DB_PATH.as_posix()}"
DEFAULT_TABLE = "prices_metrics"  # will be created later

# ---- Random seeds for reproducibility ----
RANDOM_SEED = 42