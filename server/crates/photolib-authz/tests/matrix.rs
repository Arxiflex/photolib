//! The authz matrix (design 12 §4): every principal, API keys included, against every action on every resource of a
//! world with all six access paths, and every sync stream. `can` answers what the matrix says, and `scope` lists
//! exactly what `can` allows, so a single and a bulk path cannot disagree. Each capability of the server's policy
//! switched off takes away what `OFF` says and nothing else (ADR-0240).

use std::collections::{BTreeSet, HashMap};

use photolib_authz::{Action, Capability, Kind, Principal, Purpose, Resource, Role, Stream, can, scope};
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use sqlx::{PgPool, QueryBuilder};
use uuid::Uuid;

/// The world with all six access paths that the matrix names, described in its file.
const WORLD: &str = include_str!("world.sql");

/// What each principal may do: V view, D download, C contribute, E edit, X delete, S share, M manage users, K manage
/// one's API keys, A manage the server, P pause maintenance jobs, and the purposes of a grant: t thumbs, v transcode,
/// f faces, e embeddings, o ocr, d duplicates, r edit (render), i import, p export; `-` is nothing. `ann/VS` is an API
/// key of ann's with the scopes V and S; `root/MKAP`, an administrator's key given all four letters, does what its
/// scopes `manage_users` and `manage_server` allow and never manages keys or pauses maintenance (ADR-0063). A row is a
/// resource or a sync stream (design 05 §3); `item/A1/c1` is c1 as an item of A1, `cover/A1` A1's cover,
/// `memory/m1/a1` a1 in the memory m1, `face/f1` the crop of f1, `search/a1` and `map/a1` a1 as a search hit and a map
/// pin, `folders/L1` L1's folder tree, `sidecar/a1` a1's XMP sidecar and `device_folders` the device folders a
/// connected app shows.
const MATRIX: &str = "
               ann    vic con   edi  ida pat sam root anon k1 k2 k3 k4 g1 g2 g3 g4 g5 ann/VS ann/C edi/E ida/E root/M root/V root/MKAP
server         K      K   K     K    K   K   K   MKAP -    -  -  -  -  -  -  -  -  -  -      -     -     -     M      -      MA
L1             VDCEXS VD  VDC   VDC  VD  -   -   -    -    -  -  -  -  -  -  -  -  -  VS     C     -     -     -      -      -
L2             VDCEXS -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  VS     C     -     -     -      -      -
L3             VDCEXS -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  VS     C     -     -     -      -      -
L4             VDEXS  -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  VS     -     -     -     -      -      -
L5             VDCEXS -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  VS     C     -     -     -      -      -
A1             VDCEXS VD  VDC   VDCE VD  -   -   -    -    VD V  -  -  -  -  -  -  -  VS     C     E     -     -      -      -
A2             VDCEXS -   -     -    -   -   VD  -    -    -  -  -  -  -  -  -  -  -  VS     C     -     -     -      -      -
a1             VDEXS  VD  VD    VDEX VD  VD  -   -    -    VD V  -  -  f  -  -  -  -  VS     -     E     -     -      -      -
a2             VDEXS  -   -     -    -   -   -   -    -    -  -  -  -  f  -  -  -  -  VS     -     -     -     -      -      -
a3             VDEXS  -   -     VX   -   -   -   -    -    -  -  -  -  f  -  -  -  -  VS     -     -     -     -      -      -
c1             VDEX   VD  VDEXS VDEX VD  -   -   -    -    VD V  -  -  -  -  -  -  -  V      -     E     -     -      -      -
c2             VX     -   VDEXS VX   -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
b1             VDEXS  VD  VD    VD   VD  -   -   -    -    VD V  -  -  -  tv -  -  -  VS     -     -     -     -      -      -
b2             VDEXS  -   -     -    VD  -   VD  -    -    -  -  -  -  -  tv -  -  -  VS     -     -     -     -      -      -
p1             VDEXS  -   -     -    VD  VD  -   -    -    -  -  -  -  -  -  -  -  -  VS     -     -     -     -      -      -
o1             VDEXS  VD  VD    VDEX VD  -   -   -    -    -  -  -  -  f  -  -  -  -  VS     -     E     -     -      -      -
item/A1/a1     C      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
item/A1/c1     -      -   C     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
item/A1/o1     -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
cover/A1       V      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
cover/A2       V      -   -     -    -   -   V   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
memory/m1/a1   -      -   -     V    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
memory/m1/a2   -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
memory/m1/o1   -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
face/f1        V      V   V     V    V   V   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
face/f2        V      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
search/a1      V      V   V     V    V   V   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
search/a2      V      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
search/o1      -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
map/a1         V      V   V     V    V   V   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
map/a2         V      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
map/o1         -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
folders/L1     V      V   V     V    V   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
sidecar/a1     E      -   -     E    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     E     -     -      -      -
device_folders V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
u1             -      -   C     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
u2             -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
account        V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
libraries      V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
albums         V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
tags           V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
people         V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
user_places    V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
memories       V      V   V     V    V   V   V   V    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      V      -
assets/L1      V      V   V     V    V   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
assets/L2      V      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
faces/L1       V      V   V     V    V   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
ml/L1          V      V   V     V    V   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
album_items/A1 V      V   V     V    V   -   -   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
album_items/A2 V      -   -     -    -   -   V   -    -    -  -  -  -  -  -  -  -  -  V      -     -     -     -      -      -
partner/ann    -      -   -     -    V   V   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
partner/con    -      -   -     -    -   -   V   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
partner/sam    -      -   -     -    -   -   -   -    -    -  -  -  -  -  -  -  -  -  -      -     -     -     -      -      -
";

