use std::time::Duration;

use async_trait::async_trait;
use uuid::Uuid;

pub type DbError = Box<dyn std::error::Error + Send + Sync>;

/// What `photolibd` needs from PostgreSQL: liveness, the instance-id marker and the upkeep of change capture.
#[async_trait]
pub trait Database: Send + Sync {
    async fn ping(&self) -> Result<(), DbError>;

    /// The instance id stored in the database, or `None` for a database that was never initialised.
    async fn instance_id(&self) -> Result<Option<Uuid>, DbError>;

    /// Stores `id` unless the database already has one; `false` means another process stored its own first.
    async fn init_instance_id(&self, id: Uuid) -> Result<bool, DbError>;

    /// The data migrations that are not done yet, one line each.
    async fn upgrading(&self) -> Result<Vec<String>, DbError>;

    /// What `/metrics` reports from the database.
    async fn stats(&self) -> Result<DbStats, DbError>;

    /// The sync watermark and one past the newest ended transaction.
    async fn watermark(&self) -> Result<(u64, u64), DbError>;

    /// Deletes the tombstones older than `retention`; returns how many.
    async fn purge_tombstones(&self, retention: Duration) -> Result<u64, DbError>;

    /// Forgets the mutations processed longer than `retention` ago; returns how many.
    async fn purge_mutations(&self, retention: Duration) -> Result<u64, DbError>;
}

#[derive(Clone, Debug, Default)]
pub struct DbStats {
    /// The queued, running and dead jobs, by type and status.
    pub jobs: Vec<JobStats>,
    /// The open integrity findings by kind, every kind included.
    pub findings: Vec<(String, i64)>,
    /// When each store's scrub last went through all its files, in Unix seconds.
    pub scrubs: Vec<(String, f64)>,
    /// The devices that report their backup.
    pub devices: Vec<DeviceStats>,
    /// When the newest backup that worked ended, in Unix time.
    pub last_backup: Option<f64>,
    /// When the newest restore drill that passed ended, in Unix time.
    pub last_verified_restore: Option<f64>,
}

/// A device's backup as `/metrics` reports it.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceStats {
    /// Its id, which labels its series.
    pub id: String,
    /// What its owner calls it.
    pub name: String,
    /// Its account's handle.
    pub user: String,
    /// Its last request, in Unix seconds; 0 without one.
    pub last_seen: f64,
    /// What it had left to back up at its last report.
    pub pending: i64,
    /// It has not reported for longer than the settings' `backup_silent_hours`.
    pub silent: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct JobStats {
    pub kind: String,
    pub status: String,
    pub count: i64,
    /// Seconds since the oldest of these jobs was created.
    pub oldest_secs: f64,
}
