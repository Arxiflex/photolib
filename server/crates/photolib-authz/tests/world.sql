-- Ann owns libraries L1, L2 and L3 (private), the external L4 (read-only) and L5 (read-write, an upload target), and
-- albums A1 and A2. L1 holds a1, a2 (locked), a3 (trashed), c1 and c2 (trashed), which con put there, and o1, a file
-- that is no photo or video; L2 holds b1 (2023) and b2 (no date), L3
-- p1 (whose date the server cannot read). A1 has a1, a2, c1, c2, b1 and o1, and a2 as its cover; A2 has b2, also its
-- cover. Vic, con, edi and ida (a viewer account) are members of L1 and A1 as viewer, contributor, editor and editor,
-- sam a viewer of A2. f1 and f2 are faces on a1 and a2, edi's memory m1 has a1, a2 and o1. Ann shares her library with pat from 2024 and with ida entirely, con
-- his with sam, which shows nothing he put in Ann's L1. Links k1 to k4 show A1: with downloads, without, expired and
-- revoked. Ann's grants g1 to g5: faces on L1; thumbs and transcode on A2 and b1; then faces on L1 expired, revoked
-- and without an expiry. Every id is md5(name).
INSERT INTO users (id, handle, display_name, role)
SELECT md5(handle)::uuid, handle, handle, role FROM (VALUES ('ann', 'user'), ('vic', 'user'), ('con', 'user'),
    ('edi', 'user'), ('ida', 'viewer'), ('pat', 'user'), ('sam', 'user'), ('root', 'admin')) AS u (handle, role);
INSERT INTO libraries (id, owner_id, name, kind, root_uri, privacy)
SELECT md5(name)::uuid, md5('ann')::uuid, name, 'managed', name, privacy
FROM (VALUES ('L1', 'standard'), ('L2', 'standard'), ('L3', 'private')) AS l (name, privacy);
INSERT INTO libraries (id, owner_id, name, kind, root_uri, access, is_upload_target)
SELECT md5(name)::uuid, md5('ann')::uuid, name, 'external', name, access, target
FROM (VALUES ('L4', 'ro', false), ('L5', 'rw', true)) AS l (name, access, target);
INSERT INTO assets (id, library_id, owner_id, source, taken_utc, locked, trashed_at, media_kind)
SELECT md5(name)::uuid, md5(library)::uuid, md5(owner)::uuid, 'upload', taken::timestamptz, locked, trashed::timestamptz,
    CASE WHEN name <> 'o1' THEN 'image' END
FROM (VALUES ('a1', 'L1', 'ann', '2025-05-01', false, NULL), ('a2', 'L1', 'ann', '2025-05-02', true, NULL),
    ('a3', 'L1', 'ann', '2025-05-03', false, '2025-06-01'), ('c1', 'L1', 'con', '2023-07-01', false, NULL),
    ('c2', 'L1', 'con', '2023-07-02', false, '2025-06-01'), ('b1', 'L2', 'ann', '2023-01-01', false, NULL),
    ('b2', 'L2', 'ann', NULL, false, NULL), ('p1', 'L3', 'ann', NULL, false, NULL),
    ('o1', 'L1', 'ann', '2025-05-04', false, NULL))
    AS a (name, library, owner, taken, locked, trashed);
INSERT INTO albums (id, owner_id, cover_asset_id)
VALUES (md5('A1')::uuid, md5('ann')::uuid, md5('a2')::uuid), (md5('A2')::uuid, md5('ann')::uuid, md5('b2')::uuid);
INSERT INTO album_items (id, album_id, kind, asset_id)
SELECT gen_random_uuid(), md5(album)::uuid, 'asset', md5(asset)::uuid
FROM (VALUES ('A1', 'a1'), ('A1', 'a2'), ('A1', 'c1'), ('A1', 'c2'), ('A1', 'b1'), ('A1', 'o1'), ('A2', 'b2'))
    AS i (album, asset);
INSERT INTO library_members (library_id, user_id, role)
SELECT md5('L1')::uuid, md5(handle)::uuid, role
FROM (VALUES ('vic', 'viewer'), ('con', 'contributor'), ('edi', 'editor'), ('ida', 'editor')) AS m (handle, role);
INSERT INTO album_members (album_id, user_id, role) SELECT md5('A1')::uuid, user_id, role FROM library_members
UNION ALL VALUES (md5('A2')::uuid, md5('sam')::uuid, 'viewer');
INSERT INTO faces (id, asset_id, bbox, model_id)
SELECT md5(name)::uuid, md5(asset)::uuid, '{0, 0, 1, 1}', 'm' FROM (VALUES ('f1', 'a1'), ('f2', 'a2')) AS f (name, asset);
INSERT INTO memories (id, owner_id, kind, title_template, date, asset_ids)
VALUES (md5('m1')::uuid, md5('edi')::uuid, 'on_this_day', 't', '2026-05-01',
    ARRAY[md5('a1')::uuid, md5('a2')::uuid, md5('o1')::uuid]);
INSERT INTO partner_shares (owner_id, partner_id, taken_since)
VALUES (md5('ann')::uuid, md5('pat')::uuid, '2024-01-01'), (md5('ann')::uuid, md5('ida')::uuid, NULL),
    (md5('con')::uuid, md5('sam')::uuid, NULL);
INSERT INTO links (id, album_id, token_hash, created_by, allow_download, expires_at, revoked_at)
SELECT md5(name)::uuid, md5('A1')::uuid, sha256(convert_to(name, 'UTF8')), md5('ann')::uuid, download,
    expires::timestamptz, revoked::timestamptz
FROM (VALUES ('k1', true, NULL, NULL), ('k2', false, '2999-01-01', NULL), ('k3', true, '2000-01-01', NULL),
    ('k4', true, NULL, '2000-01-01')) AS l (name, download, expires, revoked);
INSERT INTO processing_grants (id, user_id, processor, scope, purposes, user_signature, expires_at, revoked_at)
SELECT md5(name)::uuid, md5('ann')::uuid, 'pool', scope::jsonb, purposes::text[], '\x00', expires::timestamptz,
    revoked::timestamptz
FROM (VALUES
    ('g1', jsonb_build_object('libraries', jsonb_build_array(md5('L1')::uuid)), '{faces}', '2999-01-01', NULL),
    ('g2', jsonb_build_object('albums', jsonb_build_array(md5('A2')::uuid), 'assets', jsonb_build_array(md5('b1')::uuid)),
        '{thumbs,transcode}', '2999-01-01', NULL),
    ('g3', jsonb_build_object('libraries', jsonb_build_array(md5('L1')::uuid)), '{faces}', '2000-01-01', NULL),
    ('g4', jsonb_build_object('libraries', jsonb_build_array(md5('L1')::uuid)), '{faces}', '2999-01-01', '2000-01-01'),
    ('g5', jsonb_build_object('libraries', jsonb_build_array(md5('L1')::uuid)), '{faces}', NULL, NULL))
    AS g (name, scope, purposes, expires, revoked);
INSERT INTO uploads (id, owner_id, library_id, length, hash, expires_at)
SELECT md5(name)::uuid, md5(owner)::uuid, md5('L1')::uuid, 0, sha256(''), now()
FROM (VALUES ('u1', 'con'), ('u2', 'vic')) AS u (name, owner);
