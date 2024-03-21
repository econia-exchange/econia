-- Your SQL goes here
ALTER TABLE aggregator.liquidity_groups
ADD CONSTRAINT liquidity_groups_unique UNIQUE(group_id,name);


CREATE VIEW api.liquidity AS SELECT * FROM aggregator.liquidity;


CREATE VIEW api.liquidity_groups AS SELECT * FROM aggregator.liquidity_groups;


CREATE OR REPLACE FUNCTION api.get_market_best_ask_price (market_id numeric) RETURNS NUMERIC AS $$
    SELECT min_ask
    FROM aggregator.spreads
    WHERE market_id = $1
    ORDER BY "time" DESC
    LIMIT 1
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION api.get_market_best_bid_price (market_id numeric) RETURNS NUMERIC AS $$
    SELECT max_bid
    FROM aggregator.spreads
    WHERE market_id = $1
    ORDER BY "time" DESC
    LIMIT 1
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION api.get_market_liquidity (market_id numeric, depth numeric) RETURNS NUMERIC AS $$
    SELECT (amount_ask_lots + amount_bid_lots) / (SELECT tick_size FROM market_registration_events WHERE market_id = $1)
    FROM aggregator.liquidity
    WHERE group_id = (
        SELECT group_id FROM aggregator.liquidity_groups WHERE name = 'all' AND market_id = $1
    )
    AND bps_times_ten = $2 * 10
    ORDER BY "time" DESC
    LIMIT 1;
$$ LANGUAGE SQL;
