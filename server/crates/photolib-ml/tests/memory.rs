//! The default profile's memory (design 09 §3.2: at most 2 GB, flat over a 24 h soak), in a test binary of its own,
//! as resident memory is the process's: the self-tested models run batches through a `Pool` under the default 2 GB
//! for `PHOTOLIB_ML_SOAK_SECS` (20 by default; 86400 for the design's soak), unloading every other round as when idle.

use std::time::{Duration, Instant};

use photolib_ml::{IDLE, MALLOC, MEMORY, Pool, fill, peak, reset_peak, rss, self_test};
use photolib_models::Target;

#[test]
fn the_default_profile_stays_under_2_gb_and_flat() {
    if std::env::var_os(MALLOC[0].0).is_none() {
        // photolibd's allocator settings, which only a new process takes
        let mut test = photolib_spawn::tool(std::env::current_exe().unwrap());
        test.args([
            "--exact",
            "the_default_profile_stays_under_2_gb_and_flat",
            "--nocapture",
        ])
        .envs(MALLOC);
        let output = photolib_spawn::output(&mut test, Duration::from_hours(25));
        print!("{}", String::from_utf8_lossy(&output.stdout));
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        return;
    }
    let (library, dir, models) = photolib_ml::testing::onnx();
    let ort = photolib_ml::Ort::load(&library).unwrap();
    let base = rss();
    let reports = self_test(ort, dir.path(), &models);
    let pool = Pool::new(ort, dir.path(), &reports, MEMORY, rss);
    let work: Vec<_> = (models.iter())
        .flat_map(|m| {
            m.files
                .iter()
                .filter(|f| f.targets.contains(&Target::Server))
                .map(move |f| (m, f))
        })
        .map(|(model, file)| {
            let golden = file.golden.as_ref().unwrap();
            let item: Vec<_> = golden.inputs.iter().map(|input| fill(input).unwrap()).collect();
            (format!("{}/{}", model.name(), file.name), vec![item; 41])
        })
        .collect();
    let soak = Duration::from_secs(std::env::var("PHOTOLIB_ML_SOAK_SECS").map_or(20, |s| s.parse().unwrap()));
    reset_peak();
    let started = Instant::now();
    let (mut rounds, mut warm, mut end) = (0, None, 0);
    while rounds < 4 || started.elapsed() < soak {
        for (name, items) in &work {
            assert_eq!(pool.run(name, items).unwrap().len(), items.len());
        }
        end = rss();
        if warm.is_none() && rounds >= 2 && started.elapsed() > soak / 2 {
            warm = Some(end);
        }
        if rounds % 2 == 1 {
            pool.unload_idle(Instant::now() + IDLE);
        }
        rounds += 1;
    }
    let (warm, peak, mib) = (warm.unwrap_or(end), peak(), |bytes: u64| bytes >> 20);
    // MiB, as /proc and ps count
    println!(
        "{rounds} rounds in {:?}: base {} MiB, at half time {} MiB, at the end {} MiB, peak {} MiB",
        started.elapsed(),
        mib(base),
        mib(warm),
        mib(end),
        mib(peak)
    );
    assert!(peak <= MEMORY, "peak {} MiB", mib(peak));
    assert!(end <= warm + (32 << 20), "grew from {} to {} MiB", mib(warm), mib(end));
}
