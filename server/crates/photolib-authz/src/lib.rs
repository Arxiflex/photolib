//! The single authorization path of photolibd (design 12 §4, ADR-0038): what a principal may do to a resource.
//!
//! One SQL scope per principal, action and kind of resource answers both questions a handler asks — `can` for one
//! resource, `scope` for a list or a sync stream — so a single and a bulk path cannot disagree, and a list cannot show
//! what a single read refuses. Access paths: owner, library member, album member (or album owner), partner share,
//! public link and processing grant; whatever else shows an asset (a cover, a memory, a face crop, a search hit, a
//! map pin) asks the same asset scope. A file that is no photo or video (no media kind) stays in its library: no album,
//! partner share or link shares it and no surface shows it (ADR-0066). Handlers never check permissions themselves.
//! The server's policy (ADR-0240) switches capabilities off for every principal before roles count.

use sqlx::{PgPool, Postgres, QueryBuilder};
use uuid::Uuid;

/// An account's role on the server.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Role {
    /// Manages accounts; sees no one else's content.
    Admin,
    /// Keeps a library of its own and shares it.
    User,
    /// Browses what is shared with it: views and downloads, never uploads, edits or deletes (OPS-27).
    Viewer,
}

/// Who makes a request, once its credential is verified.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Principal {
    /// No credential, or an account that cannot sign in (disabled, invited or deleted).
    Anonymous,
    /// An active account, from any of its devices.
    User(Uuid, Role),
    /// An API key of an active account (M2-06): the account, within the key's scopes.
    Key(Uuid, Role, Scopes),
    /// A public link whose token, and password if it has one, was verified.
    Link(Uuid),
    /// The worker of a processing grant (design 06 §7).
    Grant(Uuid),
}

/// What a principal does to a resource.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Action {
    /// See metadata, thumbnails and previews, keep one's own state of them (favourite, seen, hidden from memories);
    /// sync a stream.
    View,
    /// Fetch originals.
    Download,
    /// Upload into a library, add items to an album (`Resource::Item`).
    Contribute,
    /// Change an asset's metadata, an album's items and blocks, a library's settings.
    Edit,
    /// Trash, restore or delete.
    Delete,
    /// Give others access: members, links, partner shares.
    Share,
    /// Manage the server's accounts.
    ManageUsers,
    /// Create, list and revoke one's own API keys.
    ManageKeys,
    /// Run the server: jobs, libraries, stores, settings, logs and diagnostics (the admin console).
    ManageServer,
    /// Pause the job types that keep data safe, such as backups and scrubs.
    PauseMaintenance,
    /// Process an asset for one purpose of a grant.
    Process(Purpose),
}

impl Principal {
    /// Who does `action`: a key acts as its account within its scopes, and as nobody beyond them.
    fn acting(self, action: Action) -> Self {
        match self {
            Self::Key(user, role, scopes) if scopes.allows(action) => Self::User(user, role),
            Self::Key(..) => Self::Anonymous,
            who => who,
        }
    }
}

/// The actions an API key may be given: never processing, which is a grant's, nor managing keys, so that a leaked key
/// can neither mint nor keep others, nor pausing maintenance, which needs an administrator at the keyboard.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Scopes(u8);

impl Scopes {
    const ALL: [Action; 8] = [
        Action::View,
        Action::Download,
        Action::Contribute,
        Action::Edit,
        Action::Delete,
        Action::Share,
        Action::ManageUsers,
        Action::ManageServer,
    ];

    fn allows(self, action: Action) -> bool {
        self.0 & Self::bit(action) != 0
    }

    fn bit(action: Action) -> u8 {
        Self::ALL
            .iter()
            .position(|scope| *scope == action)
            .map_or(0, |at| 1 << at)
    }
}

/// Leaves out the actions a key cannot be given.
impl FromIterator<Action> for Scopes {
    fn from_iter<I: IntoIterator<Item = Action>>(actions: I) -> Self {
        Self(actions.into_iter().fold(0, |bits, action| bits | Self::bit(action)))
    }
}

/// What a processing grant allows (design 06 §7), named in lower case in `processing_grants.purposes`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Purpose {
    /// Render thumbnails.
    Thumbs,
    /// Transcode videos.
    Transcode,
    /// Detect and recognise faces.
    Faces,
    /// Compute embeddings for smart search.
    Embeddings,
    /// Read text.
    Ocr,
    /// Find duplicates.
    Duplicates,
    /// Render edits.
    Edit,
    /// Import into the library.
    Import,
    /// Export from it.
    Export,
}

