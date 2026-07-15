/* ============================================================================
   Portfolio Risk Metrics — daily return & drawdown series
   ----------------------------------------------------------------------------
   Reconstruction of the SQL used to structure the raw price data before the
   risk metrics (CAGR, volatility, Sharpe, max drawdown) were computed in Excel.

   Source tables (assumed):
     holdings(ticker TEXT, shares INT)              -- from holdings.csv
     prices(trade_date DATE, ticker TEXT, close NUMERIC)  -- daily close per name

   Portfolio value on a given day = SUM(shares * close) across the basket.
     - Tech portfolio : all holdings WHERE ticker <> 'SPY'  (9 names)
     - Benchmark      : just SPY                            (ticker = 'SPY')

   Dialect: written for PostgreSQL. SQLite / others differ only in date + LAST_VALUE:
     - PostgreSQL month label : TO_CHAR(trade_date, 'YYYY-MM')
     - SQLite month label     : strftime('%Y-%m', trade_date)
   ============================================================================ */


/* ---------------------------------------------------------------------------
   1) DAILY SERIES  ->  reproduces columns: date, PortfolioValue,
      PrevPortfolioValue, DailyReturnPct, Drawdown, Month
   Swap the WHERE filter to switch between the tech basket and the benchmark.
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.trade_date                       AS date,
           SUM(h.shares * p.close)            AS portfolio_value
    FROM   prices   p
    JOIN   holdings h ON h.ticker = p.ticker
    WHERE  h.ticker <> 'SPY'                  -- tech basket; use  = 'SPY'  for benchmark
    GROUP  BY p.trade_date
),

with_prev AS (
    SELECT date,
           portfolio_value,
           LAG(portfolio_value) OVER (ORDER BY date) AS prev_portfolio_value
    FROM   daily_value
),

with_metrics AS (
    SELECT date,
           portfolio_value,
           prev_portfolio_value,
           -- daily return, in percent, rounded to 2dp (as stored in the sheet)
           ROUND((portfolio_value / prev_portfolio_value - 1) * 100, 2) AS daily_return_pct,
           -- running peak = highest value seen up to and including today
           MAX(portfolio_value) OVER (
               ORDER BY date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS running_peak
    FROM   with_prev
)

SELECT date,
       portfolio_value,
       prev_portfolio_value,
       daily_return_pct,
       portfolio_value / running_peak - 1        AS drawdown,   -- <= 0, peak-to-current
       TO_CHAR(date, 'YYYY-MM')                  AS month
FROM   with_metrics
ORDER  BY date;


/* ---------------------------------------------------------------------------
   2) MONTHLY ROLL-UP  ->  reproduces: Month, Start Value, End Value,
      Monthly ReturnPct   (first vs last trading day within each month)
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.trade_date            AS date,
           SUM(h.shares * p.close) AS portfolio_value
    FROM   prices   p
    JOIN   holdings h ON h.ticker = p.ticker
    WHERE  h.ticker <> 'SPY'
    GROUP  BY p.trade_date
),

tagged AS (
    SELECT date,
           portfolio_value,
           TO_CHAR(date, 'YYYY-MM') AS month,
           FIRST_VALUE(portfolio_value) OVER (
               PARTITION BY TO_CHAR(date, 'YYYY-MM') ORDER BY date
           ) AS start_value,
           LAST_VALUE(portfolio_value) OVER (
               PARTITION BY TO_CHAR(date, 'YYYY-MM') ORDER BY date
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
   3) (Optional) Headline risk metrics straight from SQL, so the whole pipeline
      lives in the database instead of Excel. Assumes ~252 trading days/year
      and a 2% risk-free rate.
   --------------------------------------------------------------------------- */
WITH daily_value AS (
    SELECT p.trade_date            AS date,
           SUM(h.shares * p.close) AS portfolio_value
    FROM   prices   p
    JOIN   holdings h ON h.ticker = p.ticker
    WHERE  h.ticker <> 'SPY'
    GROUP  BY p.trade_date
),
rets AS (
    SELECT date,
           portfolio_value,
           portfolio_value / LAG(portfolio_value) OVER (ORDER BY date) - 1 AS daily_return
    FROM   daily_value
),
bounds AS (
    SELECT MIN(date) AS d0, MAX(date) AS d1,
           (SELECT portfolio_value FROM rets ORDER BY date ASC  LIMIT 1) AS v0,
           (SELECT portfolio_value FROM rets ORDER BY date DESC LIMIT 1) AS v1
    FROM   rets
)
SELECT
    POWER(b.v1 / b.v0, 365.25 / (b.d1 - b.d0)) - 1              AS cagr,
    STDDEV_SAMP(r.daily_return) * SQRT(252)                    AS annualized_volatility,
    (POWER(b.v1 / b.v0, 365.25 / (b.d1 - b.d0)) - 1 - 0.02)
        / (STDDEV_SAMP(r.daily_return) * SQRT(252))            AS sharpe_ratio_rf2pct
FROM rets r CROSS JOIN bounds b
GROUP BY b.v0, b.v1, b.d0, b.d1;
