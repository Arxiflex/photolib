-- The upgrade fixture of schema version 0007_change_capture (docs/dev/migrations.md#upgrade-path-harness): a small
-- library with rows in every table, loaded into a database at that version. Ids read <entity>-0000-7000-8000-<n>; a
-- link's token is its id. Released, like the migration: never edit it.

INSERT INTO photolib_instance (instance_id) VALUES ('00000000-0000-7000-8000-000000000001');

INSERT INTO users (id, handle, display_name, email, role, status, quota_bytes, locale) VALUES
('00000001-0000-7000-8000-000000000001', 'ada', 'Ada', 'ada@example.org', 'admin', 'active', NULL, 'en'),
('00000001-0000-7000-8000-000000000002', 'bea', 'Bea', 'bea@example.org', 'user', 'active', 10737418240, 'de-DE'),
('00000001-0000-7000-8000-000000000003', 'cyd', 'Cyd', NULL, 'user', 'invited', NULL, 'ar'),
('00000001-0000-7000-8000-000000000004', 'dee', 'Dee', 'dee@example.org', 'user', 'disabled', NULL, NULL),
('00000001-0000-7000-8000-000000000005', 'eli', 'Eli', 'eli@example.org', 'user', 'active', NULL, 'fr'),
('00000001-0000-7000-8000-000000000006', 'fay', 'Fay', 'fay@example.org', 'user', 'active', NULL, NULL);
INSERT INTO user_keys (user_id, key_bundle) VALUES
('00000001-0000-7000-8000-000000000001', convert_to('public key bundle of ada', 'UTF8'));
INSERT INTO devices (id, user_id, name, platform, app_version, capabilities, device_public_key, last_seen_at,
                     is_trusted_node) VALUES
('00000002-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'Pixel', 'android', '0.1.0',
 '{sync.v1}', convert_to('device key of the Pixel', 'UTF8'), '2026-01-02 10:00:00+00', false),
('00000002-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', 'Desktop', 'linux', '0.1.0',
 '{sync.v1,ml}', convert_to('device key of the desktop', 'UTF8'), '2026-01-03 10:00:00+00', true);

-- A managed library, a private one, an external read-only one being scanned, and Bea's.
INSERT INTO libraries (id, owner_id, name, kind, privacy, access, root_uri, is_upload_target, storage_template,
                       scan_policy, state) VALUES
('00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'Photos', 'managed', 'standard',
 'rw', 'managed:photos', true, '{yyyy}/{MM}/{filename}', NULL, 'online'),
('00000003-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', 'Private', 'managed', 'private',
 'rw', 'managed:private', false, NULL, NULL, 'online'),
('00000003-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000001', 'NAS archive', 'external',
 'standard', 'ro', 'file:///srv/photos', false, NULL, '{"interval": "1d"}', 'scanning'),
('00000003-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000002', 'Bea', 'managed', 'standard',
 'rw', 'managed:bea', true, NULL, NULL, 'online');
INSERT INTO library_members (library_id, user_id, role) VALUES
('00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000002', 'viewer'),
('00000003-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000002', 'contributor'),
('00000003-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000001', 'editor');

INSERT INTO places (id, parent_id, level, names, lat, lon) VALUES
('00000004-0000-7000-8000-000000000001', NULL, 'country', '{"en": "Portugal", "pt": "Portugal"}', NULL, NULL),
('00000004-0000-7000-8000-000000000002', '00000004-0000-7000-8000-000000000001', 'city',
 '{"en": "Lisbon", "pt": "Lisboa"}', 38.7223, -9.1393);

INSERT INTO stacks (id, owner_id, kind, origin, review_state, ranking) VALUES
('00000005-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'burst', 'camera', 'reviewed',
 '{"best": "00000006-0000-7000-8000-000000000004"}'),
('00000005-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', 'raw_jpeg', 'camera',
 'unreviewed', NULL);

-- Assets of every kind: a live photo, a video, a burst, RAW+JPEG, a scan, an import, an edit copy, a private asset
-- (ciphertext only), trashed, archived and locked, and one of Bea's.
INSERT INTO assets (id, library_id, owner_id, original_filename, source, source_ref, content_hash, media_kind, facets,
                    taken_local, tz_offset_min, tz_name, taken_utc, time_source, time_confidence, time_precision,
                    tz_assumed, lat, lon, location_source, place_id, width, height, duration_ms, fps, codec, make,
                    model, title, description, rating, color_label, archived, locked, trashed_at, field_hlc, rights,
                    stack_id, stack_order) VALUES
('00000006-0000-7000-8000-000000000001', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'IMG_0001.HEIC', 'upload', NULL, sha256('\x01'), 'image', '{live}', '2024-05-01 14:00:00', 60, 'Europe/Lisbon',
 '2024-05-01 13:00:00+00', 'exif', 100, 'second', false, 38.7115, -9.1300, 'exif',
 '00000004-0000-7000-8000-000000000002', 4032, 3024, NULL, NULL, NULL, 'Apple', 'iPhone 15', 'Tram 28',
 'Up the hill to the castle', 4, 'red', false, false, NULL, '{"title": "1714568400000-0-pixel"}',
 '{"creator": "Ada"}', NULL, NULL),
('00000006-0000-7000-8000-000000000002', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'VID_0002.MOV', 'upload', NULL, sha256('\x02'), 'video', '{}', '2024-05-01 15:00:00', 60, 'Europe/Lisbon',
 '2024-05-01 14:00:00+00', 'quicktime', 100, 'second', false, NULL, NULL, NULL, NULL, 1920, 1080, 12000, 30, 'hevc',
 'Apple', 'iPhone 15', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, NULL, NULL),
('00000006-0000-7000-8000-000000000003', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'BURST_0003.JPG', 'upload', NULL, sha256('\x03'), 'image', '{burst}', '2024-05-02 09:00:00', 60, 'Europe/Lisbon',
 '2024-05-02 08:00:00+00', 'exif', 100, 'ms', false, NULL, NULL, NULL, NULL, 4000, 3000, NULL, NULL, NULL, 'Sony',
 'A7 IV', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, '00000005-0000-7000-8000-000000000001', 1),
('00000006-0000-7000-8000-000000000004', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'BURST_0004.JPG', 'upload', NULL, sha256('\x04'), 'image', '{burst}', '2024-05-02 09:00:00.25', 60,
 'Europe/Lisbon', '2024-05-02 08:00:00.25+00', 'exif', 100, 'ms', false, NULL, NULL, NULL, NULL, 4000, 3000, NULL,
 NULL, NULL, 'Sony', 'A7 IV', NULL, NULL, 5, NULL, false, false, NULL, '{}', NULL,
 '00000005-0000-7000-8000-000000000001', 2),
('00000006-0000-7000-8000-000000000005', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'DSC_0005.ARW', 'upload', NULL, sha256('\x05'), 'image', '{raw}', '2024-05-03 18:30:00', 60, 'Europe/Lisbon',
 '2024-05-03 17:30:00+00', 'exif', 100, 'second', false, NULL, NULL, NULL, NULL, 6000, 4000, NULL, NULL, NULL,
 'Sony', 'A7 IV', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, '00000005-0000-7000-8000-000000000002', 1),
('00000006-0000-7000-8000-000000000006', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'DSC_0005.JPG', 'upload', NULL, sha256('\x06'), 'image', '{}', '2024-05-03 18:30:00', 60, 'Europe/Lisbon',
 '2024-05-03 17:30:00+00', 'exif', 100, 'second', false, NULL, NULL, NULL, NULL, 6000, 4000, NULL, NULL, NULL,
 'Sony', 'A7 IV', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, '00000005-0000-7000-8000-000000000002', 2),
('00000006-0000-7000-8000-000000000007', '00000003-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000001',
 'scan_1987_03.tif', 'scan', 'file:///srv/photos/1987/scan_1987_03.tif', sha256('\x07'), 'image', '{scan}',
 '1987-03-01 00:00:00', NULL, NULL, NULL, 'user', 40, 'month', true, NULL, NULL, NULL, NULL, 3000, 2000, NULL, NULL,
 NULL, 'Epson', 'Perfection V600', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, NULL, NULL),
('00000006-0000-7000-8000-000000000008', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'PXL_0008.jpg', 'import', 'takeout:Photos from 2019/PXL_0008.jpg', sha256('\x08'), 'image', '{}',
 '2019-08-10 12:00:00', 120, 'Europe/Berlin', '2019-08-10 10:00:00+00', 'sidecar', 80, 'second', false, NULL, NULL,
 'import', NULL, 4000, 3000, NULL, NULL, NULL, 'Google', 'Pixel 3', NULL, NULL, 0, NULL, false, false, NULL, '{}',
 NULL, NULL, NULL),
('00000006-0000-7000-8000-000000000009', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'IMG_0001 (edited).jpg', 'edit_copy', '00000006-0000-7000-8000-000000000001', sha256('\x09'), 'image', '{}',
 '2024-05-01 14:00:00', 60, 'Europe/Lisbon', '2024-05-01 13:00:00+00', 'exif', 100, 'second', false, NULL, NULL,
 NULL, NULL, 4032, 3024, NULL, NULL, NULL, 'Apple', 'iPhone 15', NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL,
 NULL, NULL),
('00000006-0000-7000-8000-000000000011', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'IMG_0011.JPG', 'upload', NULL, sha256('\x11'), 'image', '{}', NULL, NULL, NULL, NULL, 'unknown', NULL, NULL,
 false, NULL, NULL, NULL, NULL, 800, 600, NULL, NULL, NULL, NULL, NULL, NULL, NULL, -1, NULL, false, false,
 '2026-01-05 08:00:00+00', '{}', NULL, NULL, NULL),
('00000006-0000-7000-8000-000000000012', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'IMG_0012.JPG', 'upload', NULL, sha256('\x12'), 'image', '{}', '2023-12-24 20:00:00', 60, 'Europe/Berlin',
 '2023-12-24 19:00:00+00', 'exif', 100, 'second', false, NULL, NULL, NULL, NULL, 800, 600, NULL, NULL, NULL, NULL,
 NULL, NULL, NULL, 0, NULL, true, true, NULL, '{}', NULL, NULL, NULL),
('00000006-0000-7000-8000-000000000013', '00000003-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000002',
 'bea.jpg', 'upload', NULL, sha256('\x13'), 'image', '{}', '2021-06-01 10:00:00', 120, 'Europe/Berlin',
 '2021-06-01 08:00:00+00', 'exif', 100, 'second', false, NULL, NULL, NULL, NULL, 800, 600, NULL, NULL, NULL, NULL,
 NULL, NULL, NULL, 0, NULL, false, false, NULL, '{}', NULL, NULL, NULL);
INSERT INTO assets (id, library_id, owner_id, source, meta_core, meta_user, meta_ml) VALUES
('00000006-0000-7000-8000-000000000010', '00000003-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001',
 'upload', convert_to('sealed core metadata', 'UTF8'), convert_to('sealed user metadata', 'UTF8'),
 convert_to('sealed ml results', 'UTF8'));
UPDATE stacks SET cover_asset_id = '00000006-0000-7000-8000-000000000004'
WHERE id = '00000005-0000-7000-8000-000000000001';
UPDATE stacks SET cover_asset_id = '00000006-0000-7000-8000-000000000006'
WHERE id = '00000005-0000-7000-8000-000000000002';

INSERT INTO custom_fields (id, library_id, name, kind, options) VALUES
('00000007-0000-7000-8000-000000000001', '00000003-0000-7000-8000-000000000003', 'Film stock', 'text', NULL),
('00000007-0000-7000-8000-000000000002', '00000003-0000-7000-8000-000000000003', 'Format', 'enum',
 '["35 mm", "120"]');
INSERT INTO asset_custom_values (asset_id, field_id, value) VALUES
('00000006-0000-7000-8000-000000000007', '00000007-0000-7000-8000-000000000001', '"Kodak Gold 200"'),
('00000006-0000-7000-8000-000000000007', '00000007-0000-7000-8000-000000000002', '"35 mm"');

-- Originals, a Live Photo's video, a sidecar, renditions, an encrypted original and a missing one.
INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash, state, crypto_header,
                         render_spec) VALUES
