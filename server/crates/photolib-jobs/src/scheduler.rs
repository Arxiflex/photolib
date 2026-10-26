//! The scheduler role's work: cron schedules, the jobs of ended processing grants, and the derivatives reconciler.

use std::{error::Error, time::Instant};

use sqlx::PgPool;
use tokio_util::sync::CancellationToken;

use crate::{
    NewJob, Timing,
    cron::Cron,
    enqueue,
    reconcile::{Profile, reconcile},
};

/// Ticks every `timing.tick` and reconciles `profile` at start and every `timing.reconcile`, until `shutdown`.
pub async fn run(pool: PgPool, profile: Profile, timing: Timing, shutdown: CancellationToken) {
    let mut reconciled: Option<Instant> = None;
    loop {
        if let Err(error) = tick(&pool).await {
            tracing::warn!(%error, "the scheduler cannot queue its schedules");
        }
        if reconciled.is_none_or(|at| at.elapsed() >= timing.reconcile) {
            match reconcile(&pool, &profile).await {
                Ok(queued) => {
                    tracing::info!(queued, "reconciled the derivatives");
                    reconciled = Some(Instant::now());
                }
                Err(error) => tracing::warn!(%error, "cannot reconcile the derivatives"),
            }
        }
        tokio::select! {
            () = shutdown.cancelled() => return,
            () = tokio::time::sleep(timing.tick) => {}
        }
    }
}

/// Registers or updates the schedule `name`, which queues a `kind` job with `payload` at each time `cron` matches.
/// An unchanged expression keeps its next run.
pub async fn schedule(
    pool: &PgPool,
    name: &str,
    cron: &str,
    kind: &str,
    payload: &[u8],
) -> Result<(), Box<dyn Error + Send + Sync>> {
    let now: i64 = sqlx::query_scalar("SELECT extract(epoch FROM now())::int8")
        .fetch_one(pool)
        .await?;
    let next = (cron.parse::<Cron>()?)
        .next_after(now)
        .ok_or_else(|| format!("'{cron}' never runs"))?;
    sqlx::query(
        "INSERT INTO job_schedules (name, cron, type, payload, next_run) VALUES ($1, $2, $3, $4, to_timestamp($5))
         ON CONFLICT (name) DO UPDATE SET cron = excluded.cron, type = excluded.type, payload = excluded.payload,
           next_run = CASE WHEN job_schedules.cron = excluded.cron THEN job_schedules.next_run
             ELSE excluded.next_run END",
    )
    .bind(name)
    .bind(cron)
    .bind(kind)
    .bind(payload)
    .bind(next as f64)
    .execute(pool)
    .await?;
    Ok(())
}