impl Purpose {
    /// Every purpose.
    pub const ALL: [Self; 9] = [
        Self::Thumbs,
        Self::Transcode,
        Self::Faces,
        Self::Embeddings,
        Self::Ocr,
        Self::Duplicates,
        Self::Edit,
        Self::Import,
        Self::Export,
    ];
}

/// The kinds of rows `scope` lists.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    /// Libraries.
    Library,
    /// Albums.
    Album,
    /// Assets.
    Asset,
}

/// What a principal acts on.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Resource {
    /// The server itself: its accounts and settings.
    Server,
    /// A library.
    Library(Uuid),
    /// An album.
    Album(Uuid),
    /// An asset.
    Asset(Uuid),
    /// A sync stream.
    Stream(Stream),
    /// A resumable upload (ADR-0061).
    Upload(Uuid),
    /// An asset as an item of an album: adding it (`Contribute`) needs `Share` on the asset too, else a member or a
    /// partner could put someone else's asset into an album and publish it by link.
    Item {
        /// The album.
        album: Uuid,
        /// The asset.
        asset: Uuid,
    },
    /// An album's cover, to whoever may view the album and the cover.
    Cover(Uuid),
    /// An asset in a memory (design 14 §3), to the memory's owner.
    Memory {
        /// The memory.
        memory: Uuid,
        /// The asset.
        asset: Uuid,
    },
    /// A face's crop.
    Face(Uuid),
    /// An asset as a search hit.
    Search(Uuid),
    /// An asset's pin on the map.
    Map(Uuid),
    /// A library's folders, in the folder browser.
    Folders(Uuid),
    /// An asset's XMP sidecar, which a change of its metadata writes.
    Sidecar(Uuid),
    /// The device folders an app connected to the server shows.
    DeviceFolders,
}

/// A capability the server's policy switches (design 15 §10, ADR-0240). On unless a level sets it off; off, the
/// actions that need it are refused whatever the roles.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Capability {
    /// Managed libraries: none is created, and none takes uploads.
    ManagedLibraries,
    /// Uploads from devices, the web and the CLI alike.
    Uploads,
    /// Browsing a library's folders.
    FolderBrowser,
    /// Device folders in the apps connected to the server.
    DeviceFolders,
    /// Sharing and public links: no share or link gives access, and none is made.
    Sharing,
    /// Editing assets.
    Edits,
    /// Trashing and deleting assets.
    Deletes,
    /// Writing XMP sidecars of metadata changes.
    XmpWrites,
    /// Faces, people and face detection.
    FaceRecognition,
    /// Smart search: embeddings and their sync.
    MlSearch,
}

impl Capability {
    /// Every capability, in the order the API numbers them.
    pub const ALL: [Self; 10] = [
        Self::ManagedLibraries,
        Self::Uploads,
        Self::FolderBrowser,
        Self::DeviceFolders,
        Self::Sharing,
        Self::Edits,
        Self::Deletes,
        Self::XmpWrites,
        Self::FaceRecognition,
        Self::MlSearch,
    ];

    /// Its name in `policy_switches`, the API and the configuration file.
    pub fn name(self) -> &'static str {
        match self {
            Self::ManagedLibraries => "managed_libraries",
            Self::Uploads => "uploads",
            Self::FolderBrowser => "folder_browser",
            Self::DeviceFolders => "device_folders",
            Self::Sharing => "sharing",
            Self::Edits => "edits",
            Self::Deletes => "deletes",
            Self::XmpWrites => "xmp_writes",
            Self::FaceRecognition => "face_recognition",
            Self::MlSearch => "ml_search",
        }
    }
}

