-- FinMetrics: Key SQL Queries

-- 1. Basic info
SELECT ticker, COUNT(*) AS rows, MIN(date) AS start, MAX(date) AS end
FROM prices_metrics
GROUP BY ticker
ORDER BY ticker;

-- 2. Average Daily Return per Ticker
SELECT ticker, ROUND(AVG(daily_return)*100,2) AS avg_return_pct
FROM prices_metrics
GROUP BY ticker
ORDER BY avg_return_pct DESC;

-- 3. Top 10 Volatility Stocks
SELECT ticker, ROUND(AVG(volatility_21d),4) AS avg_volatility
FROM prices_metrics
GROUP BY ticker
ORDER BY avg_volatility DESC
LIMIT 10;

-- 4. Highest RSI Levels (Overbought)
SELECT ticker, date, ROUND(rsi14,2) AS rsi
FROM prices_metrics
WHERE rsi14 > 70
ORDER BY rsi DESC
LIMIT 20;

-- 5. Correlation Table (for Tableau)
-- Export this one via Python to CSV