/// What each capability switched off at the server takes away from `MATRIX` (ADR-0240), from sessions, API keys,
/// links, grants and sync streams alike, and nothing else: `capability rows columns letters`, `*` for every row or
/// column. Off, sharing gives no one access through an album, a partner share or a link, and makes no share; an owner
/// still files their own assets into their own albums.
const OFF: &str = "
managed_libraries L1,L2,L3,u1                               *                           C
uploads           L1,L2,L3,L5,u1                            *                           C
folder_browser    folders/L1                                *                           V
device_folders    device_folders                            *                           V
sharing           *                                         *                           S
sharing           A1                                        vic,con,edi,ida,k1,k2,edi/E VDCE
sharing           b1                                        vic,con,edi,ida,k1,k2       VD
sharing           a1,c1                                     k1,k2                       VD
sharing           album_items/A1                            vic,con,edi,ida             V
sharing           item/A1/c1                                con                         C
sharing           A2,b2,cover/A2,album_items/A2,partner/con sam                         VD
sharing           a1,face/f1,search/a1,map/a1               pat                         VD
sharing           b2                                        ida                         VD
sharing           p1,partner/ann                            ida,pat                     VD
edits             a1,a2,a3,c1,c2,b1,b2,p1,o1,sidecar/a1     *                           E
deletes           a1,a2,a3,c1,c2,b1,b2,p1,o1                *                           X
xmp_writes        sidecar/a1                                *                           E
face_recognition  faces/L1,face/f1,face/f2,people           *                           V
face_recognition  a1,a2,a3,o1                               g1                          f
ml_search         ml/L1                                     *                           V
";

fn actions() -> Vec<(char, Action)> {
    let mut actions = vec![
        ('V', Action::View),
        ('D', Action::Download),
        ('C', Action::Contribute),
        ('E', Action::Edit),
        ('X', Action::Delete),
        ('S', Action::Share),
        ('M', Action::ManageUsers),
        ('K', Action::ManageKeys),
        ('A', Action::ManageServer),
        ('P', Action::PauseMaintenance),
    ];
    let purposes = Purpose::ALL.into_iter().map(Action::Process);
    actions.extend("tvfeodrip".chars().zip(purposes));
    actions
}