/// Queues the due occurrence of each schedule, once whatever the number of schedulers, and cancels the jobs of
/// revoked or expired processing grants. Returns the number of schedules that ran.
pub async fn tick(pool: &PgPool) -> sqlx::Result<u64> {
    sqlx::query(
        "UPDATE jobs SET status = 'cancelled', error = 'the processing grant ended', lease_owner = NULL,
           lease_until = NULL
         WHERE status IN ('queued', 'running') AND grant_id IN
           (SELECT id FROM processing_grants WHERE revoked_at IS NOT NULL OR expires_at <= now())",
    )
    .execute(pool)
    .await?;
    let mut tx = pool.begin().await?;
    let due: Vec<(String, String, String, Vec<u8>, i64, i64)> = sqlx::query_as(
        "SELECT name, cron, type, coalesce(payload, ''), extract(epoch FROM next_run)::int8, extract(epoch FROM now())::int8
         FROM job_schedules WHERE next_run <= now() FOR UPDATE SKIP LOCKED",
    )
    .fetch_all(&mut *tx)
    .await?;
    for (name, cron, kind, payload, at, now) in &due {
        // The key makes an occurrence run once, even if two schedulers saw it.
        let key = format!("cron:{name}:{at}");
        let job = NewJob {
            key: Some(&key),
            ..NewJob::new(kind, payload)
        };
        enqueue(&mut tx, &job).await?;
        let next = cron.parse::<Cron>().ok().and_then(|cron| cron.next_after(*now));
        sqlx::query("UPDATE job_schedules SET next_run = coalesce(to_timestamp($2), 'infinity') WHERE name = $1")
            .bind(name)
            .bind(next.map(|next| next as f64))
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(due.len() as u64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{asset, database, exec, fast, grant, library};

    async fn next_run(pool: &PgPool) -> i64 {
        sqlx::query_scalar("SELECT extract(epoch FROM next_run)::int8 FROM job_schedules")
            .fetch_one(pool)
            .await
            .unwrap()
    }

    async fn jobs(pool: &PgPool) -> Vec<(String, String, Vec<u8>)> {
        sqlx::query_as("SELECT type, idempotency_key, payload FROM jobs ORDER BY id")
            .fetch_all(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn a_due_schedule_queues_one_job_however_many_schedulers_and_missed_runs() {
        let pool = database().await;
        schedule(&pool, "nightly", "0 3 * * *", "backup", b"full")
            .await
            .unwrap();
        let first: i64 = next_run(&pool).await;
        let now: i64 = sqlx::query_scalar("SELECT extract(epoch FROM now())::int8")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert!(first > now && first <= now + 86_400 && first % 86_400 == 3 * 3600);
        sqlx::query("UPDATE job_schedules SET next_run = next_run - interval '3 days'")
            .execute(&pool)
            .await
            .unwrap();
        let (a, b) = tokio::join!(tick(&pool), tick(&pool));
        assert_eq!(a.unwrap() + b.unwrap(), 1);
        let key = format!("cron:nightly:{}", first - 3 * 86_400);
        assert_eq!(jobs(&pool).await, [("backup".into(), key, b"full".to_vec())]);
        assert_eq!(next_run(&pool).await, first, "missed runs are skipped");
        assert_eq!(tick(&pool).await.unwrap(), 0);
        assert_eq!(jobs(&pool).await.len(), 1);
    }

    #[tokio::test]
    async fn scheduling_again_keeps_the_next_run_unless_the_expression_changes() {
        let pool = database().await;
        schedule(&pool, "scrub", "0 4 * * *", "scrub", b"").await.unwrap();
        sqlx::query("UPDATE job_schedules SET next_run = next_run + interval '1 day'")
            .execute(&pool)
            .await
            .unwrap();
        let later = next_run(&pool).await;
        schedule(&pool, "scrub", "0 4 * * *", "scrub", b"").await.unwrap();
        assert_eq!(next_run(&pool).await, later);
        schedule(&pool, "scrub", "30 4 * * *", "scrub", b"").await.unwrap();
        assert_eq!(next_run(&pool).await % 86_400, 4 * 3600 + 1800);
        for (cron, problem) in [("0 4 * *", "five fields"), ("0 0 30 2 *", "never")] {
            let error = schedule(&pool, "bad", cron, "scrub", b"").await.unwrap_err();
            assert!(error.to_string().contains(problem), "{error}");
        }
    }

    #[tokio::test]
    async fn the_jobs_of_revoked_or_expired_grants_are_cancelled() {
        let pool = database().await;
        for (ended, status) in [
            ("revoked_at = now()", "queued"),
            ("expires_at = now()", "running"),
            ("expires_at = now() + interval '1 hour'", "running"),
        ] {
            let grant = grant(&pool).await;
            exec(
                &pool,
                &format!("UPDATE processing_grants SET {ended} WHERE id = $1"),
                grant,
            )
            .await;
            let job = format!(
                "INSERT INTO jobs (id, type, status, grant_id) VALUES (photolib_uuidv7(), 'thumb', '{status}', $1)"
            );
            exec(&pool, &job, grant).await;
        }
        tick(&pool).await.unwrap();
        let statuses: Vec<(String, Option<String>)> = sqlx::query_as("SELECT status, error FROM jobs ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
        let ended = || ("cancelled".to_string(), Some("the processing grant ended".to_string()));
        assert_eq!(statuses, [ended(), ended(), ("running".into(), None)]);
    }

    #[tokio::test]
    async fn the_scheduler_runs_due_schedules_and_reconciles_until_shutdown() {
        let pool = database().await;
        asset(&pool, library(&pool, "standard").await, "image").await;
        schedule(&pool, "often", "* * * * *", "probe", b"").await.unwrap();
        sqlx::query("UPDATE job_schedules SET next_run = now() + interval '200 milliseconds'")
            .execute(&pool)
            .await
            .unwrap();
        let profile = Profile {
            models: vec!["clip@1".into()],
            ocr: vec![],
            ..Profile::default()
        };
        let shutdown = CancellationToken::new();
        let running = tokio::spawn(run(pool.clone(), profile, fast(), shutdown.clone()));
        let started = photolib_spawn::Running::start();
        while jobs(&pool).await.len() < 2 {
            assert!(started.elapsed().as_secs() < 5, "{:?}", jobs(&pool).await);
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        // Either first: the schedule is due 200 ms after it was set, which a loaded or stopped run may outlast.
        let mut kinds: Vec<String> = jobs(&pool).await.into_iter().map(|job| job.0).collect();
        kinds.sort();
        assert_eq!(kinds, ["embed", "probe"]);
        shutdown.cancel();
        running.await.unwrap();
    }
}
