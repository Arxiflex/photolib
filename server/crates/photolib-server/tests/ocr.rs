//! The `ocr` job (design 09 §6): an uploaded picture of text is ingested, its pixels go through the sandboxed
//! renderer to PP-OCRv5 on ONNX Runtime, the text lands in `asset_ocr` and the search finds it.
// Fractions of a picture, compared to a tolerance.
#![allow(clippy::suboptimal_flops)]

use std::{
    path::{Path, PathBuf},
    sync::{Arc, OnceLock},
    time::Duration,
};

use photolib_authz::{Principal, Role};
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{Timing, Worker as JobWorker, reconcile::Profile};
use photolib_ml::{MEMORY, Pool, rss, self_test};
use photolib_server::{
    edits::{FOLLOW, Follow},
    external::Libraries,
    ingest::{self, INGEST, Ingest},
    ocr::{MODEL, OCR, Ocr},
    render::{self, RENDER, Render},
    search,
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

fn testdata(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../testdata/ocr")
        .join(name)
}

/// A store `local` in a work directory, and Ann's library on it.
async fn instance(db: &testpg::TestDb) -> (Arc<Journal>, tempfile::TempDir, Uuid, Uuid) {
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
    let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
    let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(owner)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES ($1, $2, 'Photos', 'managed', 'p')")
        .bind(library)
        .bind(owner)
        .execute(&db.pool)
        .await
        .unwrap();
    (journal, work, owner, library)
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

/// Runs ingest, rendering and OCR on the models of `photolib_ml::testing::ocr` until no job is left.
async fn run_jobs(db: &testpg::TestDb, journal: &Arc<Journal>, work: &Path) {
    let (library_file, models_dir, models) = photolib_ml::testing::ocr();
    let ort = photolib_ml::Ort::load(&library_file).unwrap();
    let reports = self_test(ort, models_dir.path(), &models);
    let pool: Arc<OnceLock<Pool<'static>>> = Arc::default();
    pool.set(Pool::new(ort, models_dir.path(), &reports, MEMORY, rss)).ok();
    let photolibd = PathBuf::from(PHOTOLIBD);
    let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
    let profile = Profile {
        ocr: vec![MODEL.into()],
        ..render::profile(&render::specs())
    };
    let follow = Follow(profile.clone());
    let ingest = Ingest::new(
        journal.clone(),
        work,
        photolibd.clone(),
        vec![],
        profile,
        libraries.clone(),
    );
    let render = Arc::new(Render::new(journal.clone(), work, photolibd, render::specs(), libraries).unwrap());
    let ocr = Ocr::new(render.clone(), pool);
    let timing = Timing {
        poll_min: Duration::from_millis(10),
        poll_max: Duration::from_millis(50),
        ..Timing::default()
    };
    let shutdown = CancellationToken::new();
    let worker = (JobWorker::new(db.pool.clone(), "test", 2, timing))
        .handle(INGEST, ingest.unwrap())
        .handle(RENDER, render)
        .handle(FOLLOW, follow)
        .handle(OCR, ocr);
    let running = tokio::spawn(worker.run(shutdown.clone()));
    let open = "SELECT count(*) FROM jobs WHERE status IN ('queued', 'running')";
    while sqlx::query_scalar::<_, i64>(open).fetch_one(&db.pool).await.unwrap() > 0 {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    shutdown.cancel();
    running.await.unwrap();
    let failed: Vec<String> = sqlx::query_scalar("SELECT error FROM jobs WHERE status <> 'done'")
        .fetch_all(&db.pool)
        .await
        .unwrap();
    assert!(failed.is_empty(), "{failed:?}");
}

#[tokio::test]
async fn pictures_of_latin_cyrillic_and_cjk_text_are_read_stored_and_found() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let (journal, work, owner, library) = instance(&db).await;
    for name in ["latin", "cyrillic", "cjk", "xss"] {
        let data = std::fs::read(testdata(&format!("{name}.png"))).unwrap();
        let path = format!("DCIM/{name}.png");
        upload(&db, &journal, work.path(), (owner, library), (&path, &data)).await;
    }
    run_jobs(&db, &journal, work.path()).await;

    let texts: Vec<(String, String)> = sqlx::query_as(
        "SELECT a.original_filename, o.text FROM asset_ocr o JOIN assets a ON a.id = o.asset_id ORDER BY 1",
    )
    .fetch_all(&db.pool)
    .await
    .unwrap();
    let names: Vec<_> = texts.iter().map(|(name, _)| name.as_str()).collect();
    assert_eq!(names, ["cjk.png", "cyrillic.png", "latin.png", "xss.png"], "{texts:?}");
    for (query, name) in [
        ("estação", "latin"),
        ("КРАСНАЯ", "cyrillic"),
        ("東京", "cjk"),
        ("onerror=alert(1)", "xss"),
    ] {
        let expected: String = sqlx::query_scalar("SELECT id::text FROM assets WHERE original_filename = $1")
            .bind(format!("{name}.png"))
            .fetch_one(&db.pool)
            .await
            .unwrap();
        let hits = search::text(&db.pool, Principal::User(owner, Role::User), query, 10)
            .await
            .unwrap();
        let found: Vec<_> = hits.into_iter().map(|hit| hit.asset_id).collect();
        assert_eq!(found, [expected], "{query}");
    }
    let payload = texts
        .iter()
        .find(|(name, _)| name == "xss.png")
        .map(|(_, text)| text.as_str());
    assert_eq!(
        payload,
        Some("<img src=x onerror=alert(1)>"),
        "stored verbatim as data, never as markup"
    );
}

/// The lines of an asset's text and where they are, by the version they were read in.
async fn lines(db: &testpg::TestDb) -> (String, Vec<(String, [f64; 4])>, Option<Uuid>) {
    let (text, regions, version): (String, Option<String>, Option<Uuid>) =
        sqlx::query_as("SELECT text, regions::text, version_id FROM asset_ocr")
            .fetch_one(&db.pool)
            .await
            .unwrap();
    let regions: Vec<serde_json::Value> = serde_json::from_str(&regions.unwrap_or_else(|| "[]".into())).unwrap();
    let lines = regions
        .iter()
        .map(|r| {
            let at = |k: &str| r[k].as_f64().unwrap();
            (
                r["text"].as_str().unwrap().to_owned(),
                [at("x"), at("y"), at("width"), at("height")],
            )
        })
        .collect();
    (text, lines, version)
}

/// Makes `recipe` a version of the only asset, its current one, and says what changed to the job system as the
/// mutation that does it does.
async fn edit(db: &testpg::TestDb, recipe: &[u8]) -> Uuid {
    let checked = photolib_server::edits::check(recipe, (0, 0)).unwrap();
    let version = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO versions (id, asset_id, parent_id, kind, recipe, recipe_hash)
         SELECT $1, id, current_version_id, 'edit', $2, $3 FROM assets",
    )
    .bind(version)
    .bind(&checked.bytes)
    .bind(&checked.hash)
    .execute(&db.pool)
    .await
    .unwrap();
    switch(db, version).await;
    version
}

async fn switch(db: &testpg::TestDb, version: Uuid) {
    sqlx::query("UPDATE assets SET current_version_id = $1")
        .bind(version)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO jobs (id, type, payload, status, placement, idempotency_key)
         SELECT photolib_uuidv7(), 'follow', convert_to(json_build_object('asset', id)::text, 'UTF8'), 'queued',
                'server', 'follow:' || id || ':' || $1::text FROM assets",
    )
    .bind(version)
    .execute(&db.pool)
    .await
    .unwrap();
}