fn principal(name: &str, id: &impl Fn(&str) -> Uuid) -> Principal {
    if let Some((account, letters)) = name.split_once('/') {
        let Principal::User(user, role) = principal(account, id) else {
            panic!("{name} is the key of an account");
        };
        let scopes = actions()
            .into_iter()
            .filter(|(letter, _)| letters.contains(*letter))
            .map(|(_, action)| action);
        return Principal::Key(user, role, scopes.collect());
    }
    let id = id(name);
    match name {
        "anon" => Principal::Anonymous,
        "ida" => Principal::User(id, Role::Viewer),
        "root" => Principal::User(id, Role::Admin),
        _ if name.starts_with('k') => Principal::Link(id),
        _ if name.starts_with('g') => Principal::Grant(id),
        _ => Principal::User(id, Role::User),
    }
}

fn resource(row: &str, id: &impl Fn(&str) -> Uuid) -> Resource {
    let pair = |ids: &str| ids.split_once('/').map(|(a, b)| (id(a), id(b))).unwrap();
    let stream = match row.split_once('/') {
        Some(("assets", library)) => Stream::Assets(id(library)),
        Some(("faces", library)) => Stream::Faces(id(library)),
        Some(("ml", library)) => Stream::Ml(id(library)),
        Some(("album_items", album)) => Stream::AlbumItems(id(album)),
        Some(("partner", owner)) => Stream::Partner(id(owner)),
        Some(("item", ids)) => {
            let (album, asset) = pair(ids);
            return Resource::Item { album, asset };
        }
        Some(("memory", ids)) => {
            let (memory, asset) = pair(ids);
            return Resource::Memory { memory, asset };
        }
        Some(("cover", album)) => return Resource::Cover(id(album)),
        Some(("face", face)) => return Resource::Face(id(face)),
        Some(("search", asset)) => return Resource::Search(id(asset)),
        Some(("map", asset)) => return Resource::Map(id(asset)),
        Some(("folders", library)) => return Resource::Folders(id(library)),
        Some(("sidecar", asset)) => return Resource::Sidecar(id(asset)),
        _ => match row {
            "server" => return Resource::Server,
            "device_folders" => return Resource::DeviceFolders,
            "account" => Stream::Account,
            "libraries" => Stream::Libraries,
            "albums" => Stream::Albums,
            "tags" => Stream::Tags,
            "people" => Stream::People,
            "user_places" => Stream::UserPlaces,
            "memories" => Stream::Memories,
            _ if row.starts_with('L') => return Resource::Library(id(row)),
            _ if row.starts_with('A') => return Resource::Album(id(row)),
            _ if row.starts_with('u') => return Resource::Upload(id(row)),
            _ => return Resource::Asset(id(row)),
        },
    };
    Resource::Stream(stream)
}

async fn listed(pool: &PgPool, who: Principal, action: Action, kind: Kind) -> BTreeSet<Uuid> {
    let mut q = QueryBuilder::new("SELECT id::text FROM (");
    scope(who, action, kind, &mut q);
    q.push(") s");
    let ids: Vec<String> = q.build_query_scalar().fetch_all(pool).await.unwrap();
    ids.iter().map(|id| id.parse().unwrap()).collect()
}

/// A database with the world, and the ids of the names in the matrix.
async fn world() -> (testpg::TestDb, HashMap<String, Uuid>) {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    sqlx::raw_sql(WORLD).execute(&db.pool).await.unwrap();
    let names: Vec<&str> = MATRIX.split_whitespace().flat_map(|word| word.split('/')).collect();
    let ids: Vec<(String, String)> = sqlx::query_as("SELECT name, md5(name)::uuid::text FROM unnest($1::text[]) name")
        .bind(&names)
        .fetch_all(&db.pool)
        .await
        .unwrap();
    let ids = ids.into_iter().map(|(name, id)| (name, id.parse().unwrap())).collect();
    (db, ids)
}

