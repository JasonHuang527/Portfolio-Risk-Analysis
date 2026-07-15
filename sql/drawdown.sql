
-- Join the holdings and stock_prices TABLE, get PortfolioValue, group by everyday
WITH daily_value AS (
	SELECT p.Date AS date,
		SUM(h.shares * p.Close) AS PortfolioValue
	FROM stock_prices p
	JOIN holdings h ON h.ticker = p.Ticker
	WHERE h.ticker <> 'SPY'          -- portfolio = 9 tech picks; SPY is benchmark only
	GROUP BY p.Date
)
-- Get drawdown from running peak
SELECT date, PortfolioValue,
	MAX(PortfolioValue) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningPeak,
	PortfolioValue *1.0 / MAX(PortfolioValue) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - 1 AS Drawdown
	FROM daily_value
	ORDER BY date;