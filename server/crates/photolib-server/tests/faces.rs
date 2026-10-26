//! The `faces` job (ADR-0389, design 09 §7): an uploaded portrait is ingested and rendered, the sweep queues it only for
//! an account that agreed, the sandboxed renderer's pixels go through YuNet and SFace on ONNX Runtime, and the faces
//! land in `faces` with a scan; for an account that did not agree, nothing is queued, rendered, run or kept; and
//! withdrawing deletes what was found.
#![allow(clippy::cast_precision_loss, reason = "pixel counts of a portrait, far below 2^24")]

mod common;

use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{Timing, Worker as JobWorker};
use photolib_ml::{MEMORY, Pool, rss, self_test};
use photolib_server::{
    external::Libraries,
    faces::{self, FACES, FaceJob, NOTICE_VERSION, SWEEP, Sweep},
    ingest::{self, INGEST, Ingest},
    ml::Models,
    render::{self, RENDER, Render},
    video::Ffmpeg,
};
use photolib_storage::{
    Hash,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const PHOTOLIBD: &str = env!("CARGO_BIN_EXE_photolibd");

/// A store `local` in a work directory.
async fn instance(db: &testpg::TestDb) -> (Arc<Journal>, tempfile::TempDir) {
    let work = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    for dir in ["data", "uploads"] {
        std::fs::create_dir(work.path().join(dir)).unwrap();
    }
    let local = FsStore::open(&work.path().join("data"), Duration::from_secs(30))
        .await
        .unwrap();
    let candidate = Candidate {
        name: "local".into(),
        store: Arc::new(local),
        adopt: true,
    };
    let stores = Stores::check(&db.pool, Uuid::now_v7(), vec![candidate]).await;
    (Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap()), work)
}

/// An account with a managed library.
async fn account(db: &testpg::TestDb, handle: &str) -> (Uuid, Uuid) {
    let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, $2, $2)")
        .bind(owner)
        .bind(handle)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES ($1, $2, 'Photos', 'managed', $3)")
        .bind(library)
        .bind(owner)
        .bind(format!("p-{handle}"))
        .execute(&db.pool)
        .await
        .unwrap();
    (owner, library)
}

/// A complete upload of `data` as `path`, stored and no longer staged, with its ingest queued.
async fn upload(
    db: &testpg::TestDb,
    journal: &Journal,
    work: &Path,
    (owner, library): (Uuid, Uuid),
    (path, data): (&str, &[u8]),
) {
    let id = Uuid::now_v7();
    let file = work.join("uploads").join(id.to_string());
    std::fs::write(&file, data).unwrap();
    let key = format!("libraries/{library}/uploads/{id}");
    let written = journal.put("local", &key, &file, Hash::of(data)).await.unwrap();
    let mut tx = db.pool.begin().await.unwrap();
    written.switch(&mut tx).await.unwrap();
    sqlx::query(
        "INSERT INTO uploads (id, owner_id, library_id, length, hash, received, store, key, completed_at,
           expires_at, path) VALUES ($1, $2, $3, $4, $5, $4, 'local', $6, now(), now(), $7)",
    )
    .bind(id)
    .bind(owner)
    .bind(library)
    .bind(i64::try_from(data.len()).unwrap())
    .bind(Hash::of(data).0.to_vec())
    .bind(&key)
    .bind(path)
    .execute(&mut *tx)
    .await
    .unwrap();
    ingest::enqueue(&mut tx, &[id]).await.unwrap();
    tx.commit().await.unwrap();
    written.finish().await.unwrap();
    std::fs::remove_file(file).unwrap();
}

