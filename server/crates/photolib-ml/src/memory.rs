//! The process's resident memory from `/proc/self/status`; 0 where there is none.

use std::fs;

fn status(field: &str) -> u64 {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    let kib = status.lines().find_map(|line| {
        line.strip_prefix(field)?
            .trim()
            .strip_suffix("kB")?
            .trim()
            .parse::<u64>()
            .ok()
    });
    kib.unwrap_or(0).saturating_mul(1024)
}

/// Resident bytes now.
pub fn rss() -> u64 {
    status("VmRSS:")
}

/// Resident bytes at most since the last `reset_peak`.
pub fn peak() -> u64 {
    status("VmHWM:")
}

/// Starts a new peak at the current size: Linux's `clear_refs` 5.
pub fn reset_peak() {
    fs::write("/proc/self/clear_refs", "5").ok();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_peak_follows_a_large_allocation_and_resets() {
        reset_peak();
        let before = rss();
        let held = vec![1u8; 64 << 20];
        assert!(peak() >= before + (60 << 20), "{} after {before}", peak());
        drop(held);
        reset_peak();
        assert!(peak() < before + (32 << 20));
    }
}