/// The columns of `MATRIX` and its rows' cells, less what `OFF` says switching `off` off takes away.
fn expected(off: Option<Capability>) -> (Vec<&'static str>, Vec<(&'static str, Vec<String>)>) {
    let mut lines = MATRIX.trim().lines();
    let columns: Vec<&str> = lines.next().unwrap().split_whitespace().collect();
    let mut rows: Vec<(&str, Vec<String>)> = lines
        .map(|line| {
            let mut cells = line.split_whitespace();
            (cells.next().unwrap(), cells.map(str::to_owned).collect())
        })
        .collect();
    let named = |list: &str, name: &str| list == "*" || list.split(',').any(|item| item == name);
    for line in OFF.trim().lines() {
        let [capability, which, whose, letters] = line.split_whitespace().collect::<Vec<_>>()[..] else {
            panic!("{line} names a capability, rows, columns and letters");
        };
        if off.map(Capability::name) != Some(capability) {
            continue;
        }
        for (_, cells) in rows.iter_mut().filter(|(row, _)| named(which, row)) {
            for (_, cell) in columns.iter().zip(cells).filter(|(column, _)| named(whose, column)) {
                cell.retain(|letter| !letters.contains(letter));
            }
        }
    }
    (columns, rows)
}

/// Where `can` and `scope` disagree with the matrix in a world whose server switches `off` off.
async fn mismatches(off: Option<Capability>) -> Vec<String> {
    let (db, ids) = world().await;
    if let Some(off) = off {
        sqlx::query("INSERT INTO policy_switches (capability, enabled) VALUES ($1, false)")
            .bind(off.name())
            .execute(&db.pool)
            .await
            .unwrap();
    }
    let id = |name: &str| ids[name];
    let (columns, rows) = expected(off);
    let (mut wrong, mut allowed) = (vec![], HashMap::<_, BTreeSet<Uuid>>::new());
    for (row, cells) in &rows {
        assert_eq!(cells.len(), columns.len(), "{row} has a cell per principal");
        let what = resource(row, &id);
        for (column, cell) in columns.iter().zip(cells) {
            let who = principal(column, &id);
            for (letter, action) in actions() {
                let expected = cell.contains(letter);
                if can(&db.pool, who, action, what).await.unwrap() != expected {
                    wrong.push(format!("{off:?} off: {column} {action:?} {row}: expected {expected}"));
                }
                let kind = match what {
                    Resource::Library(_) => Kind::Library,
                    Resource::Album(_) => Kind::Album,
                    Resource::Asset(_) => Kind::Asset,
                    _ => continue,
                };
                let ids = allowed.entry((*column, action, kind)).or_default();
                if expected {
                    ids.insert(id(row));
                }
            }
        }
    }
    for ((column, action, kind), expected) in allowed {
        let listed = listed(&db.pool, principal(column, &id), action, kind).await;
        if listed != expected {
            wrong.push(format!(
                "{off:?} off: scope of {column} {action:?} {kind:?}: {listed:?}, expected {expected:?}"
            ));
        }
    }
    wrong
}

#[tokio::test]
async fn can_and_scope_answer_what_the_matrix_says() {
    let wrong = mismatches(None).await;
    assert!(wrong.is_empty(), "{} wrong:\n{}", wrong.len(), wrong.join("\n"));
}

#[tokio::test]
async fn each_capability_switched_off_takes_away_what_it_names_and_nothing_else() {
    let worlds = tokio::task::LocalSet::new();
    let wrong = worlds
        .run_until(async {
            let mut checks = tokio::task::JoinSet::new();
            for capability in Capability::ALL {
                let named = OFF
                    .lines()
                    .any(|line| line.starts_with(&format!("{} ", capability.name())));
                assert!(named, "OFF says what switching {capability:?} off takes away");
                checks.spawn_local(mismatches(Some(capability)));
            }
            checks.join_all().await.concat()
        })
        .await;
    assert!(wrong.is_empty(), "{} wrong:\n{}", wrong.len(), wrong.join("\n"));
}