/// Every capability's effective value for `account` in `library`, and the level that decides it: `config`, `library`,
/// `user`, `server` or `default` (ADR-0240).
pub async fn policy(
    pool: &PgPool,
    account: Option<Uuid>,
    library: Option<Uuid>,
) -> Result<Vec<(Capability, bool, String)>, sqlx::Error> {
    let names = Capability::ALL.map(Capability::name);
    let [before, between, after] = DECIDING;
    let deciding = format!("{before}$3::uuid{between}$2::uuid{after}");
    let rows: Vec<(bool, String)> = sqlx::query_as(&format!(
        "SELECT coalesce(d.enabled, true), coalesce(d.level, 'default') FROM unnest($1::text[]) WITH ORDINALITY c (name, n)
         LEFT JOIN LATERAL (SELECT enabled, CASE WHEN pinned THEN 'config' WHEN library_id IS NOT NULL THEN 'library'
             WHEN user_id IS NOT NULL THEN 'user' ELSE 'server' END AS level
             FROM policy_switches WHERE capability = c.name {deciding}) d ON true ORDER BY c.n"
    ))
    .bind(&names[..])
    .bind(account.map(|id| id.to_string()))
    .bind(library.map(|id| id.to_string()))
    .fetch_all(pool)
    .await?;
    Ok(Capability::ALL
        .into_iter()
        .zip(rows)
        .map(|(capability, (on, level))| (capability, on, level))
        .collect())
}

/// The sync streams (design 05 §3); `View` is the only action on them, and only accounts sync.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Stream {
    /// The account itself.
    Account,
    /// The libraries it reaches.
    Libraries,
    /// The albums it reaches.
    Albums,
    /// Its tags.
    Tags,
    /// Its people.
    People,
    /// Its places.
    UserPlaces,
    /// Its memories.
    Memories,
    /// The assets of a library; the stream's rows still pass `scope`, which hides what owners locked or trashed.
    Assets(Uuid),
    /// The faces of a library.
    Faces(Uuid),
    /// The ML results of a library.
    Ml(Uuid),
    /// The items of an album shared with the account.
    AlbumItems(Uuid),
    /// What the owner `Uuid` shares with the account.
    Partner(Uuid),
}

/// What a route requires before its handler runs (ADR-0038).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Rule {
    /// Anyone: the request carries its own credential, such as the setup token, or asks for nothing private.
    Anyone,
    /// `action` on the server itself.
    Server(Action),
    /// An account, or its key with `action`'s scope; what it reaches is `scope`'s to say.
    Account(Action),
}

impl Rule {
    /// Whether the rule lets `who` call the procedure.
    pub fn admits(self, who: Principal) -> bool {
        match self {
            Self::Anyone => true,
            Self::Server(action) => on_server(who.acting(action), action),
            Self::Account(action) => matches!(who.acting(action), Principal::User(..)),
        }
    }
}

fn on_server(who: Principal, action: Action) -> bool {
    matches!(
        (who, action),
        (
            Principal::User(_, Role::Admin),
            Action::ManageUsers | Action::ManageServer | Action::PauseMaintenance
        ) | (Principal::User(..), Action::ManageKeys)
    )
}