('00000008-0000-7000-8000-000000000001', '00000006-0000-7000-8000-000000000001', 'original', 'managed',
 '2024/05/IMG_0001.HEIC', 'image/heic', 2400000, sha256('\x01'), 'present', NULL, NULL),
('00000008-0000-7000-8000-000000000002', '00000006-0000-7000-8000-000000000001', 'live_video', 'managed',
 '2024/05/IMG_0001.MOV', 'video/quicktime', 3100000, sha256('\x81'), 'present', NULL, NULL),
('00000008-0000-7000-8000-000000000003', '00000006-0000-7000-8000-000000000001', 'thumbnail', 'derived',
 'thumbs/00000006-0000-7000-8000-000000000001.webp', 'image/webp', 9000, NULL, 'present', NULL,
 '{"generator": "thumb", "version": 1, "size": 256}'),
('00000008-0000-7000-8000-000000000004', '00000006-0000-7000-8000-000000000002', 'original', 'managed',
 '2024/05/VID_0002.MOV', 'video/quicktime', 48000000, sha256('\x02'), 'present', NULL, NULL),
('00000008-0000-7000-8000-000000000005', '00000006-0000-7000-8000-000000000007', 'original', 'external',
 '1987/scan_1987_03.tif', 'image/tiff', 36000000, sha256('\x07'), 'offline', NULL, NULL),
