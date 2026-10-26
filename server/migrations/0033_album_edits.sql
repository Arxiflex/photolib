-- Organisation v1 (M2-26, ORG-17). A device creates an album under its own UUID with a field edit, and sets an
-- account's own visibility of an album or a library; each field keeps the value of its latest edit by hybrid logical
-- clock, as assets' do.
ALTER TABLE albums ADD COLUMN field_hlc jsonb NOT NULL DEFAULT '{}';
ALTER TABLE album_user_state ADD COLUMN field_hlc jsonb NOT NULL DEFAULT '{}';
ALTER TABLE library_user_state ADD COLUMN field_hlc jsonb NOT NULL DEFAULT '{}';

-- What the albums an account hides do to an asset, kept on the account's own state of the asset so that the timeline
-- and memories never join albums: the asset is in at least one album the account hides from the timeline or from
-- memories. Written only by the triggers below.
ALTER TABLE asset_user_state ADD COLUMN album_hides_timeline boolean NOT NULL DEFAULT false;
ALTER TABLE asset_user_state ADD COLUMN album_hides_memories boolean NOT NULL DEFAULT false;

-- Recomputes both columns of `who`'s state of each of `assets`; a state row exists only for an asset hidden or
-- otherwise kept.
CREATE FUNCTION photolib_refresh_hiding(who uuid, assets uuid[]) RETURNS void LANGUAGE sql AS $$
    WITH wanted AS (
        SELECT a AS asset_id,
            coalesce((SELECT bool_or(s.hide_from_timeline) FROM album_items i
                JOIN album_user_state s ON s.album_id = i.album_id AND s.user_id = who
                WHERE i.asset_id = a), false) AS timeline,
            coalesce((SELECT bool_or(s.hide_from_memories) FROM album_items i
                JOIN album_user_state s ON s.album_id = i.album_id AND s.user_id = who
                WHERE i.asset_id = a), false) AS memories
        FROM unnest(assets) AS a
    ), changed AS (
        UPDATE asset_user_state u SET album_hides_timeline = w.timeline, album_hides_memories = w.memories
        FROM wanted w WHERE u.user_id = who AND u.asset_id = w.asset_id
            AND (u.album_hides_timeline, u.album_hides_memories) IS DISTINCT FROM (w.timeline, w.memories)
    )
    INSERT INTO asset_user_state (user_id, asset_id, album_hides_timeline, album_hides_memories)
    SELECT who, w.asset_id, w.timeline, w.memories FROM wanted w
    WHERE (w.timeline OR w.memories) AND EXISTS (SELECT FROM assets WHERE id = w.asset_id)
        AND NOT EXISTS (SELECT FROM asset_user_state u WHERE u.user_id = who AND u.asset_id = w.asset_id)
$$;

-- A change of an account's hiding of an album reaches the assets in it.
CREATE FUNCTION photolib_album_hidden() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    state album_user_state := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
BEGIN
    PERFORM photolib_refresh_hiding(state.user_id,
        ARRAY(SELECT asset_id FROM album_items WHERE album_id = state.album_id AND asset_id IS NOT NULL));
    RETURN NULL;
END $$;
CREATE TRIGGER album_user_state_hiding AFTER INSERT OR DELETE OR UPDATE OF hide_from_timeline, hide_from_memories
    ON album_user_state FOR EACH ROW EXECUTE FUNCTION photolib_album_hidden();

-- An asset added to or taken out of an album takes on, or loses, what the album's viewers hide.
CREATE FUNCTION photolib_item_hidden() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    item album_items := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    who uuid;
BEGIN
    IF item.asset_id IS NOT NULL THEN
        FOR who IN SELECT user_id FROM album_user_state WHERE album_id = item.album_id LOOP
            PERFORM photolib_refresh_hiding(who, ARRAY[item.asset_id]);
        END LOOP;
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER album_items_hiding AFTER INSERT OR DELETE ON album_items
    FOR EACH ROW EXECUTE FUNCTION photolib_item_hidden();

-- An album that goes first lets go of what its viewers hid, while its items are still there to find.
CREATE FUNCTION photolib_album_gone() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM album_user_state WHERE album_id = OLD.id;
    RETURN OLD;
END $$;
CREATE TRIGGER albums_hiding BEFORE DELETE ON albums FOR EACH ROW EXECUTE FUNCTION photolib_album_gone();