/// Whether `who` may do `action` to `what`.
pub async fn can(pool: &PgPool, who: Principal, action: Action, what: Resource) -> Result<bool, sqlx::Error> {
    let (asked, who) = (who, who.acting(action));
    let mut q = QueryBuilder::new("SELECT ");
    // The row `who` needs access to, and the capability, if any, that it needs besides (ADR-0240).
    let (kind, id, needs) = match what {
        Resource::Server => return Ok(on_server(who, action)),
        Resource::Library(id) => (Kind::Library, id, None),
        Resource::Album(id) => (Kind::Album, id, None),
        Resource::Asset(id) => (Kind::Asset, id, None),
        Resource::Folders(id) if action == Action::View => {
            (Kind::Library, id, Some((Capability::FolderBrowser, At::Library(id))))
        }
        Resource::Sidecar(id) if action == Action::Edit => {
            (Kind::Asset, id, Some((Capability::XmpWrites, At::LibraryOf(id))))
        }
        Resource::DeviceFolders if action == Action::View && matches!(who, Principal::User(..)) => {
            push_on(&mut q, Capability::DeviceFolders, who, At::Nowhere);
            return q.build_query_scalar().fetch_one(pool).await;
        }
        Resource::Cover(_) | Resource::Memory { .. } | Resource::Face(_) | Resource::Search(_) | Resource::Map(_) => {
            return match action {
                Action::View => shows(pool, who, what).await,
                _ => Ok(false),
            };
        }
        Resource::Item { album, asset } if action == Action::Contribute => {
            return adds(pool, asked, album, asset).await;
        }
        Resource::Upload(id) if action == Action::Contribute => return appends(pool, who, id).await,
        Resource::Folders(_)
        | Resource::Sidecar(_)
        | Resource::DeviceFolders
        | Resource::Item { .. }
        | Resource::Upload(_) => return Ok(false),
        Resource::Stream(stream) => {
            let Principal::User(me, _) = who else {
                return Ok(false);
            };
            match stream {
                _ if action != Action::View => return Ok(false),
                Stream::Assets(library) => (Kind::Library, library, None),
                Stream::Faces(library) => (
                    Kind::Library,
                    library,
                    Some((Capability::FaceRecognition, At::Library(library))),
                ),
                Stream::Ml(library) => (
                    Kind::Library,
                    library,
                    Some((Capability::MlSearch, At::Library(library))),
                ),
                Stream::AlbumItems(album) => (Kind::Album, album, None),
                Stream::Partner(owner) => {
                    q.push("EXISTS (SELECT FROM partner_shares WHERE owner_id = ");
                    q.push_bind(owner.to_string()).push("::uuid AND partner_id = ");
                    q.push_bind(me.to_string()).push("::uuid) AND ");
                    push_on(
                        &mut q,
                        Capability::Sharing,
                        Principal::User(owner, Role::User),
                        At::Nowhere,
                    );
                    return q.build_query_scalar().fetch_one(pool).await;
                }
                Stream::People => {
                    push_on(&mut q, Capability::FaceRecognition, who, At::Nowhere);
                    return q.build_query_scalar().fetch_one(pool).await;
                }
                _ => return Ok(true),
            }
        }
    };
    push_allowed(&mut q, who, action, kind, id);
    if let Some((capability, at)) = needs {
        q.push(" AND ");
        push_on(&mut q, capability, who, at);
    }
    q.build_query_scalar().fetch_one(pool).await
}

/// Whether `who` may add `asset` to `album`: contribute to the album, and share the asset, without the sharing switch:
/// an owner files their own assets into their own albums whatever it says, while with sharing off no album gives
/// others access.
async fn adds(pool: &PgPool, who: Principal, album: Uuid, asset: Uuid) -> Result<bool, sqlx::Error> {
    let mut q = QueryBuilder::new("SELECT ");
    push_allowed(&mut q, who, Action::Contribute, Kind::Album, album);
    q.push(" AND EXISTS (SELECT FROM (");
    paths(who, Action::Share, Kind::Asset, &mut q);
    q.push(") s WHERE id = ").push_bind(asset.to_string());
    q.push("::uuid) AND EXISTS (SELECT FROM assets WHERE id = ");
    q.push_bind(asset.to_string())
        .push("::uuid AND media_kind IS NOT NULL)");
    q.build_query_scalar().fetch_one(pool).await
}

/// Whether `who` may append to the upload `id`: only its uploader, while they may still contribute to its library.
async fn appends(pool: &PgPool, who: Principal, id: Uuid) -> Result<bool, sqlx::Error> {
    let Principal::User(me, _) = who else {
        return Ok(false);
    };
    let mut q = QueryBuilder::new("SELECT EXISTS (SELECT FROM uploads WHERE id = ");
    q.push_bind(id.to_string()).push("::uuid AND owner_id = ");
    q.push_bind(me.to_string()).push("::uuid AND library_id IN (");
    scope(who, Action::Contribute, Kind::Library, &mut q);
    q.push("))");
    q.build_query_scalar().fetch_one(pool).await
}

