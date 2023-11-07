-- Your SQL goes here
CREATE FUNCTION api.average_execution_price(api.limit_orders)
RETURNS numeric AS $$
    SELECT
        SUM(size * price) / SUM(size) AS average_execution_price
    FROM
        fill_events
    WHERE
        maker_address = emit_address
    AND
        fill_events.market_id = $1.market_id
    AND (
            fill_events.maker_order_id = $1.order_id
        OR
            fill_events.taker_order_id = $1.order_id
    )
$$ LANGUAGE SQL;


CREATE FUNCTION api.average_execution_price(api.market_orders)
RETURNS numeric AS $$
    SELECT
        SUM(size * price) / SUM(size) AS average_execution_price
    FROM
        fill_events
    WHERE
        maker_address = emit_address
    AND
        fill_events.market_id = $1.market_id
    AND (
            fill_events.maker_order_id = $1.order_id
        OR
            fill_events.taker_order_id = $1.order_id
    )
$$ LANGUAGE SQL;


CREATE FUNCTION api.average_execution_price(api.swap_orders)
RETURNS numeric AS $$
    SELECT
        SUM(size * price) / SUM(size) AS average_execution_price
    FROM
        fill_events
    WHERE
        maker_address = emit_address
    AND
        fill_events.market_id = $1.market_id
    AND (
            fill_events.maker_order_id = $1.order_id
        OR
            fill_events.taker_order_id = $1.order_id
    )
$$ LANGUAGE SQL;
