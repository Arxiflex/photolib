-- Change capture for sync (photolib-design docs/05-sync-and-offline.md §2, ADR-0053). Every write stamps the row with
-- its transaction id and every delete leaves a tombstone, so a reader that returns only changes below the watermark
-- pg_snapshot_xmin(pg_current_snapshot()) never skips one, whatever order transactions commit in.
-- The arguments of each sync_capture trigger are the scope column ('' for shared rows) and the key columns;
-- photolib_db::sync::ENTITIES mirrors them, and a test fails on a table that is neither captured nor listed as local.
-- No release predates this migration, so the tables it indexes are empty wherever it runs.
-- squawk-ignore-file require-concurrent-index-creation

-- At most one per key: inserting a key again removes its tombstone.
CREATE TABLE tombstones (
    entity text NOT NULL,
    key jsonb NOT NULL,
    scope uuid,
    txid xid8 NOT NULL,
    deleted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (entity, key)
);
CREATE INDEX tombstones_txid ON tombstones (scope, txid);

-- The newest txid among purged tombstones: a cursor at or below it may have missed a deletion.
CREATE TABLE tombstone_horizon (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    txid xid8 NOT NULL
);

CREATE FUNCTION sync_capture() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    old_key jsonb;
    new_key jsonb;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT jsonb_object_agg(k, r -> k) INTO old_key FROM to_jsonb(OLD) AS r, unnest(TG_ARGV[1:]) AS k;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        NEW.txid := pg_current_xact_id();
        SELECT jsonb_object_agg(k, r -> k) INTO new_key FROM to_jsonb(NEW) AS r, unnest(TG_ARGV[1:]) AS k;
    END IF;
    IF old_key IS DISTINCT FROM new_key THEN
        DELETE FROM tombstones WHERE entity = TG_TABLE_NAME AND key = new_key;
        INSERT INTO tombstones (entity, key, scope, txid)
        SELECT TG_TABLE_NAME, old_key, (to_jsonb(OLD) ->> TG_ARGV[0])::uuid, pg_current_xact_id()
        WHERE old_key IS NOT NULL
        ON CONFLICT (entity, key) DO UPDATE
        SET scope = excluded.scope, txid = excluded.txid, deleted_at = excluded.deleted_at;
    END IF;
    RETURN coalesce(NEW, OLD);
END $$;

-- The account stream: scope is the user. The audit of 0003 ignores txid, which every write changes.
CREATE OR REPLACE FUNCTION audit_users() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    old_row jsonb := to_jsonb(OLD) - 'txid';
    new_row jsonb := to_jsonb(NEW) - 'txid';
BEGIN
    IF old_row = new_row THEN
        RETURN NULL;
    END IF;
    PERFORM audit_append(
        nullif(current_setting('photolib.actor', true), '')::uuid,
        CASE TG_OP WHEN 'INSERT' THEN 'user.create' WHEN 'UPDATE' THEN 'user.update' ELSE 'user.purge' END,
        jsonb_build_object('user_id', coalesce(new_row, old_row) -> 'id'),
        (
            SELECT jsonb_build_object('fields', coalesce(jsonb_agg(key ORDER BY key), '[]'))
                || coalesce(jsonb_object_agg(key, value) FILTER (
                    WHERE key NOT IN ('handle', 'display_name', 'email')
                ), '{}')
            FROM jsonb_each(new_row)
            WHERE key NOT IN ('id', 'created_at') AND (old_row -> key) IS DISTINCT FROM value
        )
    );
    RETURN NULL;
END
$$;
ALTER TABLE users ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION sync_capture('id', 'id');
ALTER TABLE user_keys ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON user_keys
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'user_id');
ALTER TABLE devices ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX devices_txid ON devices (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON devices
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'id');
ALTER TABLE processing_grants ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX processing_grants_txid ON processing_grants (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON processing_grants
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'id');
ALTER TABLE user_places ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX user_places_txid ON user_places (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON user_places
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'id');
ALTER TABLE asset_user_state ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_user_state_txid ON asset_user_state (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_user_state
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'user_id', 'asset_id');
ALTER TABLE album_user_state ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX album_user_state_txid ON album_user_state (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON album_user_state
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'user_id', 'album_id');
ALTER TABLE library_user_state ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX library_user_state_txid ON library_user_state (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON library_user_state
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'user_id', 'library_id');