/// Where a capability is asked about.
#[derive(Clone, Copy)]
enum At {
    /// The server's and the account's switches only.
    Nowhere,
    Library(Uuid),
    /// An asset's library.
    LibraryOf(Uuid),
    /// The library an expression of the query around names.
    Sql(&'static str),
}

/// Pushes whether the server's policy lets the account behind `who` use `capability` `at` a library (ADR-0240): a
/// subquery the check plans with the rest, where a function would be planned again at every call.
fn push_on(q: &mut QueryBuilder<'_, Postgres>, capability: Capability, who: Principal, at: At) {
    let [before, between, after] = DECIDING;
    q.push("coalesce((SELECT enabled FROM policy_switches WHERE capability = '");
    q.push(capability.name()).push("'").push(before);
    match at {
        At::Nowhere => q.push("NULL"),
        At::Library(id) => q.push_bind(id.to_string()).push("::uuid"),
        At::LibraryOf(asset) => (q.push("(SELECT library_id FROM assets WHERE id = "))
            .push_bind(asset.to_string())
            .push("::uuid)"),
        At::Sql(sql) => q.push(sql),
    };
    q.push(between);
    match who {
        Principal::User(me, _) => q.push_bind(me.to_string()).push("::uuid"),
        Principal::Grant(grant) => (q.push("(SELECT user_id FROM processing_grants WHERE id = "))
            .push_bind(grant.to_string())
            .push("::uuid)"),
        _ => q.push("NULL"),
    };
    q.push(after).push("), true)");
}

/// While the account `owner` (SQL) may share, wherever.
fn shares(owner: &str) -> String {
    let [before, between, after] = DECIDING;
    let deciding = format!("{before}NULL{between}{owner}{after}");
    format!(" AND coalesce((SELECT enabled FROM policy_switches WHERE capability = 'sharing' {deciding}), true)")
}

/// Narrows the switches of a capability to the one that decides for an account in a library, which go between the
/// pieces: the configuration's pin, else the narrowest level that sets it, the library's, the account's, then the
/// server's; none leaves it on.
const DECIDING: [&str; 3] = [
    "AND (library_id = ",
    " OR user_id = ",
    " OR (library_id IS NULL AND user_id IS NULL)) ORDER BY pinned DESC, library_id IS NULL, user_id IS NULL LIMIT 1",
];

/// Whether `who` may see what `surface` shows of an asset: only a photo or video they may view, so none shows a locked
/// one. Links show album covers, but never faces, memories, search hits or locations (design 12 §3).
async fn shows(pool: &PgPool, who: Principal, surface: Resource) -> Result<bool, sqlx::Error> {
    let mut q = QueryBuilder::new("SELECT EXISTS (SELECT FROM (");
    scope(who, Action::View, Kind::Asset, &mut q);
    q.push(") s JOIN assets a ON a.id = s.id AND a.media_kind IS NOT NULL WHERE s.id = (");
    match (surface, who) {
        (Resource::Cover(album), _) => {
            q.push("SELECT cover_asset_id FROM albums WHERE id = ");
            q.push_bind(album.to_string()).push("::uuid AND id IN (");
            scope(who, Action::View, Kind::Album, &mut q);
            q.push(")");
        }
        (Resource::Memory { memory, asset }, Principal::User(me, _)) => {
            q.push("SELECT item FROM memories, unnest(asset_ids) item WHERE id = ");
            q.push_bind(memory.to_string()).push("::uuid AND owner_id = ");
            q.push_bind(me.to_string()).push("::uuid AND item = ");
            q.push_bind(asset.to_string()).push("::uuid LIMIT 1");
        }
        (Resource::Face(face), Principal::User(..)) => {
            q.push("SELECT asset_id FROM faces WHERE id = ");
            q.push_bind(face.to_string()).push("::uuid");
        }
        (Resource::Search(asset) | Resource::Map(asset), Principal::User(..)) => {
            q.push("SELECT ").push_bind(asset.to_string()).push("::uuid");
        }
        _ => return Ok(false),
    }
    q.push(")");
    if let Resource::Face(_) = surface {
        q.push(" AND ");
        push_on(&mut q, Capability::FaceRecognition, who, At::Sql("a.library_id"));
    }
    q.push(")");
    q.build_query_scalar().fetch_one(pool).await
}

/// Pushes whether `id` is among the `kind` rows `who` may do `action` to.
fn push_allowed(q: &mut QueryBuilder<'_, Postgres>, who: Principal, action: Action, kind: Kind, id: Uuid) {
    q.push("EXISTS (SELECT FROM (");
    scope(who, action, kind, q);
    q.push(") s WHERE id = ").push_bind(id.to_string()).push("::uuid)");
}

/// Pushes a query of the ids of the `kind` rows `who` may do `action` to: list endpoints and sync streams keep only
/// rows `WHERE id IN (…)` it, and `can` asks it about one id. Each access path is a branch of a `UNION ALL` on its
/// own indexes; a lookup by id reaches every branch. What the server's policy switches off is refused on every path,
/// whatever the roles (ADR-0240).
pub fn scope(who: Principal, action: Action, kind: Kind, q: &mut QueryBuilder<'_, Postgres>) {
    let capability = match (action, kind) {
        (Action::Contribute, Kind::Library) => Capability::Uploads,
        (Action::Edit, Kind::Asset) => Capability::Edits,
        (Action::Delete, Kind::Asset) => Capability::Deletes,
        (Action::Share, _) => Capability::Sharing,
        (Action::Process(Purpose::Faces), _) => Capability::FaceRecognition,
        (Action::Process(Purpose::Embeddings), _) => Capability::MlSearch,
        _ => return paths(who, action, kind, q),
    };
    let who = who.acting(action);
    q.push("SELECT id FROM (");
    paths(who, action, kind, q);
    q.push(") s WHERE ");
    let library = match kind {
        Kind::Library => At::Sql("s.id"),
        Kind::Album => At::Nowhere,
        Kind::Asset => At::Sql("(SELECT library_id FROM assets WHERE id = s.id)"),
    };
    push_on(q, capability, who, library);
    if capability == Capability::Uploads {
        // Managed libraries while they are on, and read-write external ones marked as a target (design 07 §2); the
        // server never writes into a read-only one.
        q.push(" AND EXISTS (SELECT FROM libraries l WHERE l.id = s.id AND CASE WHEN l.kind = 'managed' THEN ");
        push_on(q, Capability::ManagedLibraries, who, At::Sql("l.id"));
        q.push(" ELSE l.access = 'rw' AND l.is_upload_target END)");
    }
}

fn paths(who: Principal, action: Action, kind: Kind, q: &mut QueryBuilder<'_, Postgres>) {
    use Action::{Contribute, Delete, Download, Edit, Process, Share, View};
    q.push("SELECT NULL::uuid AS id WHERE false");
    let who = who.acting(action);
    let read = matches!(action, View | Download);
    let download = if action == Download { DOWNLOADABLE } else { "" };
    // Albums, partner shares and links give access only while their owner may share (ADR-0240).
    let album_shared = shares("(SELECT owner_id FROM albums WHERE id = album_id)");
    match who {
        Principal::User(_, Role::Viewer) if !read => {}
        Principal::User(me, role) => {
            let roles = member_roles(kind, action);
            let mut path = |parts: &[&str]| push_path(q, parts, me, roles, String::new());
            if matches!(action, View | Download | Edit | Delete | Share)
                || (action == Contribute && kind != Kind::Asset)
            {
                path(&[match kind {
                    Kind::Library => "SELECT id FROM libraries WHERE owner_id = $id",
                    Kind::Album => "SELECT id FROM albums WHERE owner_id = $id",
                    Kind::Asset => "SELECT id FROM assets WHERE owner_id = $id",
                }]);
            }
            match kind {
                _ if roles.is_empty() => {}
                Kind::Library => path(&[LIBRARY_MEMBER]),
                Kind::Album => path(&[ALBUM_MEMBER, &album_shared]),
                Kind::Asset => {
                    path(&[IN_LIBRARY, SHARED]);
                    if read {
                        path(&[IN_ALBUM, &album_shared, ")", SHARED, MEDIA]);
                        path(&[PARTNER, &shares("p.owner_id"), SHARED, MEDIA]);
                    }
                    // Whoever may delete an asset sees it in the trash and may restore it.
                    if matches!(action, View | Delete) && role != Role::Viewer {
                        let deleters = member_roles(kind, Delete);
                        push_path(q, &[IN_LIBRARY, TRASHED], me, deleters, String::new());
                    }
                }
            }
        }
        Principal::Link(link) if read => match kind {
            Kind::Library => {}
            Kind::Album => push_path(q, &[LINKED, &album_shared, download], link, &[], String::new()),
            Kind::Asset => {
                let parts = [ASSETS_OF_ALBUMS, LINKED, &album_shared, download, ")", SHARED, MEDIA];
                push_path(q, &parts, link, &[], String::new());
            }
        },
        Principal::Grant(grant) => {
            if let (Process(purpose), Kind::Asset) = (action, kind) {
                let name = format!("{purpose:?}").to_lowercase();
                push_path(q, &[GRANTED], grant, &[], name);
            }
        }
        _ => {}
    }
}

/// The access paths, by kind; `$id` is the principal's id, `$roles` the member roles that allow the action and
/// `$purpose` a grant's purpose.
const LIBRARY_MEMBER: &str = "SELECT library_id FROM library_members WHERE user_id = $id AND role = ANY($roles)";
const ALBUM_MEMBER: &str = "SELECT album_id FROM album_members WHERE user_id = $id AND role = ANY($roles)";
/// A library's owner acts as an editor over what others put into it.
const IN_LIBRARY: &str = "SELECT a.id FROM assets a WHERE a.library_id IN (
    SELECT id FROM libraries WHERE owner_id = $id
    UNION ALL SELECT library_id FROM library_members WHERE user_id = $id AND role = ANY($roles))";
