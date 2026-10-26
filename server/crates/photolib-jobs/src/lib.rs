//! The job system on PostgreSQL (ADR-0034): leased jobs, cron schedules and the derivatives reconciler. No other
//! service: `LISTEN/NOTIFY` only wakes idle workers early.

pub mod cron;
pub mod reconcile;
pub mod scheduler;
#[cfg(test)]
mod testing;
mod worker;

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

pub use worker::{Handler, Job, Worker};

/// The channel that carries the id of a newly queued job, a hint to wake idle workers.
const CHANNEL: &str = "photolib_jobs";

/// Who runs a job: the server's workers, the user's device, or a trusted node (photolib-design docs/03 §5).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Placement {
    /// photolibd's workers.
    Server,
    /// A device of the user whose data it is.
    Device,
    /// A trusted node of that user's.
    TrustedNode,
}

impl Placement {
    fn as_str(self) -> &'static str {
        match self {
            Self::Server => "server",
            Self::Device => "device",
            Self::TrustedNode => "trusted_node",
        }
    }
}

/// A job to queue.
pub struct NewJob<'a> {
    /// Its type, which picks the handler.
    pub kind: &'a str,
    /// The handler's input.
    pub payload: &'a [u8],
    /// Higher runs first.
    pub priority: i16,
    /// Who runs it.
    pub placement: Placement,
    /// The processing grant a job on private data runs under; it runs only while the grant is active.
    pub grant: Option<Uuid>,
    /// Enqueueing a key that exists returns the existing job instead.
    pub key: Option<&'a str>,
}

impl<'a> NewJob<'a> {
    /// A job of `kind` with `payload`, at priority 0 on the server, without a grant or a key.
    pub fn new(kind: &'a str, payload: &'a [u8]) -> Self {
        NewJob {
            kind,
            payload,
            priority: 0,
            placement: Placement::Server,
            grant: None,
            key: None,
        }
    }
}

/// How long leases last and how often idle loops look for work.
#[derive(Clone, Copy, Debug)]
pub struct Timing {
    /// A lease the worker does not renew expires after this; another worker then retries the job.
    pub lease: Duration,
    /// The first retry delay; it doubles with each failed attempt.
    pub retry: Duration,
    /// An idle worker polls after `poll_min`, then ever less often up to `poll_max`.
    pub poll_min: Duration,
    /// The longest an idle worker waits between polls.
    pub poll_max: Duration,
    /// The scheduler looks for due cron schedules and ended grants this often.
    pub tick: Duration,
    /// The scheduler reconciles derivatives at start and then this often.
    pub reconcile: Duration,
}

impl Default for Timing {
    fn default() -> Self {
        Self {
            lease: Duration::from_secs(60),
            retry: Duration::from_secs(10),
            poll_min: Duration::from_secs(1),
            poll_max: Duration::from_secs(60),
            tick: Duration::from_secs(60),
            reconcile: Duration::from_hours(24),
        }
    }
}

/// Queues `job` on `conn`, in the caller's transaction if it is one, and returns its id.
pub async fn enqueue(conn: &mut PgConnection, job: &NewJob<'_>) -> sqlx::Result<Uuid> {
    let inserted: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO jobs (id, type, payload, status, priority, placement, grant_id, idempotency_key)
         VALUES ($1, $2, $3, 'queued', $4, $5, $6, $7) ON CONFLICT (idempotency_key) DO NOTHING RETURNING id",
    )
    .bind(Uuid::now_v7())
    .bind(job.kind)
    .bind(job.payload)
    .bind(job.priority)
    .bind(job.placement.as_str())
    .bind(job.grant)
    .bind(job.key)
    .fetch_optional(&mut *conn)
    .await?;
    match inserted {
        Some(id) => {
            notify(&mut *conn, id).await?;
            Ok(id)
        }
        None => {
            sqlx::query_scalar("SELECT id FROM jobs WHERE idempotency_key = $1")
                .bind(job.key)
                .fetch_one(conn)
                .await
        }
    }
}

/// Cancels a queued or running job; a running one stops at its next lease renewal and its writes roll back.
pub async fn cancel(conn: &mut PgConnection, id: Uuid) -> sqlx::Result<bool> {
    let cancelled = sqlx::query(
        "UPDATE jobs SET status = 'cancelled', lease_owner = NULL, lease_until = NULL
         WHERE id = $1 AND status IN ('queued', 'running')",
    )
    .bind(id)
    .execute(conn)
    .await?;
    Ok(cancelled.rows_affected() == 1)
}

