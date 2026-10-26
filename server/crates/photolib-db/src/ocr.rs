//! The text OCR read from pictures (`asset_ocr`, design 09 §6), as a search matches it.

/// Matches a text against a [`pattern`], in any case: ICU's root collation folds Cyrillic and every other script
/// whatever the database's locale (PostgreSQL built with ICU), and a substring, not words, matches Chinese and
/// Japanese, which have no spaces to split at.
pub const CONTAINS: &str = "COLLATE \"und-x-icu\" ILIKE";

/// The `LIKE` pattern that holds `query`: `%`, `_` and `\` in it are characters. None for a blank query, which finds
/// nothing.
pub fn pattern(query: &str) -> Option<String> {
    (!query.trim().is_empty()).then(|| {
        let escaped = query.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_");
        format!("%{escaped}%")
    })
}

#[cfg(test)]
mod tests {
    use sqlx::PgPool;

    use super::*;
    use crate::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };

    #[test]
    fn a_query_is_text_and_a_blank_one_is_nothing() {
        assert_eq!(pattern("100%_\\").as_deref(), Some("%100\\%\\_\\\\%"));
        assert_eq!(pattern("東京").as_deref(), Some("%東京%"));
        assert_eq!((pattern(""), pattern("  \t")), (None, None));
    }

    /// Whether `text` matches `query` as a search matches it.
    async fn matches(pool: &PgPool, text: &str, query: &str) -> bool {
        sqlx::query_scalar(&format!("SELECT $1::text {CONTAINS} $2"))
            .bind(text)
            .bind(pattern(query).unwrap())
            .fetch_one(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn latin_cyrillic_and_cjk_match_in_any_case_and_wildcards_are_characters() {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        for (text, query) in [
            ("Lisboa Estação", "estação"),
            ("Lisboa Estação", "LISBOA"),
            ("Москва, Красная площадь", "красная"),
            ("Москва, Красная площадь", "МОСКВА"),
            ("東京駅 丸の内", "東京"),
            ("東京駅 丸の内", "丸の内"),
            ("100% sure", "100%"),
            ("a_b", "a_b"),
            ("a\\b", "a\\b"),
        ] {
            assert!(matches(&db.pool, text, query).await, "{query} in {text}");
        }
        for (text, query) in [("Lisboa", "Paris"), ("abc", "a_c"), ("abc", "%"), ("a\\b", "a\\\\b")] {
            assert!(!matches(&db.pool, text, query).await, "{query} in {text}");
        }
    }
}