/// What is in the albums one owns or is a member of, whatever one's role; the member's branch is left open.
const IN_ALBUM: &str = "SELECT a.id FROM assets a JOIN album_items i ON i.asset_id = a.id WHERE i.album_id IN (
    SELECT id FROM albums WHERE owner_id = $id UNION ALL SELECT album_id FROM album_members WHERE user_id = $id";
/// A partner sees the assets of the owner's own libraries taken since the share's date, as the partner's sync stream
/// sends them, and private ones whole whatever it: the server cannot read their dates, and the partner holds their
/// keys. What the owner puts in another's library is shared as that library is (ADR-0155).
const PARTNER: &str = "SELECT a.id FROM assets a JOIN partner_shares p ON p.owner_id = a.owner_id
    JOIN libraries l ON l.id = a.library_id AND l.owner_id = a.owner_id
    WHERE p.partner_id = $id AND (p.taken_since IS NULL OR a.taken_utc >= p.taken_since OR l.privacy = 'private')";
const ASSETS_OF_ALBUMS: &str =
    "SELECT a.id FROM assets a JOIN album_items i ON i.asset_id = a.id WHERE i.album_id IN (";
/// The album of a link that is neither revoked nor expired.
const LINKED: &str = "SELECT album_id FROM links
    WHERE id = $id AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())";
