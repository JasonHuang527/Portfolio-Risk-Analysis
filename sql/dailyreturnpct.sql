-- Get Daily Portfolio Value
WITH daily_value AS (
    SELECT p.Date AS date,
           SUM(h.shares * p.Close) AS PortfolioValue
    FROM   stock_prices p
    JOIN   holdings h ON h.ticker = p.Ticker
    WHERE  h.ticker <> 'SPY'          -- portfolio = 9 tech picks; SPY is benchmark only
    GROUP  BY p.Date
)

-- Get yesterday value as previous value and daily return percentage
SELECT date,
       PortfolioValue,
       LAG(PortfolioValue) OVER (ORDER BY date) AS PrevValue,
       ROUND((PortfolioValue * 1.0 / LAG(PortfolioValue) OVER (ORDER BY date) - 1) * 100, 2) AS DailyReturnPct
FROM   daily_value          --
ORDER  BY date;