/// Queues a dead or cancelled job again from its first attempt.
pub async fn retry(conn: &mut PgConnection, id: Uuid) -> sqlx::Result<bool> {
    let retried = sqlx::query(
        "UPDATE jobs SET status = 'queued', attempts = 0, run_after = now(), error = NULL
         WHERE id = $1 AND status IN ('dead', 'cancelled')",
    )
    .bind(id)
    .execute(&mut *conn)
    .await?
    .rows_affected()
        == 1;
    if retried {
        notify(conn, id).await?;
    }
    Ok(retried)
}

/// How long a pause lasts unless the caller says otherwise (ADR-0063).
pub const DEFAULT_PAUSE: Duration = Duration::from_secs(3600);
/// The types that keep data safe; only an administrator's session may pause them, never an API key.
pub const MAINTENANCE: [&str; 3] = ["backup", "storage-purge", "scrub"];

/// How long one request may pause `kind`: 7 days for maintenance, a day for any other type (ADR-0063).
pub fn max_pause(kind: &str) -> Duration {
    Duration::from_hours(if MAINTENANCE.contains(&kind) { 7 * 24 } else { 24 })
}

/// Stops leasing jobs of `kind` for `length` from now, after which they resume by themselves; returns when.
pub async fn pause(
    conn: &mut PgConnection,
    kind: &str,
    length: Duration,
    by: Option<Uuid>,
) -> sqlx::Result<SystemTime> {
    let until: f64 = sqlx::query_scalar(
        "INSERT INTO job_pauses (type, until, paused_by) VALUES ($1, now() + make_interval(secs => $2), $3)
         ON CONFLICT (type) DO UPDATE SET until = excluded.until, paused_by = excluded.paused_by
         RETURNING extract(epoch FROM until)::float8",
    )
    .bind(kind)
    .bind(length.as_secs_f64())
    .bind(by)
    .fetch_one(conn)
    .await?;
    UNIX_EPOCH
        .checked_add(Duration::from_secs_f64(until))
        .ok_or_else(|| sqlx::Error::Decode("a pause that ends past what SystemTime holds".into()))
}

/// Ends a pause at once; `false` when `kind` was not paused.
pub async fn resume(conn: &mut PgConnection, kind: &str) -> sqlx::Result<bool> {
    let paused: Option<bool> = sqlx::query_scalar("DELETE FROM job_pauses WHERE type = $1 RETURNING until > now()")
        .bind(kind)
        .fetch_optional(&mut *conn)
        .await?;
    if paused == Some(true) {
        notify(conn, Uuid::nil()).await?;
    }
    Ok(paused == Some(true))
}

/// Puts the jobs leased to `owner` back on the queue at once, without counting the attempt: a graceful shutdown.
pub async fn requeue_leased(pool: &PgPool, owner: &str) -> sqlx::Result<u64> {
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "UPDATE jobs SET status = 'queued', attempts = attempts - 1, run_after = now(), lease_owner = NULL,
           lease_until = NULL
         WHERE lease_owner = $1 AND status = 'running' RETURNING id",
    )
    .bind(owner)
    .fetch_all(pool)
    .await?;
    if let Some(id) = ids.first() {
        notify(pool, *id).await?;
    }
    Ok(ids.len() as u64)
}

/// Wakes idle workers; `id` names the job that is new, or nil.
pub async fn notify(conn: impl sqlx::PgExecutor<'_>, id: Uuid) -> sqlx::Result<()> {
    sqlx::query("SELECT pg_notify($1, $2)")
        .bind(CHANNEL)
        .bind(id.to_string())
        .execute(conn)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::database;

    #[tokio::test]
    async fn an_idempotency_key_enqueues_a_job_once() {
        let pool = database().await;
        let keyed = NewJob {
            key: Some("export:42"),
            ..NewJob::new("export", b"{}")
        };
        let mut conn = pool.acquire().await.unwrap();
        let first = enqueue(&mut conn, &keyed).await.unwrap();
        assert_eq!(enqueue(&mut conn, &keyed).await.unwrap(), first);
        let unkeyed = enqueue(&mut conn, &NewJob::new("export", b"{}")).await.unwrap();
        assert_ne!(unkeyed, first);
        let rows: Vec<(Uuid, String, Vec<u8>, String)> =
            sqlx::query_as("SELECT id, type, payload, status FROM jobs ORDER BY id")
                .fetch_all(&pool)
                .await
                .unwrap();
        assert_eq!(
            rows,
            [
                (first, "export".into(), b"{}".to_vec(), "queued".into()),
                (unkeyed, "export".into(), b"{}".to_vec(), "queued".into())
            ]
        );
    }
}
