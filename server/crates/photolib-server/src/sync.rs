//! Sync upkeep, run by the scheduler role: the watermark lag, which `/metrics` exports and a warning reports while it
//! is high, tombstone retention (ADR-0053) and how long processed mutations are remembered (ADR-0265).

use std::{
    collections::VecDeque,
    sync::{Arc, atomic::AtomicU64},
    time::Duration,
};

use prometheus_client::metrics::gauge::Gauge;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

use crate::db::Database;

const SAMPLE_EVERY: Duration = Duration::from_secs(15);
/// Above this, photolibd logs a warning (photolib-design docs/15-reliability-migrations-ops.md §10).
const LAG_ALERT: Duration = Duration::from_secs(300);
/// How long a deletion stays readable (photolib-design docs/05-sync-and-offline.md §8).
const TOMBSTONE_RETENTION: Duration = Duration::from_secs(90 * 86_400);
/// How long a mutation's id stays known, so that a device's retry never applies it twice (design 05 §5).
const MUTATION_RETENTION: Duration = Duration::from_hours(30 * 24);
const PURGE_EVERY: Duration = Duration::from_secs(86_400);

/// How long changes that ended above the watermark have waited for it to pass them. It is measured from samples
/// of the watermark and of one past the newest ended transaction, so it needs no access to other sessions and is
/// exact to within one sample.
#[derive(Default)]
struct Lag(VecDeque<(Instant, u64)>);

impl Lag {
    /// Takes the `(watermark, one past the newest ended transaction)` read at `now`; returns the lag.
    fn observe(&mut self, now: Instant, (watermark, ended): (u64, u64)) -> Duration {
        self.0.push_back((now, ended));
        while self.0.front().is_some_and(|(_, ended)| *ended <= watermark) {
            self.0.pop_front();
        }
        self.0.front().map_or(Duration::ZERO, |(since, _)| now - *since)
    }
}

/// Samples the watermark lag into `gauge` and warns while it exceeds [`LAG_ALERT`]; purges expired tombstones and
/// processed mutations daily.
/// Returns at `shutdown`.
pub async fn maintain(db: Arc<dyn Database>, gauge: Gauge<f64, AtomicU64>, shutdown: CancellationToken) {
    let (mut lag, mut warned, mut purged) = (Lag::default(), false, None::<Instant>);
    let mut ticks = tokio::time::interval(SAMPLE_EVERY);
    loop {
        tokio::select! {
            _ = ticks.tick() => {}
            () = shutdown.cancelled() => return,
        }
        match db.watermark().await {
            Ok(sample) => {
                let now = lag.observe(Instant::now(), sample);
                gauge.set(now.as_secs_f64());
                if (now > LAG_ALERT) != warned {
                    warned = !warned;
                    match warned {
                        true => tracing::warn!(
                            lag_secs = now.as_secs(),
                            "sync is delayed: a transaction holds the watermark back"
                        ),
                        false => tracing::info!("sync caught up with the watermark"),
                    }
                }
            }
            Err(error) => {
                gauge.set(f64::NAN);
                tracing::warn!(%error, "cannot read the sync watermark");
            }
        }
        if purged.is_none_or(|at| at.elapsed() >= PURGE_EVERY) {
            match db.purge_tombstones(TOMBSTONE_RETENTION).await {
                Ok(count) => {
                    purged = Some(Instant::now());
                    tracing::info!(count, "purged expired tombstones");
                }
                Err(error) => tracing::warn!(%error, "cannot purge tombstones"),
            }
            match db.purge_mutations(MUTATION_RETENTION).await {
                Ok(count) => tracing::info!(count, "forgot processed mutations"),
                Err(error) => tracing::warn!(%error, "cannot purge processed mutations"),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use tracing::instrument::WithSubscriber;

    use super::*;
    use crate::testing::{Capture, FakeDb};

    #[test]
    fn the_lag_counts_from_the_first_sample_that_saw_a_transaction_end_above_the_watermark() {
        let start = Instant::now();
        let at = |secs| start + Duration::from_secs(secs);
        let mut lag = Lag::default();
        assert_eq!(lag.observe(at(0), (100, 100)), Duration::ZERO, "nothing ended above it");
        assert_eq!(lag.observe(at(15), (100, 105)), Duration::ZERO);
        assert_eq!(lag.observe(at(30), (100, 110)), Duration::from_secs(15));
        assert_eq!(lag.observe(at(375), (100, 900)), Duration::from_secs(360));
        assert_eq!(
            lag.observe(at(390), (107, 950)),
            Duration::from_secs(360),
            "what ended by 15 s is through, what ended by 30 s still waits"
        );
        assert_eq!(lag.observe(at(405), (110, 990)), Duration::from_secs(30));
        assert_eq!(lag.observe(at(420), (990, 991)), Duration::ZERO);
        assert_eq!(lag.observe(at(435), (991, 991)), Duration::ZERO);
    }

    #[tokio::test(start_paused = true)]
    async fn the_lag_is_exported_and_warned_about_past_five_minutes_and_tombstones_and_mutations_expire_daily() {
        let db = Arc::new(FakeDb::default());
        *db.watermark.lock().unwrap() = (100, 105);
        let (shutdown, log, gauge) = (CancellationToken::new(), Capture::default(), Gauge::default());
        let subscriber = tracing_subscriber::fmt().json().with_writer(log.clone()).finish();
        let task = tokio::spawn(maintain(db.clone(), gauge.clone(), shutdown.clone()).with_subscriber(subscriber));
        tokio::time::sleep(Duration::from_secs(290)).await;
        assert!(!log.text().contains("WARN"), "{}", log.text());
        tokio::time::sleep(Duration::from_secs(30)).await;
        let warning = r#""level":"WARN","fields":{"message":"sync is delayed: a transaction holds the watermark back","lag_secs":315}"#;
        assert_eq!(log.text().matches(warning).count(), 1, "{}", log.text());
        assert_eq!(gauge.get(), 315.0, "/metrics exports what the warning reports");

        *db.watermark.lock().unwrap() = (106, 106);
        tokio::time::sleep(Duration::from_secs(15)).await;
        assert!(
            log.text().contains("sync caught up with the watermark"),
            "{}",
            log.text()
        );
        assert_eq!(gauge.get(), 0.0);
        db.set_down(true);
        tokio::time::sleep(Duration::from_secs(15)).await;
        assert!(gauge.get().is_nan(), "a lag it cannot read is unknown, not stale");
        db.set_down(false);
        assert_eq!(*db.purges.lock().unwrap(), [TOMBSTONE_RETENTION, MUTATION_RETENTION]);
        tokio::time::sleep(Duration::from_secs(86_400)).await;
        assert_eq!(db.purges.lock().unwrap().len(), 4);
        shutdown.cancel();
        task.await.unwrap();
    }
}
