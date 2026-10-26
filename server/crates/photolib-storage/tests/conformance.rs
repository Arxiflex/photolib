//! One `BlobStore` conformance suite (ADR-0022 point 7) for the filesystem driver and for Garage.

use std::{
    io::{BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use photolib_storage::{
    BlobStore, Error, Hash, Hook, Local, Meta,
    fs::FsStore,
    s3::{S3Config, S3Store},
    testing,
};

/// Makes the hook fail at the given part of the next multipart write, to abort it half-way.
#[derive(Clone, Default)]
struct FailAt(Arc<Mutex<(Option<usize>, usize)>>);

impl FailAt {
    fn hook(&self) -> Hook {
        let state = self.0.clone();
        Arc::new(move |step| {
            let mut state = state.lock().unwrap();
            if step == "part" {
                state.1 += 1;
                if state.0 == Some(state.1) {
                    return Err(Error::Other("injected failure".into()));
                }
            }
            Ok(())
        })
    }

    fn set(&self, part: Option<usize>) {
        *self.0.lock().unwrap() = (part, 0);
    }
}

fn bytes(n: usize, seed: u8) -> Vec<u8> {
    (0..n).map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed)).collect()
}

async fn put(store: &dyn BlobStore, dir: &Path, key: &str, data: &[u8]) -> Meta {
    let (staged, hash) = testing::staged(dir, data);
    let meta = store.put(key, &staged, hash).await.unwrap();
    assert_eq!(
        meta,
        Meta {
            size: data.len() as u64,
            hash: Some(hash)
        },
        "{key}"
    );
    meta
}

