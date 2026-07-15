/* ============================================================================
   02 — Daily returns & drawdown series   (the core window-function query)
   ----------------------------------------------------------------------------
   Turns raw daily prices into: portfolio value, daily return %, and the
   drawdown-from-peak series.

   Requires: holdings table (01_setup_holdings.sql) + stock_prices (CSV import).

   Portfolio value on a day = SUM(shares * Close) across the holdings.
     - PORTFOLIO : all holdings         -> default (no filter)
     - BENCHMARK : S&P 500 only         -> uncomment  WHERE h.ticker = 'SPY'

   Window functions used:
     LAG()  -> previous day's value  (for the daily return)
     MAX() OVER (... ROWS UNBOUNDED PRECEDING) -> running peak (for drawdown)
   ============================================================================ */

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
