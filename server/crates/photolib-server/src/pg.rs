use std::time::Duration;

use async_trait::async_trait;
use sqlx::{PgPool, postgres::PgPoolOptions};
use uuid::Uuid;

use crate::db::{Database, DbError, DbStats, DeviceStats, JobStats};

/// Serialises concurrent first starts so that exactly one of them creates the marker table and row.
const INIT_LOCK: i64 = 0x7068_6f74_6f6c_6962;

/// Every type with open or dead jobs gets all three counts, zeros included, so that its first dead job is growth.
const JOB_STATS: &str = "WITH open AS (SELECT type, status, count(*) AS count, min(created_at) AS oldest FROM jobs
        WHERE status IN ('queued', 'running', 'dead') GROUP BY type, status)
    SELECT type, status, coalesce(count, 0), coalesce(extract(epoch FROM now() - oldest), 0)::float8
    FROM (SELECT DISTINCT type FROM open) AS types CROSS JOIN unnest(ARRAY['queued', 'running', 'dead']) AS status
    LEFT JOIN open USING (type, status) ORDER BY type, status";
const FINDING_STATS: &str =
    "SELECT k.kind, count(i.id) FROM unnest(ARRAY['content', 'missing', 'size', 'hash', 'orphan'])
    AS k (kind) LEFT JOIN integrity_findings i ON i.kind = k.kind AND i.resolved_at IS NULL GROUP BY 1 ORDER BY 1";
const SCRUB_STATS: &str = "SELECT store, extract(EPOCH FROM cycle_ended_at)::float8 FROM scrubs
    WHERE cycle_ended_at IS NOT NULL ORDER BY store";
const DEVICE_STATS: &str =
    "SELECT d.id::text, d.name, u.handle, coalesce(extract(EPOCH FROM d.last_seen_at), 0)::float8,
      b.pending, b.reported_at < now() - make_interval(hours => i.backup_silent_hours)
    FROM device_backups b JOIN devices d ON d.id = b.device_id JOIN users u ON u.id = d.user_id
    CROSS JOIN instance_settings i ORDER BY d.id";

const BACKUP_STATS: &str = "SELECT extract(EPOCH FROM max(finished_at) FILTER (WHERE kind = 'backup'))::float8,
      extract(EPOCH FROM max(finished_at) FILTER (WHERE kind = 'drill'))::float8
    FROM backup_runs WHERE ok";

/// PostgreSQL behind the [`Database`] port. The marker table is created only by an initialising start; the
/// baseline migration takes it over.
pub struct PgDatabase {
    pool: PgPool,
}

impl PgDatabase {
    /// `jobs` is how many jobs this process runs at once, each in a transaction of its own.
    pub async fn connect(url: &str, jobs: usize) -> Result<PgDatabase, DbError> {
        let pool = PgPoolOptions::new()
            .max_connections(5 + jobs as u32)
            .acquire_timeout(Duration::from_secs(5))
            .connect(url)
            .await?;
        Ok(PgDatabase { pool })
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

#[async_trait]
impl Database for PgDatabase {
    async fn ping(&self) -> Result<(), DbError> {
        sqlx::query("SELECT 1").execute(&self.pool).await?;
        Ok(())
    }

    async fn instance_id(&self) -> Result<Option<Uuid>, DbError> {
        let exists: bool = sqlx::query_scalar("SELECT to_regclass('photolib_instance') IS NOT NULL")
            .fetch_one(&self.pool)
            .await?;
        if !exists {
            return Ok(None);
        }
        let id: Option<String> = sqlx::query_scalar("SELECT instance_id::text FROM photolib_instance")
            .fetch_optional(&self.pool)
            .await?;
        Ok(id.map(|id| Uuid::parse_str(&id)).transpose()?)
    }

    async fn init_instance_id(&self, id: Uuid) -> Result<bool, DbError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT pg_advisory_xact_lock($1)")
            .bind(INIT_LOCK)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS photolib_instance (
                singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
                instance_id uuid NOT NULL,
                created_at timestamptz NOT NULL DEFAULT now())",
        )
        .execute(&mut *tx)
        .await?;
        let inserted =
            sqlx::query("INSERT INTO photolib_instance (instance_id) VALUES ($1::text::uuid) ON CONFLICT DO NOTHING")
                .bind(id.to_string())
                .execute(&mut *tx)
                .await?
                .rows_affected();
        tx.commit().await?;
        Ok(inserted == 1)
    }

    async fn upgrading(&self) -> Result<Vec<String>, DbError> {
        Ok(photolib_db::data::unfinished(&self.pool).await?)
    }

