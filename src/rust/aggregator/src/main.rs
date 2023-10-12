use std::{sync::Arc, time::Duration};

use anyhow::Result;
use data::{
    leaderboards::Leaderboards, user_history::UserHistory, Data,
};
use sqlx::PgPool;
use tokio::{sync::Mutex, task::JoinSet};
use tracing_subscriber;

mod data;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();
    tracing::info!("[Aggregator] Started up.");
    dotenvy::dotenv().ok();

    let pool = PgPool::connect(
        std::env::var("DATABASE_URL")
            .expect("DATABASE_URL should be set")
            .as_str(),
    )
    .await?;
    tracing::info!("[Aggregator] Connected to DB.");

    let default_interval = Duration::from_secs(5);

    let mut data: Vec<Arc<Mutex<dyn Data + Send + Sync>>> = vec![];

    data.push(Arc::new(Mutex::new(UserHistory::new(pool.clone()))));

    data.push(Arc::new(Mutex::new(Leaderboards::new(pool.clone()))));

    let mut handles = JoinSet::new();

    for data in data {
        handles.spawn(async move {
            let mut data = data.lock().await;

            tracing::info!(
                "[Aggregator] Starting process & save (historical, {}).",
                data.model_name()
            );
            data.process_and_save_historical_data().await?;
            tracing::info!(
                "[Aggregator] Finished process & save (historical, {}).",
                data.model_name()
            );

            loop {
                let interval = data.poll_interval().unwrap_or(default_interval);

                tokio::time::sleep(interval).await;

                if data.ready() {
                    data.process_and_save().await?;
                } else {
                    tracing::info!("[Aggregator] Data is not ready.");
                }
            }

            #[allow(unreachable_code)]
            Ok::<(), anyhow::Error>(())
        });
    }

    while let Some(res) = handles.join_next().await {
        res??;
    }

    Ok(())
}
