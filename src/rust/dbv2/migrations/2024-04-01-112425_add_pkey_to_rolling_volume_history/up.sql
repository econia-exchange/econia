-- Your SQL goes here
DELETE FROM aggregator.daily_rolling_volume_history;
ALTER TABLE aggregator.daily_rolling_volume_history ADD PRIMARY KEY ("time", market_id);
ALTER TABLE aggregator.spreads ADD PRIMARY KEY ("time", market_id);