('00000008-0000-7000-8000-000000000006', '00000006-0000-7000-8000-000000000007', 'sidecar', 'external',
 '1987/scan_1987_03.tif.xmp', 'application/rdf+xml', 2000, NULL, 'present', NULL, NULL),
('00000008-0000-7000-8000-000000000007', '00000006-0000-7000-8000-000000000010', 'original', 'managed',
 'objects/00000006-0000-7000-8000-000000000010', NULL, 2500000, NULL, 'present',
 convert_to('sealed file header', 'UTF8'), NULL),
('00000008-0000-7000-8000-000000000008', '00000006-0000-7000-8000-000000000008', 'original', 'managed',
 '2019/08/PXL_0008.jpg', 'image/jpeg', 3000000, sha256('\x08'), 'missing', NULL, NULL),
('00000008-0000-7000-8000-000000000009', '00000006-0000-7000-8000-000000000001', 'render', 'derived',
 'renders/00000009-0000-7000-8000-000000000002.jpg', 'image/jpeg', 2000000, NULL, 'present', NULL,
 '{"generator": "render", "version": 1}');

INSERT INTO versions (id, asset_id, parent_id, kind, origin, label, batch_id, recipe_hash, process_version, recipe,
                      render_file_id, created_by_device, note) VALUES
('00000009-0000-7000-8000-000000000001', '00000006-0000-7000-8000-000000000001', NULL, 'original', 'upload', NULL,
 NULL, NULL, NULL, NULL, NULL, '00000002-0000-7000-8000-000000000001', NULL),