-- Libraries: an owner sees its libraries, a member its memberships; library content is scoped by the library.
ALTER TABLE libraries ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX libraries_txid ON libraries (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON libraries
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');
ALTER TABLE library_members ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX library_members_txid ON library_members (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON library_members
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'library_id', 'user_id');
ALTER TABLE custom_fields ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX custom_fields_txid ON custom_fields (library_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON custom_fields
FOR EACH ROW EXECUTE FUNCTION sync_capture('library_id', 'id');
ALTER TABLE assets ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX assets_txid ON assets (library_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON assets
FOR EACH ROW EXECUTE FUNCTION sync_capture('library_id', 'id');
ALTER TABLE stacks ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX stacks_txid ON stacks (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON stacks
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');

-- What hangs off an asset is scoped by the asset.
ALTER TABLE asset_files ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_files_txid ON asset_files (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_files
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'id');
ALTER TABLE versions ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX versions_txid ON versions (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON versions
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'id');
ALTER TABLE asset_custom_values ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_custom_values_txid ON asset_custom_values (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_custom_values
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'field_id');
ALTER TABLE asset_embeddings ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_embeddings_txid ON asset_embeddings (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_embeddings
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'model_id');
ALTER TABLE asset_ocr ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_ocr_txid ON asset_ocr (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_ocr
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'model_id');
ALTER TABLE asset_quality ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_quality_txid ON asset_quality (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_quality
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'model_id');
ALTER TABLE asset_ml_labels ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_ml_labels_txid ON asset_ml_labels (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_ml_labels
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'label_id', 'model_id');
ALTER TABLE asset_tags ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX asset_tags_txid ON asset_tags (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON asset_tags
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'asset_id', 'tag_id');
ALTER TABLE faces ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX faces_txid ON faces (asset_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON faces
FOR EACH ROW EXECUTE FUNCTION sync_capture('asset_id', 'id');

-- Albums: an owner sees its folders, albums and links, a member its memberships; items are scoped by the album.
ALTER TABLE album_folders ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX album_folders_txid ON album_folders (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON album_folders
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');
ALTER TABLE albums ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX albums_txid ON albums (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON albums
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');
ALTER TABLE album_members ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX album_members_txid ON album_members (user_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON album_members
FOR EACH ROW EXECUTE FUNCTION sync_capture('user_id', 'album_id', 'user_id');
ALTER TABLE links ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX links_txid ON links (album_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON links
FOR EACH ROW EXECUTE FUNCTION sync_capture('album_id', 'id');
ALTER TABLE album_items ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX album_items_txid ON album_items (album_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON album_items
FOR EACH ROW EXECUTE FUNCTION sync_capture('album_id', 'id');

-- Partner shares are scoped by the partner who sees the owner's assets.
ALTER TABLE partner_shares ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX partner_shares_txid ON partner_shares (partner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON partner_shares
FOR EACH ROW EXECUTE FUNCTION sync_capture('partner_id', 'owner_id', 'partner_id');

-- Organisation, scoped by its owner; face constraints by their face.
ALTER TABLE tags ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX tags_txid ON tags (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON tags
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');
ALTER TABLE persons ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX persons_txid ON persons (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON persons
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');
ALTER TABLE face_constraints ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX face_constraints_txid ON face_constraints (face_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON face_constraints
FOR EACH ROW EXECUTE FUNCTION sync_capture('face_id', 'id');
ALTER TABLE memories ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX memories_txid ON memories (owner_id, txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON memories
FOR EACH ROW EXECUTE FUNCTION sync_capture('owner_id', 'id');

-- Shared vocabularies every client needs.
ALTER TABLE places ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX places_txid ON places (txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON places
FOR EACH ROW EXECUTE FUNCTION sync_capture('', 'id');
ALTER TABLE ml_labels ADD COLUMN txid xid8 NOT NULL DEFAULT pg_current_xact_id();
CREATE INDEX ml_labels_txid ON ml_labels (txid);
CREATE TRIGGER sync_capture BEFORE INSERT OR UPDATE OR DELETE ON ml_labels
FOR EACH ROW EXECUTE FUNCTION sync_capture('', 'id');
