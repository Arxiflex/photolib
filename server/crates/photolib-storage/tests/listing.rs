//! Listing a filesystem store holds no file open per key, so a store of millions of files lists within the process's
//! file limit. A binary of its own: the test lowers that limit for the whole process.

use std::time::Duration;

use photolib_storage::{BlobStore, fs::FsStore};
use rustix::process::{Resource, Rlimit, getrlimit, setrlimit};

#[tokio::test]
async fn a_store_with_more_files_than_the_process_may_open_lists_them_all() {
    let root = tempfile::tempdir().unwrap();
    for i in 0..300 {
        let dir = root.path().join(format!("libraries/l/originals/{}", i % 7));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(format!("{i}.jpg")), b"x").unwrap();
    }
    let store = FsStore::open(root.path(), Duration::from_secs(30)).await.unwrap();
    let limit = getrlimit(Resource::Nofile);
    setrlimit(
        Resource::Nofile,
        Rlimit {
            current: Some(128),
            ..limit
        },
    )
    .unwrap();
    let listed = store.list("libraries/").await;
    setrlimit(Resource::Nofile, limit).unwrap();
    assert_eq!(listed.unwrap().len(), 300);
}