/// Runs ingest, rendering, the sweep and the face jobs on the real models until nothing is left to do.
async fn run_jobs(db: &testpg::TestDb, journal: &Arc<Journal>, work: &Path, videos: bool) {
    let (library_file, models_dir, models) = photolib_ml::testing::onnx();
    let ort = photolib_ml::Ort::load(&library_file).unwrap();
    let reports = self_test(ort, models_dir.path(), &models);
    let pool = Models::default();
    pool.set(Pool::new(ort, models_dir.path(), &reports, MEMORY, rss)).ok();
    let photolibd = PathBuf::from(PHOTOLIBD);
    let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
    let ingest = Ingest::new(
        journal.clone(),
        work,
        photolibd.clone(),
        vec![],
        render::profile(&render::specs()),
        libraries.clone(),
    );
    let render = Arc::new(
        Render::new(
            journal.clone(),
            work,
            photolibd.clone(),
            render::specs(),
            libraries.clone(),
        )
        .unwrap(),
    );
    let scratch = Render::new(
        journal.clone(),
        &work.join("faces"),
        photolibd.clone(),
        vec![],
        libraries,
    )
    .unwrap();
    let ffmpeg = videos.then(|| Arc::new(Ffmpeg::new(photolibd.clone(), common::tools(), 1).unwrap()));
    let faces = Arc::new(FaceJob::new(Arc::new(scratch), pool, db.pool.clone(), "sface", ffmpeg).unwrap());
    let embedder = faces.embedder().to_owned();
    let timing = Timing {
        poll_min: Duration::from_millis(10),
        poll_max: Duration::from_millis(50),
        ..Timing::default()
    };
    let shutdown = CancellationToken::new();
    let worker = (JobWorker::new(db.pool.clone(), "test", 2, timing))
        .handle(INGEST, ingest.unwrap())
        .handle(RENDER, render)
        .handle(FACES, faces)
        .handle(
            SWEEP,
            Sweep {
                embedder: embedder.clone(),
                videos,
            },
        );
    let running = tokio::spawn(worker.run(shutdown.clone()));
    // A video's renditions are for the transcoders, which this test has none of.
    let open = "SELECT count(*) FROM jobs WHERE status IN ('queued', 'running') AND type <> 'transcode'";
    // The scheduler would queue the sweep every minute: here after every pass over the open jobs.
    loop {
        while sqlx::query_scalar::<_, i64>(open).fetch_one(&db.pool).await.unwrap() > 0 {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        let mut conn = db.pool.acquire().await.unwrap();
        if faces::sweep(&mut conn, &embedder, videos).await.unwrap() == 0 {
            break;
        }
    }
    shutdown.cancel();
    running.await.unwrap();
    let failed: Vec<String> =
        sqlx::query_scalar("SELECT error FROM jobs WHERE status <> 'done' AND type <> 'transcode'")
            .fetch_all(&db.pool)
            .await
            .unwrap();
    assert!(failed.is_empty(), "{failed:?}");
}

async fn faces_of(db: &testpg::TestDb, owner: Uuid) -> Vec<(Vec<f32>, f32, String, String, i32)> {
    sqlx::query_as(
        "SELECT f.bbox, f.score, f.model_id, f.detector, octet_length(f.embedding) FROM faces f
         JOIN assets a ON a.id = f.asset_id WHERE a.owner_id = $1",
    )
    .bind(owner)
    .fetch_all(&db.pool)
    .await
    .unwrap()
}

async fn count(db: &testpg::TestDb, sql: &str, owner: Uuid) -> i64 {
    sqlx::query_scalar(sql).bind(owner).fetch_one(&db.pool).await.unwrap()
}

fn iou(a: &[f32], b: [f32; 4]) -> f32 {
    let width = (a[0] + a[2]).min(b[0] + b[2]) - a[0].max(b[0]);
    let height = (a[1] + a[3]).min(b[1] + b[3]) - a[1].max(b[1]);
    let both = width.max(0.0) * height.max(0.0);
    both / (a[2].mul_add(a[3], b[2] * b[3]) - both)
}

#[tokio::test]
async fn faces_are_found_only_for_the_account_that_agreed_and_withdrawing_deletes_them() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let (journal, work) = instance(&db).await;
    let (ann, bob) = (account(&db, "ann").await, account(&db, "bob").await);
    let portrait = std::fs::read(photolib_ml::testing::photo("face-photo-armstrong-a")).unwrap();
    for (who, name) in [(ann, "ann"), (bob, "bob")] {
        upload(
            &db,
            &journal,
            work.path(),
            who,
            (&format!("DCIM/{name}.jpg"), &portrait),
        )
        .await;
    }
    // Only Ann agreed to the notice.
    sqlx::query("INSERT INTO face_consents (user_id, notice_version) VALUES ($1, $2)")
        .bind(ann.0)
        .bind(NOTICE_VERSION)
        .execute(&db.pool)
        .await
        .unwrap();
    run_jobs(&db, &journal, work.path(), false).await;

    let found = faces_of(&db, ann.0).await;
    assert_eq!(found.len(), 1, "{found:?}");
    let (bbox, score, model, detector, embedding_bytes) = &found[0];
    // OpenCV's detector finds this face at x 0.2912, y 0.141, 0.4017 × 0.4312 of the picture.
    assert!(iou(bbox, [0.2912, 0.141, 0.4017, 0.4312]) > 0.85, "{bbox:?}");
    assert!(*score > 0.7);
    assert_eq!((model.as_str(), detector.as_str()), ("sface@2021dec", "yunet@2026may"));
    assert_eq!(*embedding_bytes, 256, "128 half floats");
    assert_eq!(
        count(
            &db,
            "SELECT count(*) FROM face_scans s JOIN assets a ON a.id = s.asset_id WHERE a.owner_id = $1",
            ann.0
        )
        .await,
        1
    );

    // Bob never agreed: no job was queued for his photo, nothing was run and nothing is kept.
    assert_eq!(faces_of(&db, bob.0).await.len(), 0);
    let sql = "SELECT count(*) FROM jobs WHERE type = 'faces' AND convert_from(payload, 'UTF8')::jsonb ->> 'asset' IN
               (SELECT id::text FROM assets WHERE owner_id = $1)";
    assert_eq!(count(&db, sql, bob.0).await, 0);
    assert_eq!(
        count(
            &db,
            "SELECT count(*) FROM face_scans s JOIN assets a ON a.id = s.asset_id WHERE a.owner_id = $1",
            bob.0
        )
        .await,
        0
    );
    assert_eq!(count(&db, sql, ann.0).await, 1);

    // Ann withdraws: her faces, scans and jobs go, and the sweep queues nothing for her.
    faces::withdraw(&db.pool, ann.0).await.unwrap();
    assert_eq!(faces_of(&db, ann.0).await.len(), 0);
    assert_eq!(count(&db, sql, ann.0).await, 0);
    run_jobs(&db, &journal, work.path(), false).await;
    assert!(
        faces_of(&db, ann.0).await.is_empty(),
        "not found again without her agreement"
    );

    // Agreeing again finds them again.
    faces::grant(&db.pool, ann.0, NOTICE_VERSION).await.unwrap();
    run_jobs(&db, &journal, work.path(), false).await;
    assert_eq!(faces_of(&db, ann.0).await.len(), 1);
    assert_eq!(faces_of(&db, bob.0).await.len(), 0);
}

