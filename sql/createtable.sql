-- Create a table for number of holdings per stock
CREATE TABLE holdings (
    ticker TEXT    NOT NULL,
    shares INTEGER NOT NULL
);
-- Insert shares of every stock
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

SELECT ticker, shares FROM holdings ORDER BY ticker;