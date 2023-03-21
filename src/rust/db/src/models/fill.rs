use bigdecimal::BigDecimal;
use chrono::{DateTime, Utc};
use diesel::prelude::*;

use super::order::Side;

#[derive(Clone, Debug, Queryable)]
pub struct Fill {
    pub market_id: BigDecimal,
    pub maker_order_id: BigDecimal,
    pub maker: String,
    pub maker_side: Side,
    pub custodian_id: Option<BigDecimal>,
    pub size: BigDecimal,
    pub price: BigDecimal,
    pub time: DateTime<Utc>,
}