('00000009-0000-7000-8000-000000000002', '00000006-0000-7000-8000-000000000001',
 '00000009-0000-7000-8000-000000000001', 'edit', 'app', 'Warmer', '00000009-0000-7000-8000-0000000000ff',
 sha256('\x92'), '1', convert_to('recipe: warmth +10', 'UTF8'), '00000008-0000-7000-8000-000000000009',
 '00000002-0000-7000-8000-000000000002', 'for the album'),
('00000009-0000-7000-8000-000000000003', '00000006-0000-7000-8000-000000000009', NULL, 'import_variant', 'import',
 NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
UPDATE assets SET current_version_id = '00000009-0000-7000-8000-000000000002'
WHERE id = '00000006-0000-7000-8000-000000000001';
UPDATE assets SET current_version_id = '00000009-0000-7000-8000-000000000003'
WHERE id = '00000006-0000-7000-8000-000000000009';

INSERT INTO asset_user_state (user_id, asset_id, favorite, hidden_from_memories, last_viewed_at,
                              playback_position_ms) VALUES
('00000001-0000-7000-8000-000000000002', '00000006-0000-7000-8000-000000000001', true, false,
 '2026-01-04 09:00:00+00', NULL),
('00000001-0000-7000-8000-000000000001', '00000006-0000-7000-8000-000000000002', false, true, NULL, 4000);
INSERT INTO asset_embeddings (asset_id, model_id, embedding) VALUES
('00000006-0000-7000-8000-000000000001', 'siglip2-base', '\x0000803f0000003f');
INSERT INTO asset_ocr (asset_id, model_id, text) VALUES
('00000006-0000-7000-8000-000000000008', 'ppocr-v5', 'Lisboa');
INSERT INTO asset_quality (asset_id, model_id, scores) VALUES
('00000006-0000-7000-8000-000000000003', 'aesthetic-v1', '{"aesthetic": 0.8, "sharpness": 0.6}');
INSERT INTO ml_labels (id, names) VALUES ('tram', '{"en": "tram", "de": "Straßenbahn"}');
INSERT INTO asset_ml_labels (asset_id, label_id, model_id, score) VALUES
('00000006-0000-7000-8000-000000000001', 'tram', 'labels-v1', 0.93);

INSERT INTO tags (id, owner_id, parent_id, name, path, color, is_album, origin) VALUES
('0000000a-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', NULL, 'Places', 'Places', NULL,
 false, 'user'),
('0000000a-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001',
 '0000000a-0000-7000-8000-000000000001', 'Lisbon', 'Places|Lisbon', '#ffcc00', false, 'user'),
('0000000a-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000001', NULL, 'Family', 'Family', NULL,
 true, 'user'),
('0000000a-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000001', NULL, 'Takeout', 'Takeout', NULL,
 false, 'import');
INSERT INTO asset_tags (asset_id, tag_id, origin, confidence) VALUES
('00000006-0000-7000-8000-000000000001', '0000000a-0000-7000-8000-000000000002', 'user', NULL),
('00000006-0000-7000-8000-000000000008', '0000000a-0000-7000-8000-000000000004', 'import', NULL),
('00000006-0000-7000-8000-000000000003', '0000000a-0000-7000-8000-000000000003', 'ml', 0.7);

-- Albums of every kind, the first with text, heading, location, divider and date blocks.
INSERT INTO album_folders (id, owner_id, parent_id, name, sort_key) VALUES
('0000000b-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', NULL, 'Trips', 'a'),
('0000000b-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001',
 '0000000b-0000-7000-8000-000000000001', '2024', 'a');
INSERT INTO albums (id, owner_id, folder_id, sort_key, kind, title, description, cover_asset_id, sort_mode, layout,
                    privacy, query, tag_id, include_descendants, source_library_id, source_path,
                    encrypted_meta) VALUES
('0000000c-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 '0000000b-0000-7000-8000-000000000002', 'a', 'regular', 'Lisbon 2024', 'Three days in May',
 '00000006-0000-7000-8000-000000000001', 'custom', 'story', 'standard', NULL, NULL, true, NULL, NULL, NULL),
('0000000c-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', NULL, 'b', 'smart', 'Five stars',
 NULL, NULL, 'taken_desc', 'grid', 'standard', convert_to('rating >= 5', 'UTF8'), NULL, true, NULL, NULL, NULL),
('0000000c-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000001', NULL, 'c', 'tag', 'Family', NULL,
 NULL, 'taken_asc', 'justified', 'standard', NULL, '0000000a-0000-7000-8000-000000000003', true, NULL, NULL, NULL),
('0000000c-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000001', NULL, 'd', 'folder_backed', '1987',
 NULL, NULL, 'name', 'grid', 'standard', NULL, NULL, true, '00000003-0000-7000-8000-000000000003', '1987/', NULL),
('0000000c-0000-7000-8000-000000000005', '00000001-0000-7000-8000-000000000001', NULL, 'e', 'regular', NULL, NULL,
 NULL, 'added_desc', 'grid', 'private', NULL, NULL, true, NULL, NULL, convert_to('sealed album title', 'UTF8'));
INSERT INTO album_items (id, album_id, kind, asset_id, caption, body, anchor_asset_id, place_id, lat, lon, sort_key,
                         encrypted) VALUES
('0000000d-0000-7000-8000-000000000001', '0000000c-0000-7000-8000-000000000001', 'heading', NULL, NULL, 'Day one',
 '00000006-0000-7000-8000-000000000001', NULL, NULL, NULL, 'a0', NULL),
('0000000d-0000-7000-8000-000000000002', '0000000c-0000-7000-8000-000000000001', 'asset',
 '00000006-0000-7000-8000-000000000001', 'Tram 28', NULL, NULL, NULL, NULL, NULL, 'a1', NULL),
('0000000d-0000-7000-8000-000000000003', '0000000c-0000-7000-8000-000000000001', 'text', NULL, NULL,
 'We took the tram up to the castle.', '00000006-0000-7000-8000-000000000002', NULL, NULL, NULL, 'a2', NULL),
('0000000d-0000-7000-8000-000000000004', '0000000c-0000-7000-8000-000000000001', 'asset',
 '00000006-0000-7000-8000-000000000002', NULL, NULL, NULL, NULL, NULL, NULL, 'a3', NULL),
('0000000d-0000-7000-8000-000000000005', '0000000c-0000-7000-8000-000000000001', 'location', NULL, 'Castelo', NULL,
 NULL, '00000004-0000-7000-8000-000000000002', 38.7139, -9.1334, 'a4', NULL),
('0000000d-0000-7000-8000-000000000006', '0000000c-0000-7000-8000-000000000001', 'divider', NULL, NULL, NULL, NULL,
 NULL, NULL, NULL, 'a5', NULL),
('0000000d-0000-7000-8000-000000000007', '0000000c-0000-7000-8000-000000000001', 'date', NULL, '2 May', NULL,
 '00000006-0000-7000-8000-000000000003', NULL, NULL, NULL, 'a6', NULL),
('0000000d-0000-7000-8000-000000000008', '0000000c-0000-7000-8000-000000000001', 'asset',
 '00000006-0000-7000-8000-000000000003', NULL, NULL, NULL, NULL, NULL, NULL, 'a7', NULL),
('0000000d-0000-7000-8000-000000000009', '0000000c-0000-7000-8000-000000000005', 'asset',
 '00000006-0000-7000-8000-000000000010', NULL, NULL, NULL, NULL, NULL, NULL, 'a0',
 convert_to('sealed caption', 'UTF8'));

-- Shares: album members, library members (above), a partner share and links: open, with a password and an expiry,
-- revoked and expired.
INSERT INTO album_members (album_id, user_id, role) VALUES
('0000000c-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000002', 'contributor'),
('0000000c-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000003', 'viewer'),
('0000000c-0000-7000-8000-000000000004', '00000001-0000-7000-8000-000000000002', 'editor');
INSERT INTO album_user_state (user_id, album_id, hide_from_timeline, hide_from_memories) VALUES
('00000001-0000-7000-8000-000000000002', '0000000c-0000-7000-8000-000000000001', true, false);
INSERT INTO library_user_state (user_id, library_id, hide_from_timeline, hide_from_memories) VALUES
('00000001-0000-7000-8000-000000000002', '00000003-0000-7000-8000-000000000001', false, true);
INSERT INTO links (id, album_id, token_hash, created_by, password_hash, allow_download, expires_at, revoked_at)
SELECT id, album_id, sha256(convert_to(id::text, 'UTF8')), '00000001-0000-7000-8000-000000000001', password_hash,
       allow_download, expires_at, revoked_at
FROM (VALUES
    ('0000000e-0000-7000-8000-000000000001'::uuid, '0000000c-0000-7000-8000-000000000001'::uuid, NULL, true,
     NULL::timestamptz, NULL::timestamptz),
    ('0000000e-0000-7000-8000-000000000002', '0000000c-0000-7000-8000-000000000001', 'argon2id:fixture', false,
     '2030-01-01 00:00:00+00', NULL),
    ('0000000e-0000-7000-8000-000000000003', '0000000c-0000-7000-8000-000000000004', NULL, false, NULL,
     '2026-01-06 00:00:00+00'),
    ('0000000e-0000-7000-8000-000000000004', '0000000c-0000-7000-8000-000000000001', NULL, false,
     '2025-01-01 00:00:00+00', NULL)
) AS l (id, album_id, password_hash, allow_download, expires_at, revoked_at);
INSERT INTO partner_shares (owner_id, partner_id, taken_since) VALUES
('00000001-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', '2020-01-01');

-- People and pets: a person, a pet and a person merged into the first; assigned, automatic and unassigned faces.
INSERT INTO persons (id, owner_id, kind, name, birth_date, hidden, merged_into) VALUES
('0000000f-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'human', 'Maria', '1960-02-29',
 false, NULL),
('0000000f-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', 'pet', 'Tiger', NULL, false, NULL),
('0000000f-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000001', 'human', 'Mum', NULL, true,
 '0000000f-0000-7000-8000-000000000001');
INSERT INTO faces (id, asset_id, version_basis, bbox, landmarks, model_id, embedding, quality, person_id,
                   assignment) VALUES
('00000010-0000-7000-8000-000000000001', '00000006-0000-7000-8000-000000000001',
 '00000009-0000-7000-8000-000000000001', '{0.1,0.2,0.3,0.4}', '{"eyes": [[0.2, 0.3], [0.3, 0.3]]}', 'faces-v1',
 '\x0000803f', 0.9, '0000000f-0000-7000-8000-000000000001', 'user'),
('00000010-0000-7000-8000-000000000002', '00000006-0000-7000-8000-000000000003', NULL, '{0.5,0.5,0.2,0.2}', NULL,
 'faces-v1', '\x0000003f', 0.7, '0000000f-0000-7000-8000-000000000002', 'auto'),
('00000010-0000-7000-8000-000000000003', '00000006-0000-7000-8000-000000000004', NULL, '{0.5,0.5,0.2,0.2}', NULL,
 'faces-v1', '\x0000003f', 0.6, NULL, 'auto');
UPDATE persons SET cover_face_id = '00000010-0000-7000-8000-000000000001'
WHERE id = '0000000f-0000-7000-8000-000000000001';
INSERT INTO face_constraints (id, face_id, person_id, other_face_id, kind) VALUES
('00000011-0000-7000-8000-000000000001', '00000010-0000-7000-8000-000000000001',
 '0000000f-0000-7000-8000-000000000001', NULL, 'must_link'),
('00000011-0000-7000-8000-000000000002', '00000010-0000-7000-8000-000000000002', NULL,
 '00000010-0000-7000-8000-000000000003', 'cannot_link');

INSERT INTO user_places (id, user_id, name, lat, lon, radius_m, strip_on_share) VALUES
('00000012-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'Home', 52.52, 13.405, 150, true);
INSERT INTO memories (id, owner_id, kind, title_template, params, date, asset_ids, cover_asset_id, state) VALUES
('00000013-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'on_this_day',
 'memory.on_this_day', '{"years": 2}', '2026-05-01',
 '{00000006-0000-7000-8000-000000000001,00000006-0000-7000-8000-000000000002}',
 '00000006-0000-7000-8000-000000000001', 'new');

-- A processing grant to the trusted desktop, and jobs: leased, queued on a device and on the grant, dead, done by a
-- schedule and cancelled with a grant; schedules with and without a payload.
INSERT INTO processing_grants (id, user_id, processor, scope, purposes, wrapped_keys, ledger_ref, user_signature,
                               expires_at, revoked_at) VALUES
('00000014-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 '00000002-0000-7000-8000-000000000002', '{"libraries": ["00000003-0000-7000-8000-000000000002"]}',
 '{faces,search}', convert_to('wrapped library key', 'UTF8'), 'ledger:1', convert_to('signature of ada', 'UTF8'),
 '2027-01-01 00:00:00+00', NULL);
INSERT INTO jobs (id, type, payload, status, priority, placement, grant_id, attempts, run_after, lease_owner,
                  lease_until, progress, result, error, idempotency_key) VALUES
('00000015-0000-7000-8000-000000000001', 'thumbnail', convert_to('00000006-0000-7000-8000-000000000002', 'UTF8'),
 'running', 0, 'server', NULL, 1, '2026-01-07 00:00:00+00', 'worker:media@node-1', '2026-01-07 00:05:00+00', 0.5,
 NULL, NULL, 'thumbnail:00000006-0000-7000-8000-000000000002'),
('00000015-0000-7000-8000-000000000002', 'faces', NULL, 'queued', 5, 'trusted_node',
 '00000014-0000-7000-8000-000000000001', 0, '2026-01-07 00:00:00+00', NULL, NULL, NULL, NULL, NULL, NULL),
('00000015-0000-7000-8000-000000000003', 'embed', NULL, 'queued', 0, 'device', NULL, 0, '2026-01-07 00:00:00+00',
 NULL, NULL, NULL, NULL, NULL, NULL),
('00000015-0000-7000-8000-000000000004', 'scan', NULL, 'dead', 0, 'server', NULL, 3, '2026-01-07 00:00:00+00',
 NULL, NULL, NULL, NULL, 'library offline', 'scan:00000003-0000-7000-8000-000000000003'),
('00000015-0000-7000-8000-000000000005', 'reconcile', NULL, 'done', 0, 'server', NULL, 1, '2026-01-07 00:00:00+00',
 NULL, NULL, 1, convert_to('ok', 'UTF8'), NULL, 'cron:nightly:1767744000'),
('00000015-0000-7000-8000-000000000006', 'search', NULL, 'cancelled', 0, 'trusted_node',
 '00000014-0000-7000-8000-000000000001', 0, '2026-01-07 00:00:00+00', NULL, NULL, NULL, NULL, 'grant ended', NULL);
INSERT INTO job_schedules (name, cron, type, payload, next_run) VALUES
('nightly', '0 0 * * *', 'reconcile', NULL, '2026-01-08 00:00:00+00'),
('weekly-scan', '30 3 * * 1', 'scan', convert_to('00000003-0000-7000-8000-000000000003', 'UTF8'),
 '2026-01-12 03:30:00+00');

-- Since 0003 the users_audit trigger has chained an event for each account above; other events go through
-- audit_append.
SELECT audit_append('00000001-0000-7000-8000-000000000001', 'link.revoke',
                    '{"link": "0000000e-0000-7000-8000-000000000003"}', NULL);
SELECT audit_append('00000001-0000-7000-8000-000000000001', 'album.share',
                    '{"album": "0000000c-0000-7000-8000-000000000001"}',
                    '{"user": "00000001-0000-7000-8000-000000000003"}');

-- Ada makes Eli a viewer and deletes Fay's account, which awaits its purge; the trigger names her as the actor.
SELECT set_config('photolib.actor', '00000001-0000-7000-8000-000000000001', true);
UPDATE users SET role = 'viewer', quota_bytes = 0 WHERE id = '00000001-0000-7000-8000-000000000005';
UPDATE users SET status = 'deleted', purge_at = '2026-01-13 00:00:00+00'
WHERE id = '00000001-0000-7000-8000-000000000006';

-- The data directory and an S3 store; an intent in every state, and bytes that failed their hash.
INSERT INTO stores (name, id, created_at) VALUES
('local', '00000016-0000-7000-8000-000000000001', '2026-01-01 00:00:00+00'),
('b2', '00000016-0000-7000-8000-000000000002', '2026-01-02 00:00:00+00');
INSERT INTO file_intents (id, owner, kind, store, key, source, hash, size, state, created_at, finished_at) VALUES
('00000017-0000-7000-8000-000000000001', 7, 'put', 'local', '2024/05/IMG_0001.HEIC', '/var/tmp/upload-1',
 sha256('\x01'), 2400000, 'done', '2026-01-05 10:00:00+00', '2026-01-05 10:00:01+00'),
('00000017-0000-7000-8000-000000000002', 7, 'move', 'local', '2024/05/VID_0002.MOV', 'inbox/VID_0002.MOV',
 sha256('\x02'), 48000000, 'switched', '2026-01-05 10:01:00+00', NULL),
('00000017-0000-7000-8000-000000000003', 8, 'delete', 'b2', 'thumbs/old.webp', NULL, NULL, NULL, 'planned',
 '2026-01-05 10:02:00+00', NULL),
('00000017-0000-7000-8000-000000000004', 8, 'put', 'b2', '2019/08/PXL_0008.jpg', '/var/tmp/upload-2', sha256('\x08'),
 3000000, 'rolled_back', '2026-01-05 10:03:00+00', '2026-01-05 10:04:00+00');
INSERT INTO integrity_findings (id, store, key, detail, found_at) VALUES
('00000018-0000-7000-8000-000000000001', 'local', '2019/08/PXL_0008.jpg', 'blake3 differs from the recorded hash',
 '2026-01-06 00:02:00+00');

-- The private library lives on b2; an upload in progress into it, a complete one into Photos and an abandoned one.
UPDATE libraries SET store = 'b2' WHERE id = '00000003-0000-7000-8000-000000000002';
INSERT INTO uploads (id, owner_id, library_id, length, hash, received, store, key, completed_at, expires_at,
                     created_at) VALUES
('00000019-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000002', '00000003-0000-7000-8000-000000000002',
 10000000000, sha256('\x19'), 2516582400, NULL, NULL, NULL, '2026-01-08 10:00:00+00', '2026-01-07 09:00:00+00'),
('00000019-0000-7000-8000-000000000002', '00000001-0000-7000-8000-000000000001', '00000003-0000-7000-8000-000000000001',
 2400000, sha256('\x01'), 2400000, 'local',
 'libraries/00000003-0000-7000-8000-000000000001/uploads/00000019-0000-7000-8000-000000000002',
 '2026-01-07 09:05:00+00', '2026-01-08 09:05:00+00', '2026-01-07 09:04:00+00'),
('00000019-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000005', '00000003-0000-7000-8000-000000000001',
 48000000, sha256('\x02'), 0, NULL, NULL, NULL, '2026-01-02 00:00:00+00', '2026-01-01 00:00:00+00');

-- Deletions sync still delivers: a signed-out device and a tag taken off an asset leave tombstones through the
-- capture triggers; older tombstones were purged up to the horizon.
INSERT INTO devices (id, user_id, name, platform) VALUES
('00000002-0000-7000-8000-000000000003', '00000001-0000-7000-8000-000000000002', 'Old phone', 'ios');
INSERT INTO asset_tags (asset_id, tag_id) VALUES
('00000006-0000-7000-8000-000000000002', '0000000a-0000-7000-8000-000000000002');
DELETE FROM devices WHERE id = '00000002-0000-7000-8000-000000000003';
DELETE FROM asset_tags WHERE asset_id = '00000006-0000-7000-8000-000000000002';
INSERT INTO tombstone_horizon (txid) VALUES ('3');

-- photolib:drift
-- What years of use leave behind, loaded for the drifted case only. Duplicate hashes: the same bytes uploaded twice
-- into one library, and an e-mail address that differs only in case.
INSERT INTO assets (id, library_id, owner_id, original_filename, source, content_hash, media_kind) VALUES
('00000006-0000-7000-8000-000000000101', '00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001',
 'IMG_0001 copy.HEIC', 'upload', sha256('\x01'), 'image');
INSERT INTO asset_files (id, asset_id, role, storage, key, content_hash) VALUES
('00000008-0000-7000-8000-000000000101', '00000006-0000-7000-8000-000000000101', 'original', 'managed',
 '2024/05/IMG_0001 copy.HEIC', sha256('\x01'));
INSERT INTO users (id, handle, display_name, email) VALUES
('00000001-0000-7000-8000-000000000101', 'ada2', 'Ada', 'ADA@example.org');

-- Orphans: rows whose asset was deleted while triggers were off, and ids that no foreign key guards.
SET session_replication_role = replica;
INSERT INTO asset_files (id, asset_id, role, storage, key) VALUES
('00000008-0000-7000-8000-000000000102', '00000006-0000-7000-8000-0000000001ff', 'thumbnail', 'derived',
 'thumbs/00000006-0000-7000-8000-0000000001ff.webp');
INSERT INTO faces (id, asset_id, bbox, model_id) VALUES
('00000010-0000-7000-8000-000000000101', '00000006-0000-7000-8000-0000000001ff', '{0,0,1,1}', 'faces-v1');
INSERT INTO file_intents (id, owner, kind, store, key) VALUES
('00000017-0000-7000-8000-000000000101', 9, 'delete', 'removed', 'a.jpg');
RESET session_replication_role;
UPDATE memories SET asset_ids = asset_ids || '00000006-0000-7000-8000-0000000001ff'::uuid;
INSERT INTO audit_events (actor_user_id, action, hash) VALUES
('00000001-0000-7000-8000-0000000001ff', 'user.delete', sha256('\xa3'));

-- Indexes an administrator added by hand.
CREATE INDEX manual_assets_camera ON assets (make, model);
CREATE INDEX manual_users_email ON users (lower(email));

-- Settings left on the database and on the role in it.
DO $$BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'Pacific/Chatham');
    EXECUTE format('ALTER DATABASE %I SET datestyle = %L', current_database(), 'SQL, DMY');
    EXECUTE format('ALTER DATABASE %I SET photolib.legacy_mode = %L', current_database(), 'on');
    EXECUTE format('ALTER ROLE CURRENT_USER IN DATABASE %I SET intervalstyle = %L', current_database(), 'iso_8601');
    EXECUTE format('ALTER ROLE CURRENT_USER IN DATABASE %I SET work_mem = %L', current_database(), '1MB');
END$$;
