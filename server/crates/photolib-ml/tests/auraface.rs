//! The optional face embedding (ADR-0389): AuraFace reproduces its golden sample on ONNX Runtime's CPU and tells
//! people apart as SFace does. It is 261 MB, downloaded from the registry: `PHOTOLIB_ML_MODELS=auraface cargo test
//! -p photolib-ml --test auraface -- --ignored`.

use photolib_ml::faces::{self, Models, Picture};
use photolib_ml::{Backend, Ort, Pool, Verdict, rss, self_test, testing};
use photolib_models::Model;

fn dot(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

fn photo(name: &str) -> (u32, u32, Vec<u8>) {
    let image = image::open(testing::photo(name)).unwrap().to_rgba8();
    (image.width(), image.height(), image.into_raw())
}

#[test]
#[ignore = "downloads 261 MB: PHOTOLIB_ML_MODELS=auraface"]
fn auraface_reproduces_its_golden_and_tells_people_apart() {
    assert!(
        std::env::var("PHOTOLIB_ML_MODELS").is_ok_and(|ids| ids.contains("auraface")),
        "run with PHOTOLIB_ML_MODELS=auraface"
    );
    let (library, dir, models) = testing::onnx();
    let ort = Ort::load(&library).unwrap();
    let reports = self_test(ort, dir.path(), &models);
    let aura = reports.iter().find(|r| r.name.starts_with("auraface@v1/")).unwrap();
    let cpu = aura.backends.iter().find(|(b, _)| *b == Backend::Cpu);
    assert!(
        matches!(cpu, Some((_, Verdict::Passed { cosine })) if *cosine > 0.9999),
        "{aura:?}"
    );
    let pool = Pool::new(ort, dir.path(), &reports, photolib_ml::MEMORY, rss);
    let by = |id: &str| -> &Model { models.iter().find(|m| m.id == id).unwrap() };
    let models = Models::new(by("yunet"), by("auraface")).unwrap();
    assert_eq!(models.dim(), 512);
    let embedding = |name: &str| {
        let (width, height, rgba) = photo(name);
        let picture = Picture {
            width,
            height,
            rgba: &rgba,
        };
        let mut found = faces::find(&pool, &models, &picture).unwrap();
        assert_eq!(found.len(), 1, "{name}");
        found.remove(0).embedding
    };
    let (a, b, magnus) = (
        embedding("face-photo-armstrong-a"),
        embedding("face-photo-armstrong-b"),
        embedding("face-photo-magnus"),
    );
    assert_eq!(a.len(), 512);
    assert!((dot(&a, &a) - 1.0).abs() < 1e-4, "a unit vector");
    let (same, other, other_too) = (dot(&a, &b), dot(&a, &magnus), dot(&b, &magnus));
    println!("AuraFace: Armstrong twice {same}, against Magnus {other} and {other_too}");
    assert!(
        same > 0.4 && same > other + 0.2 && same > other_too + 0.2,
        "{same} {other} {other_too}"
    );
}
