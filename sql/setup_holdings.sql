/* ============================================================================
   Setup — create and populate the holdings table
   ----------------------------------------------------------------------------
   Run this once in DB Browser (Execute SQL tab), then click "Write Changes"
   to save it into the database file.

   The stock_prices table is NOT created here — it has 11,290 rows and is
   loaded via  File -> Import -> Table from CSV  (stock_prices.csv).
   ============================================================================ */

DROP TABLE IF EXISTS holdings;

CREATE TABLE holdings (
    ticker TEXT    NOT NULL,
    shares INTEGER NOT NULL
);

INSERT INTO holdings (ticker, shares) VALUES
    ('NVDA',  50),
    ('AMZN',  30),
    ('MSFT',  40),
    ('GOOGL', 35),
    ('TSLA',  45),
    ('AAPL',  60),
    ('TSM',   55),
    ('MU',    40),
    ('HOOD',  80),
    ('SPY',  100);

-- Quick check (should return 10 rows):
SELECT ticker, shares FROM holdings ORDER BY ticker;
