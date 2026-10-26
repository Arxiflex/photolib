//! Search over the text OCR read from pictures (M5-08): the assets the caller may view whose `asset_ocr` holds the
//! query. Visibility is `scope`'s, as a sync row's; a picture in the trash, locked, or in a private library, which
//! the server never reads, is no hit.

use photolib_authz::{Action, Kind, Principal, scope};
use photolib_db::ocr::{CONTAINS, pattern};
use photolib_proto::proto::photolib::api::v1::{SearchHit, TextRegion};
use sqlx::{PgPool, QueryBuilder};

use crate::ocr::MODEL;

/// Up to `limit` hits of `query` for `who`, newest first; none for a blank query.
pub async fn text(pool: &PgPool, who: Principal, query: &str, limit: u16) -> sqlx::Result<Vec<SearchHit>> {
    let Some(pattern) = pattern(query) else {
        return Ok(vec![]);
    };
    let mut q = QueryBuilder::new(
        "SELECT a.id::text, a.library_id::text, o.text FROM assets a
         JOIN libraries l ON l.id = a.library_id AND l.privacy = 'standard'
         JOIN asset_ocr o ON o.asset_id = a.id AND o.model_id = ",
    );
    q.push_bind(MODEL)
        .push(" WHERE NOT a.locked AND a.trashed_at IS NULL AND o.text ")
        .push(CONTAINS)
        .push(" ");
    q.push_bind(pattern).push(" AND a.id IN (");
    scope(who, Action::View, Kind::Asset, &mut q);
    q.push(") ORDER BY a.created_at DESC, a.id LIMIT ")
        .push_bind(i64::from(limit));
    let rows: Vec<(String, String, String)> = q.build_query_as().fetch_all(pool).await?;
    Ok(rows
        .into_iter()
        .map(|(asset_id, library_id, text)| SearchHit {
            asset_id,
            library_id,
            text,
            ..Default::default()
        })
        .collect())
}

/// What OCR read from a picture, as it is in the version that is current.
#[derive(Clone, Debug, PartialEq)]
pub struct Text {
    /// All the text, lines separated by line breaks.
    pub text: String,
    /// Each line and where it is, in reading order.
    pub regions: Vec<TextRegion>,
}

/// The text OCR read from `asset` if `who` may view it: `Some(None)` while it is unread or was read in another version
/// than the current one, `None` if it is not theirs to see or is not there.
pub async fn of(pool: &PgPool, who: Principal, asset: uuid::Uuid) -> sqlx::Result<Option<Option<Text>>> {
    let mut q = QueryBuilder::new(
        "SELECT o.text, o.regions::text FROM assets a LEFT JOIN asset_ocr o ON o.asset_id = a.id AND o.model_id = ",
    );
    q.push_bind(MODEL).push(
        " AND (o.version_id = a.current_version_id OR (o.version_id IS NULL AND NOT EXISTS (
             SELECT FROM versions v WHERE v.id = a.current_version_id AND v.kind = 'edit')))
         WHERE NOT a.locked AND a.trashed_at IS NULL AND a.id = ",
    );
    q.push_bind(asset).push(" AND a.id IN (");
    scope(who, Action::View, Kind::Asset, &mut q);
    q.push(")");
    let row: Option<(Option<String>, Option<String>)> = q.build_query_as().fetch_optional(pool).await?;
    Ok(row.map(|(text, regions)| {
        text.map(|text| Text {
            text,
            regions: regions.map(|json| regions_of(&json)).unwrap_or_default(),
        })
    }))
}

/// The regions a job stored, as the API has them: lines whose box is not within the picture are left out.
fn regions_of(json: &str) -> Vec<TextRegion> {
    #[derive(serde::Deserialize)]
    struct Stored {
        text: String,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    }
    let stored: Vec<Stored> = serde_json::from_str(json).unwrap_or_default();
    stored
        .into_iter()
        .filter(|r| [r.x, r.y, r.width, r.height].iter().all(|v| (0.0..=1.0).contains(v)))
        .map(|r| TextRegion {
            text: r.text,
            x: r.x,
            y: r.y,
            width: r.width,
            height: r.height,
            ..Default::default()
        })
        .collect()
}