const DOWNLOADABLE: &str = " AND allow_download";
/// A grant reaches only its owner's assets, within its scope and purposes, until it expires or is revoked.
const GRANTED: &str = "SELECT a.id FROM assets a JOIN processing_grants g ON g.user_id = a.owner_id
    WHERE g.id = $id AND g.revoked_at IS NULL AND g.expires_at > now() AND $purpose = ANY(g.purposes)
    AND ((g.scope -> 'libraries') ? a.library_id::text OR (g.scope -> 'assets') ? a.id::text
        OR EXISTS (SELECT FROM album_items i WHERE i.asset_id = a.id AND (g.scope -> 'albums') ? i.album_id::text))";
/// What every shared path hides: what the owner locked or trashed; whoever may delete still sees the latter.
const SHARED: &str = " AND NOT a.locked AND a.trashed_at IS NULL";
/// What albums, partner shares and links share: photos and videos, never other files (ADR-0066).
const MEDIA: &str = " AND a.media_kind IS NOT NULL";
const TRASHED: &str = " AND NOT a.locked AND a.trashed_at IS NOT NULL";

/// Pushes ` UNION ALL ` and `parts` with their placeholders bound.
fn push_path(
    q: &mut QueryBuilder<'_, Postgres>,
    parts: &[&str],
    id: Uuid,
    roles: &'static [&'static str],
    purpose: String,
) {
    let sql = parts.concat();
    let mut pieces = sql.split('$');
    q.push(" UNION ALL ").push(pieces.next().unwrap_or_default());
    for piece in pieces {
        let rest = if let Some(rest) = piece.strip_prefix("id") {
            q.push_bind(id.to_string()).push("::uuid");
            rest
        } else if let Some(rest) = piece.strip_prefix("roles") {
            q.push_bind(roles);
            rest
        } else {
            q.push_bind(purpose.clone());
            piece.strip_prefix("purpose").expect("a placeholder")
        };
        q.push(rest);
    }
}

/// The member roles of a library or album that allow `action`; for assets, the library roles.
fn member_roles(kind: Kind, action: Action) -> &'static [&'static str] {
    match (kind, action) {
        (_, Action::View | Action::Download) => &["viewer", "contributor", "editor"],
        (Kind::Library | Kind::Album, Action::Contribute) => &["contributor", "editor"],
        (Kind::Album, Action::Edit) | (Kind::Asset, Action::Edit | Action::Delete) => &["editor"],
        _ => &[],
    }
}