    async fn stats(&self) -> Result<DbStats, DbError> {
        let jobs: Vec<(String, String, i64, f64)> = sqlx::query_as(JOB_STATS).fetch_all(&self.pool).await?;
        let devices: Vec<(String, String, String, f64, i64, bool)> =
            sqlx::query_as(DEVICE_STATS).fetch_all(&self.pool).await?;
        let (last_backup, last_verified_restore) = sqlx::query_as(BACKUP_STATS).fetch_one(&self.pool).await?;
        Ok(DbStats {
            last_backup,
            last_verified_restore,
            jobs: jobs
                .into_iter()
                .map(|(kind, status, count, oldest_secs)| JobStats {
                    kind,
                    status,
                    count,
                    oldest_secs,
                })
                .collect(),
            findings: sqlx::query_as(FINDING_STATS).fetch_all(&self.pool).await?,
            scrubs: sqlx::query_as(SCRUB_STATS).fetch_all(&self.pool).await?,
            devices: devices
                .into_iter()
                .map(|(id, name, user, last_seen, pending, silent)| DeviceStats {
                    id,
                    name,
                    user,
                    last_seen,
                    pending,
                    silent,
                })
                .collect(),
        })
    }

    async fn watermark(&self) -> Result<(u64, u64), DbError> {
        Ok(photolib_db::sync::watermark(&self.pool).await?)
    }

    async fn purge_tombstones(&self, retention: Duration) -> Result<u64, DbError> {
        Ok(photolib_db::sync::purge_tombstones(&self.pool, retention).await?)
    }

