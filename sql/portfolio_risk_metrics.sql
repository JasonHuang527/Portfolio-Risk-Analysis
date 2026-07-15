/* ============================================================================
   Portfolio Risk Metrics  —  SQLite  (run against dailyreturn.db)
   ----------------------------------------------------------------------------
   Recreates the data pipeline behind the project: raw daily prices -> portfolio
   value -> daily returns, drawdown, and the headline risk metrics.

   Tables in the database:
     holdings(ticker TEXT, shares INTEGER)          -- 10 rows
     stock_prices(Date TEXT, Ticker TEXT, Close REAL, High, Low, Open, Volume)

   Portfolio value on a day = SUM(shares * Close) across the holdings.

   TWO SERIES (flip the JOIN filter to switch between them):
     - PORTFOLIO  : all holdings            -> leave the WHERE line out (default)
     - BENCHMARK  : S&P 500 only            -> add   WHERE h.ticker = 'SPY'

   Verified: the PORTFOLIO output below reproduces the workbook exactly —
   start $109,967.49, end $232,446.09, CAGR 18.08%, volatility 24.6%,
   Sharpe 0.65, max drawdown -36.21%.

   HOW TO RUN IN DB BROWSER: click inside one query block, press Ctrl+Enter
   (running everything at once only shows the last result grid).
   ============================================================================ */


/* ---------------------------------------------------------------------------
   QUERY 1 — DAILY SERIES  (date, value, prev value, daily return %, drawdown, month)
   LAG() gives the previous day's value; a running MAX() gives the peak.
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.Date                  AS date,
           SUM(h.shares * p.Close) AS portfolio_value
    FROM   stock_prices p
    JOIN   holdings     h ON h.ticker = p.Ticker
    -- WHERE h.ticker = 'SPY'          -- uncomment for the S&P 500 benchmark line
    GROUP  BY p.Date
),
with_prev AS (
    SELECT date,
           portfolio_value,
           LAG(portfolio_value) OVER (ORDER BY date) AS prev_value
    FROM   daily_value
),
with_metrics AS (
    SELECT date,
           portfolio_value,
           prev_value,
           ROUND((portfolio_value / prev_value - 1) * 100, 2) AS daily_return_pct,
           MAX(portfolio_value) OVER (
               ORDER BY date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS running_peak
    FROM   with_prev
)
SELECT date,
       portfolio_value,
       prev_value,
       daily_return_pct,
       portfolio_value / running_peak - 1 AS drawdown,   -- <= 0, peak-to-current
       strftime('%Y-%m', date)            AS month
FROM   with_metrics
ORDER  BY date;


/* ---------------------------------------------------------------------------
   QUERY 2 — MONTHLY ROLL-UP  (month, start value, end value, monthly return %)
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.Date AS date, SUM(h.shares * p.Close) AS portfolio_value
    FROM   stock_prices p
    JOIN   holdings     h ON h.ticker = p.Ticker
    -- WHERE h.ticker = 'SPY'          -- uncomment for the benchmark
    GROUP  BY p.Date
),
tagged AS (
    SELECT strftime('%Y-%m', date) AS month,
           portfolio_value,
           FIRST_VALUE(portfolio_value) OVER (
               PARTITION BY strftime('%Y-%m', date) ORDER BY date
           ) AS start_value,
           LAST_VALUE(portfolio_value) OVER (
               PARTITION BY strftime('%Y-%m', date) ORDER BY date
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS end_value
    FROM   daily_value
)
SELECT DISTINCT
       month,
       start_value,
       end_value,
       end_value / start_value - 1 AS monthly_return_pct
FROM   tagged
ORDER  BY month;


/* ---------------------------------------------------------------------------
   QUERY 3 — HEADLINE RISK METRICS  (CAGR, volatility, Sharpe, max drawdown)
   Assumes 252 trading days/year and a 2% risk-free rate.
   (SQLite has no STDDEV, so the variance is computed by hand.)
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.Date AS date, SUM(h.shares * p.Close) AS pv
    FROM   stock_prices p
    JOIN   holdings     h ON h.ticker = p.Ticker
    -- WHERE h.ticker = 'SPY'          -- uncomment for the benchmark
    GROUP  BY p.Date
),
rets AS (
    SELECT date, pv,
           pv * 1.0 / LAG(pv) OVER (ORDER BY date) - 1 AS r,
           MAX(pv) OVER (ORDER BY date
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS peak
    FROM   daily_value
),
agg AS (
    SELECT COUNT(r) AS n, SUM(r) AS sr, SUM(r*r) AS sr2,
           MIN(pv/peak - 1) AS maxdd,
           (SELECT pv FROM rets ORDER BY date ASC  LIMIT 1) AS v0,
           (SELECT pv FROM rets ORDER BY date DESC LIMIT 1) AS v1,
           (SELECT julianday(MAX(date)) - julianday(MIN(date)) FROM rets) AS days
    FROM   rets
    WHERE  r IS NOT NULL
)
SELECT
    ROUND((pow(v1/v0, 365.25/days) - 1) * 100, 2)                       AS cagr_pct,
    ROUND(sqrt((sr2 - sr*sr/n) / (n-1)) * sqrt(252) * 100, 2)           AS ann_volatility_pct,
    ROUND((pow(v1/v0, 365.25/days) - 1 - 0.02)
          / (sqrt((sr2 - sr*sr/n) / (n-1)) * sqrt(252)), 2)            AS sharpe_ratio_rf2pct,
    ROUND(maxdd * 100, 2)                                               AS max_drawdown_pct
FROM agg;