fn recipe_of(operations: Vec<photolib_kernel::proto::model::v1::Operation>) -> Vec<u8> {
    use prost::Message;
    photolib_kernel::proto::model::v1::EditRecipe {
        schema_version: 1,
        operations,
        ..Default::default()
    }
    .encode_to_vec()
}

fn step(
    id: &str,
    kind: photolib_kernel::proto::model::v1::operation::Kind,
) -> photolib_kernel::proto::model::v1::Operation {
    photolib_kernel::proto::model::v1::Operation {
        operation_id: id.into(),
        kind: Some(kind),
        ..Default::default()
    }
}

/// OCR reads the picture of the current version, and says where its lines are in it: cutting a line out of the picture
/// takes it out of the text, turning the picture turns the boxes, and a revert reads the original's lines again.
#[tokio::test]
async fn the_text_and_its_regions_are_those_of_the_edited_picture() {
    use photolib_kernel::proto::model::v1::{CropOperation, operation::Kind};
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let (journal, work, owner, library) = instance(&db).await;
    let data = std::fs::read(testdata("lines.png")).unwrap();
    upload(&db, &journal, work.path(), (owner, library), ("DCIM/lines.png", &data)).await;
    run_jobs(&db, &journal, work.path()).await;
    let (text, whole, version) = lines(&db).await;
    let original: Uuid = sqlx::query_scalar("SELECT current_version_id FROM assets")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    assert_eq!(version, Some(original), "read in the version that was current");
    assert_eq!(whole.len(), 2, "{text:?}");
    // One line above the other: the first in the top half, the second in the bottom one.
    assert!(whole[0].1[1] < 0.5 && whole[1].1[1] > 0.5, "{whole:?}");
    assert!(
        whole.iter().all(|(_, [x, y, w, h])| x + w <= 1.0001 && y + h <= 1.0001),
        "{whole:?}"
    );
    assert!(
        text.to_lowercase().contains("lisboa") && text.contains("Augusta"),
        "{text:?}"
    );

    // The top half of the picture: the second line is gone from the text, and the first fills the picture's height.
    let top = recipe_of(vec![step(
        "crop",
        Kind::Crop(CropOperation {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 0.5,
        }),
    )]);
    let cropped = edit(&db, &top).await;
    run_jobs(&db, &journal, work.path()).await;
    let (text, kept, version) = lines(&db).await;
    assert_eq!(version, Some(cropped));
    assert_eq!(kept.len(), 1, "{kept:?} {text:?}");
    assert!(
        text.to_lowercase().contains("lisboa") && !text.contains("Augusta"),
        "{text:?}"
    );
    // In the cropped frame the line spans about the same width and twice the height of the fractions it had.
    let (before, after) = (whole[0].1, kept[0].1);
    assert!(
        (after[0] - before[0]).abs() < 0.03 && (after[2] - before[2]).abs() < 0.04,
        "{before:?} {after:?}"
    );
    assert!(
        (after[1] - 2.0 * before[1]).abs() < 0.08 && (after[3] - 2.0 * before[3]).abs() < 0.12,
        "{before:?} {after:?}"
    );

    // A revert reads the first version again, and gets the lines it had.
    switch(&db, original).await;
    run_jobs(&db, &journal, work.path()).await;
    let (text, again, version) = lines(&db).await;
    assert_eq!(version, Some(original));
    assert_eq!(again, whole, "{text:?}");

    // The bottom half: the other line is gone and the one left is where the half puts it, its top at the fraction of
    // the half that it was below the middle.
    let bottom = recipe_of(vec![step(
        "crop",
        Kind::Crop(CropOperation {
            x: 0.0,
            y: 0.5,
            width: 1.0,
            height: 0.5,
        }),
    )]);
    edit(&db, &bottom).await;
    run_jobs(&db, &journal, work.path()).await;
    let (text, lower, _) = lines(&db).await;
    assert_eq!(lower.len(), 1, "{lower:?} {text:?}");
    assert!(
        text.contains("Augusta") && !text.to_lowercase().contains("lisboa"),
        "{text:?}"
    );
    assert!(
        (lower[0].1[1] - 2.0 * (whole[1].1[1] - 0.5)).abs() < 0.08,
        "{:?} {:?}",
        whole[1],
        lower[0]
    );
}