    async fn purge_mutations(&self, retention: Duration) -> Result<u64, DbError> {
        let purged = sqlx::query("DELETE FROM processed_mutations WHERE processed_at < now() - $1")
            .bind(retention)
            .execute(&self.pool)
            .await?;
        Ok(purged.rows_affected())
    }
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        doctor::drift,
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };

    use super::*;

    #[tokio::test]
    async fn the_instance_marker_lives_in_the_database() {
        let db = PgDatabase::connect(&testpg::database().await.url, 0).await.unwrap();
        db.ping().await.unwrap();
        sqlx::query("DROP TABLE IF EXISTS photolib_instance")
            .execute(&db.pool)
            .await
            .unwrap();
        assert_eq!(db.instance_id().await.unwrap(), None, "reading never creates the table");
        let (first, second) = (Uuid::now_v7(), Uuid::now_v7());
        assert!(db.init_instance_id(first).await.unwrap());
        assert!(!db.init_instance_id(second).await.unwrap(), "the first id wins");
        assert_eq!(db.instance_id().await.unwrap(), Some(first));
        sqlx::query("DROP TABLE photolib_instance")
            .execute(&db.pool)
            .await
            .unwrap();
        let ids = [Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7()];
        let (a, b, c, d) = tokio::join!(
            db.init_instance_id(ids[0]),
            db.init_instance_id(ids[1]),
            db.init_instance_id(ids[2]),
            db.init_instance_id(ids[3])
        );
        let wins = [a, b, c, d].map(|won| won.unwrap());
        assert_eq!(
            wins.iter().filter(|won| **won).count(),
            1,
            "exactly one racer initialises"
        );
        let winner = ids[wins.iter().position(|won| *won).unwrap()];
        assert_eq!(db.instance_id().await.unwrap(), Some(winner));
    }

    #[tokio::test]
    async fn the_baseline_migration_takes_over_the_marker_table_of_a_first_start() {
        let db = PgDatabase::connect(&testpg::database().await.url, 0).await.unwrap();
        assert!(db.init_instance_id(Uuid::now_v7()).await.unwrap());
        let migrations = embedded();
        upgrade(&db.pool, &Upgrade::new(&migrations)).await.unwrap();
        assert_eq!(drift(&db.pool, &migrations).await.unwrap(), Vec::<String>::new());
    }

    async fn migrated() -> PgDatabase {
        let db = PgDatabase::connect(&testpg::database().await.url, 0).await.unwrap();
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db
    }

    #[tokio::test]
    async fn stats_count_the_open_and_dead_jobs_by_type() {
        let db = migrated().await;
        assert_eq!(db.stats().await.unwrap().jobs, []);
        sqlx::query(
            "INSERT INTO jobs (id, type, status, created_at)
             SELECT photolib_uuidv7(), kind, status, now() - make_interval(hours => age)
             FROM (VALUES ('render', 'queued', 1), ('render', 'queued', 2), ('render', 'running', 0),
                          ('embed', 'dead', 3), ('render', 'done', 9), ('embed', 'cancelled', 9))
                  AS job(kind, status, age)",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let stats = db.stats().await.unwrap();
        let jobs: Vec<_> = (stats.jobs.iter())
            .map(|job| {
                (
                    job.kind.as_str(),
                    job.status.as_str(),
                    job.count,
                    // In whole minutes: a loaded machine takes its time between the insert and the scrape.
                    (job.oldest_secs / 60.0).floor(),
                )
            })
            .collect();
        assert_eq!(
            jobs,
            [
                ("embed", "dead", 1, 180.0),
                ("embed", "queued", 0, 0.0),
                ("embed", "running", 0, 0.0),
                ("render", "dead", 0, 0.0),
                ("render", "queued", 2, 120.0),
                ("render", "running", 1, 0.0)
            ],
            "a type with open or dead jobs has all three counts, so that its first dead job is growth"
        );
    }

    #[tokio::test]
    async fn stats_report_open_findings_by_kind_finished_scrubs_and_each_device_backup() {
        let db = migrated().await;
        sqlx::raw_sql(
            "INSERT INTO integrity_findings (id, store, key, kind, detail, resolved_at) VALUES
             (photolib_uuidv7(), 'local', 'a', 'content', '', NULL), (photolib_uuidv7(), 'local', 'b', 'content', '', NULL),
             (photolib_uuidv7(), 'local', 'c', 'orphan', '', NULL), (photolib_uuidv7(), 'local', 'd', 'missing', '', now());
             INSERT INTO scrubs (store, cycle_ended_at) VALUES ('local', 'epoch'::timestamptz + interval '1000 seconds'),
               ('b2', NULL);
             INSERT INTO users (id, handle, display_name) VALUES ('00000001-0000-7000-8000-000000000001', 'ann', 'Ann');
             INSERT INTO devices (id, user_id, name, platform, last_seen_at) VALUES
             ('00000002-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'Pixel', 'android',
              'epoch'::timestamptz + interval '2000 seconds'),
             ('00000002-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', 'Laptop', 'linux', NULL);
             INSERT INTO device_backups (device_id, reported_at, pending) VALUES
             ('00000002-0000-7000-8000-000000000001', now() - interval '49 hours', 12),
             ('00000002-0000-7000-8000-000000000002', now(), 0);",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let stats = db.stats().await.unwrap();
        let findings: Vec<_> = stats.findings.iter().map(|(kind, n)| (kind.as_str(), *n)).collect();
        assert_eq!(
            findings,
            [("content", 2), ("hash", 0), ("missing", 0), ("orphan", 1), ("size", 0)]
        );
        assert_eq!(stats.scrubs, [("local".to_string(), 1000.0)]);
        let device = |id: &str, name: &str, last_seen, pending, silent| DeviceStats {
            id: format!("00000002-0000-7000-8000-00000000000{id}"),
            name: name.into(),
            user: "ann".into(),
            last_seen,
            pending,
            silent,
        };
        assert_eq!(
            stats.devices,
            [
                device("1", "Pixel", 2000.0, 12, true),
                device("2", "Laptop", 0.0, 0, false)
            ]
        );
    }

    #[tokio::test]
    async fn the_job_stats_read_an_index_not_the_whole_table() {
        let db = migrated().await;
        let mut conn = db.pool.acquire().await.unwrap();
        sqlx::query("SET enable_seqscan = off")
            .execute(&mut *conn)
            .await
            .unwrap();
        let plan: Vec<String> = sqlx::query_scalar(&format!("EXPLAIN {JOB_STATS}"))
            .fetch_all(&mut *conn)
            .await
            .unwrap();
        assert!(!plan.join("\n").contains("Seq Scan"), "{plan:#?}");
    }

    #[tokio::test]
    async fn the_change_capture_upkeep_reads_the_watermark_and_purges_tombstones_and_processed_mutations() {
        let db = PgDatabase::connect(&testpg::database().await.url, 0).await.unwrap();
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        sqlx::raw_sql(
            "INSERT INTO users (id, handle, display_name) VALUES (gen_random_uuid(), 'a', 'a'); DELETE FROM users",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let (watermark, ended) = db.watermark().await.unwrap();
        assert!(0 < watermark && watermark <= ended, "{watermark} {ended}");
        assert_eq!(db.purge_tombstones(Duration::from_secs(3600)).await.unwrap(), 0);
        assert_eq!(db.purge_tombstones(Duration::ZERO).await.unwrap(), 1);

        sqlx::raw_sql(
            "INSERT INTO users (id, handle, display_name) VALUES ('00000000-0000-7000-8000-000000000001', 'b', 'b');
             INSERT INTO processed_mutations (user_id, mutation_id, processed_at)
             SELECT '00000000-0000-7000-8000-000000000001', gen_random_uuid(), now() - age
             FROM unnest(ARRAY[interval '0 days', interval '31 days']) AS a (age)",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        assert_eq!(db.purge_mutations(Duration::from_hours(30 * 24)).await.unwrap(), 1);
    }

    #[tokio::test]
    async fn every_running_job_has_a_connection_beside_five_for_the_rest() {
        let test = testpg::database().await;
        let db = PgDatabase::connect(&test.url, 8).await.unwrap();
        assert_eq!(db.pool.options().get_max_connections(), 13);
    }

    #[tokio::test]
    async fn an_unreachable_database_is_an_error_not_a_hang() {
        let error = PgDatabase::connect("postgres://photolib@127.0.0.1:1/photolib", 0)
            .await
            .err()
            .unwrap();
        assert!(!error.to_string().is_empty());
    }
}