#[tokio::test]
async fn the_faces_in_the_keyframes_of_a_video_are_found_with_their_time_and_only_for_an_account_that_agreed() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let (journal, work) = instance(&db).await;
    let (ann, bob) = (account(&db, "ann").await, account(&db, "bob").await);
    // A 7 s clip of the portrait, 5 frames a second.
    let clip = work.path().join("clip.mp4");
    let portrait = photolib_ml::testing::photo("face-photo-armstrong-a");
    common::ffmpeg(
        &common::tools(),
        &[
            "-loop",
            "1",
            "-framerate",
            "5",
            "-i",
            portrait.to_str().unwrap(),
            "-t",
            "7",
            "-vf",
            "scale=480:640",
            "-c:v",
            "mpeg4",
            "-pix_fmt",
            "yuv420p",
            clip.to_str().unwrap(),
        ],
    );
    let video = std::fs::read(&clip).unwrap();
    for (who, name) in [(ann, "ann"), (bob, "bob")] {
        upload(&db, &journal, work.path(), who, (&format!("DCIM/{name}.mp4"), &video)).await;
    }
    sqlx::query("INSERT INTO face_consents (user_id, notice_version) VALUES ($1, $2)")
        .bind(ann.0)
        .bind(NOTICE_VERSION)
        .execute(&db.pool)
        .await
        .unwrap();
    run_jobs(&db, &journal, work.path(), true).await;

    let times: Vec<(i32,)> = sqlx::query_as(
        "SELECT f.time_ms FROM faces f JOIN assets a ON a.id = f.asset_id WHERE a.owner_id = $1 ORDER BY 1",
    )
    .bind(ann.0)
    .fetch_all(&db.pool)
    .await
    .unwrap();
    // Two seconds apart over 7 s: the frames at 0, 2, 4 and 6 s, each with the face.
    let times: Vec<i32> = times.into_iter().map(|t| t.0).collect();
    assert_eq!(times, [0, 2000, 4000, 6000]);
    let found = faces_of(&db, ann.0).await;
    for (bbox, score, ..) in &found {
        assert!(iou(bbox, [0.2912, 0.141, 0.4017, 0.4312]) > 0.8, "{bbox:?}");
        assert!(*score > 0.7);
    }
    assert_eq!(faces_of(&db, bob.0).await.len(), 0, "Bob never agreed");
    let bobs = "SELECT count(*) FROM jobs WHERE type = 'faces' AND convert_from(payload, 'UTF8')::jsonb ->> 'asset' IN
                (SELECT id::text FROM assets WHERE owner_id = $1)";
    assert_eq!(count(&db, bobs, bob.0).await, 0);
}
