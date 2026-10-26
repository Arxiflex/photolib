use photolib_synthlib::{Config, Shape, generate};
use std::{env, path::PathBuf, process::ExitCode, time::Instant};

const USAGE: &str = "usage: synthlib --assets <count: 10k, 100k, 1m, ...> [--seed <u64, default 0>] \
                     [--shape <library, near-duplicates, one-timestamp, one-day, folders, albums>] --out <empty dir>";

fn main() -> ExitCode {
    let (cfg, out) = match parse(env::args().skip(1)) {
        Ok(parsed) => parsed,
        Err(e) => {
            eprintln!("synthlib: {e}\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    let started = Instant::now();
    match generate(&cfg, &out) {
        Ok(()) => {
            let (n, seed, dir, t) = (cfg.assets, cfg.seed, out.display(), started.elapsed());
            eprintln!("synthlib: {n} assets with seed {seed} in {dir} after {t:.1?}");
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("synthlib: {}: {e}", out.display());
            ExitCode::FAILURE
        }
    }
}

fn parse(mut args: impl Iterator<Item = String>) -> Result<(Config, PathBuf), String> {
    let (mut assets, mut seed, mut shape, mut out) = (None, 0, Shape::Library, None);
    while let Some(flag) = args.next() {
        let value = args.next().ok_or(format!("{flag} needs a value"))?;
        match flag.as_str() {
            "--assets" => assets = Some(count(&value).ok_or(format!("not a count: {value}"))?),
            "--seed" => seed = value.parse().map_err(|_| format!("not a seed: {value}"))?,
            "--shape" => shape = value.parse()?,
            "--out" => out = Some(PathBuf::from(value)),
            _ => return Err(format!("unknown argument {flag}")),
        }
    }
    Ok((Config { assets: assets.ok_or("--assets is required")?, seed, shape }, out.ok_or("--out is required")?))
}

/// A whole number, optionally in thousands (`k`) or millions (`m`).
fn count(s: &str) -> Option<u64> {
    let (digits, scale) = match s.char_indices().last()? {
        (i, 'k' | 'K') => (&s[..i], 1_000),
        (i, 'm' | 'M') => (&s[..i], 1_000_000),
        _ => (s, 1),
    };
    digits.parse::<u64>().ok()?.checked_mul(scale)
}

#[cfg(test)]
mod tests {
    #[test]
    fn counts_take_k_and_m_suffixes() {
        let ok = [("2500", 2500), ("0", 0), ("10k", 10_000), ("100K", 100_000), ("1m", 1_000_000), ("2M", 2_000_000)];
        for (s, n) in ok {
            assert_eq!(super::count(s), Some(n), "{s}");
        }
        for s in ["", "k", "1.5m", "-1", "lots", "1g", "99999999999999999m"] {
            assert_eq!(super::count(s), None, "{s}");
        }
    }
}