/// `multipart` is a size the store writes in more than two parts.
async fn suite(store: &dyn BlobStore, fail: &FailAt, multipart: usize) {
    let dir = tempfile::tempdir().unwrap();
    let dir = dir.path();
    let photo = bytes(100_000, 1);

    // put, get, head and read-after-write
    assert_eq!(store.head("p/a.jpg").await.unwrap(), None);
    let meta = put(store, dir, "p/a.jpg", &photo).await;
    assert_eq!(store.head("p/a.jpg").await.unwrap(), Some(meta), "object metadata");
    assert_eq!(store.get("p/a.jpg", None).await.unwrap(), photo);
    assert_eq!(store.list("").await.unwrap(), ["p/a.jpg"]);
    put(store, dir, "empty", b"").await;
    assert_eq!(store.get("empty", None).await.unwrap(), b"");

    // keys are never overwritten; a wrong hash or key writes nothing
    let (other, other_hash) = testing::staged(dir, b"other");
    assert!(matches!(
        store.put("p/a.jpg", &other, other_hash).await,
        Err(Error::Exists(_))
    ));
    assert!(matches!(
        store.put("p/b.jpg", &other, Hash::of(b"x")).await,
        Err(Error::Integrity(_))
    ));
    assert!(matches!(
        store.put("../b.jpg", &other, other_hash).await,
        Err(Error::InvalidKey(_))
    ));
    assert_eq!(store.get("p/a.jpg", None).await.unwrap(), photo);
    assert_eq!(store.head("p/b.jpg").await.unwrap(), None);

    // range reads, clamped to the object like HTTP ranges
    assert_eq!(store.get("p/a.jpg", Some(0..1)).await.unwrap(), photo[..1]);
    assert_eq!(store.get("p/a.jpg", Some(500..1500)).await.unwrap(), photo[500..1500]);
    assert_eq!(
        store.get("p/a.jpg", Some(99_999..100_000)).await.unwrap(),
        photo[99_999..]
    );
    assert_eq!(
        store.get("p/a.jpg", Some(99_000..200_000)).await.unwrap(),
        photo[99_000..]
    );
    assert!(matches!(store.get("p/missing", None).await, Err(Error::NotFound(_))));

    // server-side copy keeps the bytes and the metadata
    assert_eq!(store.copy("p/a.jpg", "q/a copy.jpg").await.unwrap(), meta);
    assert_eq!(store.head("q/a copy.jpg").await.unwrap(), Some(meta));
    assert_eq!(store.get("q/a copy.jpg", None).await.unwrap(), photo);
    assert!(matches!(
        store.copy("p/a.jpg", "q/a copy.jpg").await,
        Err(Error::Exists(_))
    ));
    assert!(matches!(store.copy("p/missing", "q/x").await, Err(Error::NotFound(_))));

    // prefix listing is by key prefix, not by directory, and sorted
    put(store, dir, "p/b/c.jpg", b"c").await;
    put(store, dir, "pa.jpg", b"pa").await;
    assert_eq!(store.list("p/").await.unwrap(), ["p/a.jpg", "p/b/c.jpg"]);
    assert_eq!(store.list("p").await.unwrap(), ["p/a.jpg", "p/b/c.jpg", "pa.jpg"]);
    assert_eq!(store.list("p/b").await.unwrap(), ["p/b/c.jpg"]);
    assert_eq!(store.list("nothing/").await.unwrap(), Vec::<String>::new());
    assert_eq!(
        store.list("").await.unwrap(),
        ["empty", "p/a.jpg", "p/b/c.jpg", "pa.jpg", "q/a copy.jpg"]
    );

    // delete, idempotently, with read-after-write
    store.delete("pa.jpg").await.unwrap();
    store.delete("pa.jpg").await.unwrap();
    assert_eq!(store.head("pa.jpg").await.unwrap(), None);
    assert_eq!(store.list("pa").await.unwrap(), Vec::<String>::new());

    // multipart, and an aborted multipart write that leaves nothing behind
    let big = bytes(multipart, 7);
    put(store, dir, "big/video.mov", &big).await;
    assert_eq!(
        store.get("big/video.mov", Some(5..multipart as u64 - 5)).await.unwrap(),
        big[5..multipart - 5]
    );
    fail.set(Some(2));
    let (staged, hash) = testing::staged(dir, &bytes(multipart, 9));
    let failed = store.put("big/aborted.mov", &staged, hash).await;
    fail.set(None);
    assert!(
        matches!(&failed, Err(Error::Other(why)) if why.contains("injected")),
        "{failed:?}"
    );
    assert_eq!(store.head("big/aborted.mov").await.unwrap(), None);
    assert!(store.uploads("").await.unwrap().is_empty());
    assert_eq!(store.list("big/").await.unwrap(), ["big/video.mov"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn the_filesystem_driver_conforms() {
    let root = tempfile::tempdir().unwrap();
    let fail = FailAt::default();
    let store = FsStore::open(root.path(), Duration::from_secs(30))
        .await
        .unwrap()
        .with_hook(fail.hook());
    suite(&store, &fail, 20 << 20).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn garage_conforms() {
    let fail = FailAt::default();
    let store = testing::garage_store(Duration::from_secs(30)).with_hook(fail.hook());
    suite(&store, &fail, 11 << 20).await;
}

/// The test Garage behind a proxy that answers 503 Service Unavailable to the requests `fails` picks by their number,
/// and the number of requests so far.
fn flaky_garage(fails: fn(usize) -> bool) -> (S3Config, Arc<AtomicUsize>) {
    let mut config = testing::garage();
    let garage = config.endpoint.replace("http://", "");
    let proxy = TcpListener::bind("127.0.0.1:0").unwrap();
    config.endpoint = format!("http://{}", proxy.local_addr().unwrap());
    let seen = Arc::new(AtomicUsize::new(0));
    let count = seen.clone();
    std::thread::spawn(move || {
        for client in proxy.incoming() {
            let mut client = client.unwrap();
            let request = closing(&mut client);
            if fails(count.fetch_add(1, Ordering::SeqCst)) {
                let busy = "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 0\r\nconnection: close\r\n\r\n";
                client.write_all(busy.as_bytes()).unwrap();
            } else {
                let mut garage = TcpStream::connect(&garage).unwrap();
                garage.write_all(&request).unwrap();
                // The client may hang up once it has read what it needs, such as a HEAD's headers.
                drop(std::io::copy(&mut garage, &mut client));
            }
        }
    });
    (config, seen)
}

/// One HTTP request from `client`, asking the server to close the connection after its answer.
fn closing(client: &mut TcpStream) -> Vec<u8> {
    let mut reader = BufReader::new(client);
    let (mut head, mut length) = (String::new(), 0);
    loop {
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        if line == "\r\n" {
            break;
        }
        if let Some((name, value)) = line.split_once(':')
            && name.eq_ignore_ascii_case("content-length")
        {
            length = value.trim().parse().unwrap();
        }
        head.push_str(&line);
    }
    head.push_str("connection: close\r\n\r\n");
    let mut body = vec![0; length];
    reader.read_exact(&mut body).unwrap();
    [head.into_bytes(), body].concat()
}

/// An object store that is busy for a moment answers 503, as Garage does when its database is locked under load:
/// every call tries again, a few times.
#[tokio::test(flavor = "multi_thread")]
async fn garage_conforms_when_it_answers_every_first_try_with_503() {
    let fail = FailAt::default();
    let (config, _) = flaky_garage(|n| n % 2 == 0);
    let store = S3Store::open(&config, Duration::from_secs(30))
        .unwrap()
        .part_size(5 << 20)
        .with_hook(fail.hook());
    suite(&store, &fail, 11 << 20).await;

    let (config, seen) = flaky_garage(|_| true);
    let busy = S3Store::open(&config, Duration::from_secs(30)).unwrap().head("a").await;
    assert!(
        matches!(&busy, Err(Error::Other(why)) if why.contains("503")),
        "{busy:?}"
    );
    assert_eq!(seen.load(Ordering::SeqCst), 4, "tries");
}

#[tokio::test(flavor = "multi_thread")]
async fn local_returns_a_filesystem_original_in_place_and_an_object_as_a_hash_checked_copy() {
    let root = tempfile::tempdir().unwrap();
    let fs = FsStore::open(root.path(), Duration::from_secs(30)).await.unwrap();
    let s3 = testing::garage_store(Duration::from_secs(30));
    let photo = bytes(12 << 20, 3);
    for store in [&fs as &dyn BlobStore, &s3] {
        let scratch = tempfile::tempdir().unwrap();
        let meta = put(store, root.path(), "2024/IMG_0001.HEIC", &photo).await;
        let hash = meta.hash.unwrap();
        let local = store.local("2024/IMG_0001.HEIC", hash, scratch.path()).await.unwrap();
        let path = match &local {
            Local::InPlace(path) => {
                assert_eq!(path, &root.path().join("2024/IMG_0001.HEIC"));
                path
            }
            Local::Copy(path) => {
                assert_eq!(path, &scratch.path().join("IMG_0001.HEIC"));
                path
            }
        };
        assert_eq!(std::fs::read(path).unwrap(), photo);
        let empty = tempfile::tempdir().unwrap();
        let wrong = store
            .local("2024/IMG_0001.HEIC", Hash::of(b"other"), empty.path())
            .await;
        if matches!(local, Local::Copy(_)) {
            assert!(matches!(wrong, Err(Error::Integrity(_))), "{wrong:?}");
            assert_eq!(std::fs::read_dir(empty.path()).unwrap().count(), 0, "no copy is left");
        }
        assert!(matches!(
            store.local("missing", hash, empty.path()).await,
            Err(Error::NotFound(_))
        ));
    }
    assert!(matches!(
        fs.local("2024/IMG_0001.HEIC", Hash::of(b""), root.path()).await,
        Ok(Local::InPlace(_))
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn a_black_holed_endpoint_times_out() {
    let hole = TcpListener::bind("127.0.0.1:0").unwrap();
    let mut config = testing::garage();
    config.endpoint = format!("http://{}", hole.local_addr().unwrap());
    let store = S3Store::open(&config, Duration::from_millis(500)).unwrap();
    let started = photolib_spawn::Running::start();
    let dir = tempfile::tempdir().unwrap();
    let (staged, hash) = testing::staged(dir.path(), b"x");
    for result in [
        store.head("a").await.map(drop),
        store.put("a", &staged, hash).await.map(drop),
        store.list("").await.map(drop),
        store.uploads("").await.map(drop),
    ] {
        assert!(matches!(result, Err(Error::Timeout(_))), "{result:?}");
    }
    assert!(started.elapsed() < Duration::from_secs(4), "{:?}", started.elapsed());
}

/// `TEST_CASEFOLD_DIR=<a directory on a case-insensitive volume> cargo test -- --ignored` runs it.
#[tokio::test]
#[ignore = "needs TEST_CASEFOLD_DIR, a directory on a case-insensitive volume"]
async fn a_case_insensitive_volume_never_overwrites_a_name_that_differs_in_case() {
    let dir = std::env::var_os("TEST_CASEFOLD_DIR").expect("TEST_CASEFOLD_DIR");
    let root = tempfile::tempdir_in(dir).unwrap();
    let store = FsStore::open(root.path(), Duration::from_secs(30)).await.unwrap();
    let staging = tempfile::tempdir().unwrap();
    put(&store, staging.path(), "Fotos/IMG_0001.JPG", b"upper").await;
    let (lower, hash) = testing::staged(staging.path(), b"lower");
    for key in ["Fotos/img_0001.jpg", "fotos/IMG_0001.JPG"] {
        let put = store.put(key, &lower, hash).await;
        assert!(matches!(put, Err(Error::Exists(_))), "{key}: {put:?}");
    }
    assert_eq!(store.list("").await.unwrap(), ["Fotos/IMG_0001.JPG"]);
    assert_eq!(store.get("fotos/img_0001.jpg", None).await.unwrap(), b"upper");
}
