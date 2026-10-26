//! The mass-disappearance guard (photolib-design docs/07 §4, ADR-0257): an operation that would delete, trash, hide or
//! purge more than 1,000 items or 5 % of its scope does nothing until it comes back with the token of its dry run. The
//! token names the state the items were counted in, so a confirmation never covers more than was shown.

use uuid::Uuid;

/// The most items an operation changes unconfirmed.
pub const LIMIT: i64 = 1000;
/// The largest share of its scope an operation changes unconfirmed: 1/20, 5 %.
const SHARE: i64 = 20;

/// What an operation would change: `count` items of the `total` in its scope, and the token that confirms exactly that.
#[derive(Debug, PartialEq, Eq)]
pub struct Dry {
    /// The items it would change.
    pub count: i64,
    /// The items in its scope.
    pub total: i64,
    /// What confirms it.
    pub token: String,
}

impl Dry {
    /// `count` items of `total` that `action` would change in `scope`, as counted in `state` (a scan, a snapshot).
    pub fn new(action: &str, scope: Uuid, state: Uuid, count: i64, total: i64) -> Self {
        let mut hasher = blake3::Hasher::new();
        for part in [
            action.as_bytes(),
            scope.as_bytes(),
            state.as_bytes(),
            &count.to_le_bytes(),
        ] {
            hasher.update(&part.len().to_le_bytes()).update(part);
        }
        let token = hasher.finalize().to_hex();
        Self {
            count,
            total,
            token: token.get(..32).unwrap_or_default().to_owned(),
        }
    }

    /// Whether it may run unconfirmed.
    pub fn plausible(&self) -> bool {
        self.count <= LIMIT && self.count.saturating_mul(SHARE) <= self.total
    }

    /// Whether it may run: plausible, or confirmed with its own token.
    pub fn allows(&self, token: &str) -> bool {
        self.plausible() || token == self.token
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn more_than_a_thousand_items_or_five_percent_wait_for_their_own_token() {
        let (scope, state) = (Uuid::now_v7(), Uuid::now_v7());
        let dry = |count, total| Dry::new("library.hide", scope, state, count, total);
        assert!(dry(0, 0).plausible() && dry(5, 100).plausible() && dry(1000, 20_000).plausible());
        assert!(!dry(1, 0).plausible() && !dry(6, 100).plausible() && !dry(1001, 1_000_000).plausible());
        let held = dry(6, 100);
        assert!(!held.allows("") && held.allows(&held.token));
        assert_eq!(held.token.len(), 32);
        assert_eq!(
            held.token,
            dry(6, 200).token,
            "the token names what is counted, not the scope's size"
        );
        for other in [
            dry(7, 100),
            Dry::new("library.hide", scope, Uuid::now_v7(), 6, 100),
            Dry::new("library.hide", Uuid::now_v7(), state, 6, 100),
            Dry::new("trash.empty", scope, state, 6, 100),
        ] {
            assert!(
                !held.allows(&other.token),
                "a token confirms only its own count and state"
            );
        }
    }
}
