-- Events, the events API and webhooks (M9-04, ADR-0263).

-- What happened to an asset, as ids only: a hint for integrations, never its content. Readers take events below the
-- sync watermark in (txid, id) order, so a cursor never skips one whatever order transactions commit in. No foreign
-- keys: a deletion's event outlives its asset and library, and the `events` job purges what is a week old.
CREATE TABLE events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    txid xid8 NOT NULL DEFAULT pg_current_xact_id(),
    at timestamptz NOT NULL DEFAULT now(),
    type text NOT NULL CHECK (type IN ('asset.created', 'asset.trashed', 'asset.restored', 'asset.deleted')),
    library_id uuid NOT NULL,
    asset_id uuid NOT NULL
);
CREATE INDEX events_order ON events (txid, id);
CREATE INDEX events_at ON events (at);

-- Every writer of assets records its events, whatever path it takes.
CREATE FUNCTION asset_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    a assets := coalesce(NEW, OLD);
BEGIN
    INSERT INTO events (type, library_id, asset_id) VALUES (
        CASE
            WHEN TG_OP = 'INSERT' THEN 'asset.created'
            WHEN TG_OP = 'DELETE' THEN 'asset.deleted'
            WHEN NEW.trashed_at IS NULL THEN 'asset.restored'
            ELSE 'asset.trashed'
        END,
        a.library_id,
        a.id
    );
    RETURN NULL;
END $$;
CREATE TRIGGER asset_events AFTER INSERT OR DELETE ON assets
FOR EACH ROW EXECUTE FUNCTION asset_event();
CREATE TRIGGER asset_trash_events AFTER UPDATE OF trashed_at ON assets
FOR EACH ROW WHEN ((OLD.trashed_at IS NULL) <> (NEW.trashed_at IS NULL)) EXECUTE FUNCTION asset_event();

-- An account's webhooks: the URL, the signing secret and the last event delivered, in the events' order. A new one
-- starts after what had committed; `failing_since` and `last_status` (0 without an answer) say why it waits.
CREATE TABLE webhooks (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    url text NOT NULL,
    secret bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    after_txid xid8 NOT NULL DEFAULT pg_snapshot_xmin(pg_current_snapshot()),
    after_id bigint NOT NULL DEFAULT 0,
    delivered_at timestamptz,
    failing_since timestamptz,
    last_status integer
);
CREATE INDEX webhooks_owner ON webhooks (owner_id);