/// The narrowest level that sets a switch wins, server, then account, then library, and a pin (`!`) over all: whether
/// con, a contributor of L1, may upload there and why, and whether Ann may upload into L2.
#[tokio::test]
async fn the_narrowest_level_that_sets_a_switch_wins_and_a_pin_over_all() {
    let (db, ids) = world().await;
    let (con, ann) = (
        Principal::User(ids["con"], Role::User),
        Principal::User(ids["ann"], Role::User),
    );
    for (switches, con_in_l1, level, ann_in_l2) in [
        ("", true, "default", true),
        ("server=off", false, "server", false),
        ("server=off con=on", true, "user", false),
        ("server=off con=on L1=off", false, "library", false),
        ("server=on con=off L1=on", true, "library", true),
        ("server=on con=off", false, "user", true),
        ("server=off! con=on L1=on", false, "config", false),
        ("server=on! con=off L1=off", true, "config", true),
    ] {
        sqlx::query("DELETE FROM policy_switches")
            .execute(&db.pool)
            .await
            .unwrap();
        for switch in switches.split_whitespace() {
            let (at, value) = switch.split_once('=').unwrap();
            let (user, library) = match at {
                "server" => (None, None),
                "L1" => (None, Some(ids[at].to_string())),
                _ => (Some(ids[at].to_string()), None),
            };
            sqlx::query(
                "INSERT INTO policy_switches (capability, user_id, library_id, enabled, pinned)
                 VALUES ('uploads', $1::uuid, $2::uuid, $3, $4)",
            )
            .bind(user)
            .bind(library)
            .bind(value.starts_with("on"))
            .bind(value.ends_with('!'))
            .execute(&db.pool)
            .await
            .unwrap();
        }
        let effective = photolib_authz::policy(&db.pool, Some(ids["con"]), Some(ids["L1"]))
            .await
            .unwrap();
        let uploads = effective
            .into_iter()
            .find(|(capability, ..)| *capability == Capability::Uploads);
        assert_eq!(
            uploads,
            Some((Capability::Uploads, con_in_l1, level.into())),
            "{switches}"
        );
        let upload = |who, library| can(&db.pool, who, Action::Contribute, Resource::Library(ids[library]));
        assert_eq!(upload(con, "L1").await.unwrap(), con_in_l1, "{switches}");
        assert_eq!(upload(ann, "L2").await.unwrap(), ann_in_l2, "{switches}");
    }
}

/// The hot path: a check reads assets by id on every access path, never a whole library, even when it fails.
#[tokio::test]
async fn a_check_reads_assets_by_id_on_every_path() {
    let (db, ids) = world().await;
    sqlx::raw_sql(
        "INSERT INTO assets (id, library_id, owner_id, source)
        SELECT gen_random_uuid(), md5('L1')::uuid, md5('ann')::uuid, 'upload' FROM generate_series(1, 20000);
        ANALYZE",
    )
    .execute(&db.pool)
    .await
    .unwrap();
    for (who, action) in [
        (Principal::User(ids["vic"], Role::User), Action::View),
        (Principal::User(ids["pat"], Role::User), Action::View),
        (Principal::Link(ids["k1"]), Action::Download),
        (Principal::Grant(ids["g1"]), Action::Process(Purpose::Faces)),
    ] {
        let mut q = QueryBuilder::new("EXPLAIN (ANALYZE, BUFFERS) SELECT EXISTS (SELECT FROM (");
        scope(who, action, Kind::Asset, &mut q);
        q.push(") s WHERE id = ")
            .push_bind(ids["b2"].to_string())
            .push("::uuid)");
        let plan: Vec<String> = q.build_query_scalar().fetch_all(&db.pool).await.unwrap();
        // The root's buffers count every page the check read; the 20,000 assets take hundreds.
        let pages: u32 = plan
            .iter()
            .find_map(|line| line.trim().strip_prefix("Buffers: shared "))
            .map(|counts| counts.split(['=', ' ']).filter_map(|n| n.parse::<u32>().ok()).sum())
            .unwrap();
        assert!(pages < 100, "{who:?} read {pages} pages: {plan:#?}");
    }
}
