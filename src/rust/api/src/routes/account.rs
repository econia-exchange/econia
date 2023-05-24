use axum::{
    extract::{Path, State},
    Json,
};
use types::error::TypeError;

use crate::{error::ApiError, util::check_addr, AppState};

pub async fn order_history_by_account(
    Path(account_address): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Vec<types::order::Order>>, ApiError> {
    check_addr(&account_address)?;

    let order_history_query = sqlx::query_as!(
        db::models::order::Order,
        r#"
        select
            market_order_id,
            market_id,
            side as "side: db::models::order::Side",
            size,
            price,
            user_address,
            custodian_id,
            order_state as "order_state: db::models::order::OrderState",
            created_at
        from orders where user_address = $1 order by created_at;
        "#,
        account_address
    )
    .fetch_all(&state.pool)
    .await?;

    if order_history_query.is_empty() {
        return Err(ApiError::NotFound);
    }

    let order_history = order_history_query
        .into_iter()
        .map(|v| v.try_into())
        .collect::<Result<Vec<types::order::Order>, TypeError>>()?;

    Ok(Json(order_history))
}

pub async fn open_orders_by_account(
    Path(account_address): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<Vec<types::order::Order>>, ApiError> {
    check_addr(&account_address)?;

    let open_orders_query = sqlx::query_as!(
        db::models::order::Order,
        r#"
        select
            market_order_id,
            market_id,
            side as "side: db::models::order::Side",
            size,
            price,
            user_address,
            custodian_id,
            order_state as "order_state: db::models::order::OrderState",
            created_at
        from orders where user_address = $1 and order_state = 'open'
        order by created_at;
        "#,
        account_address
    )
    .fetch_all(&state.pool)
    .await?;

    if open_orders_query.is_empty() {
        return Err(ApiError::NotFound);
    }

    let open_orders = open_orders_query
        .into_iter()
        .map(|v| v.try_into())
        .collect::<Result<Vec<types::order::Order>, TypeError>>()?;

    Ok(Json(open_orders))
}

#[cfg(test)]
mod tests {
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;

    use crate::{load_config, tests::make_test_server};

    /// Test that the order history by account endpoint returns order history
    /// for the specified user.
    ///
    /// This test sends a GET request to the `/accounts/{account_id}/order-history`
    /// endpoint with the `account_id` parameter set to `0x123`. The response is
    /// then checked to ensure that it has a `200 OK` status code, and the
    /// response body is checked to ensure that it is a JSON response in the
    /// correct format.
    #[tokio::test]
    async fn test_order_history_by_account() {
        let account_id = "0x123";
        let config = load_config();
        let app = make_test_server(config).await;

        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/account/{}/order-history", account_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let res = serde_json::from_slice::<Vec<types::order::Order>>(&body);
        assert!(res.is_ok());
    }

    /// Test that the order history by account endpoint returns a `400 Bad Request`
    /// error when an invalid account address is sent.
    ///
    /// This test sends a GET request to the `/accounts/{account_id}/order-history`
    /// endpoint with the `account_id` parameter set to `hello`. The response is
    /// checked to ensure that it has a `400 Bad Request` status code.
    #[tokio::test]
    async fn test_order_history_for_invalid_address() {
        let account_id = "hello";
        let config = load_config();
        let app = make_test_server(config).await;

        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/account/{}/order-history", account_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    /// Test that the open orders by account endpoint returns open orders
    /// for the specified user.
    ///
    /// This test sends a GET request to the `/accounts/{account_id}/open-orders`
    /// endpoint with the `account_id` parameter set to `0x123`. The response is
    /// then checked to ensure that it has a `200 OK` status code, and the
    /// response body is checked to ensure that it is a JSON response in the
    /// correct format.
    #[tokio::test]
    async fn test_open_orders_by_account() {
        let account_id = "0x123";
        let config = load_config();
        let app = make_test_server(config).await;

        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/account/{}/open-orders", account_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
        let res = serde_json::from_slice::<Vec<types::order::Order>>(&body);
        assert!(res.is_ok());
    }

    /// Test that the open orders by account endpoint returns a `400 Bad Request`
    /// error when an invalid account address is sent.
    ///
    /// This test sends a GET request to the `/accounts/{account_id}/open-orders`
    /// endpoint with the `account_id` parameter set to `hello`. The response is
    /// checked to ensure that it has a `400 Bad Request` status code.
    #[tokio::test]
    async fn test_open_orders_for_invalid_address() {
        let account_id = "hello";

        let config = load_config();
        let app = make_test_server(config).await;

        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/account/{}/open-orders", account_id))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
}
