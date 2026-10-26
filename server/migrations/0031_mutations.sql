-- Mutations (M2-16, ADR-0265): what devices' outboxes sent, each applied at most once, and the hybrid logical clock of
-- each user field's and album membership's last change, so that offline edits merge by their latest edit.

-- The mutations applied for each account, kept 30 days so that a device's retries apply none twice; `rejected` is the
-- reason of one refused for good.
CREATE TABLE processed_mutations (
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    mutation_id uuid NOT NULL,
    rejected text,
    processed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, mutation_id)
);
CREATE INDEX processed_mutations_age ON processed_mutations (processed_at);

-- The clock of each field's last edit, as assets.field_hlc has it.
ALTER TABLE asset_user_state ADD COLUMN field_hlc jsonb NOT NULL DEFAULT '{}';
ALTER TABLE album_items ADD COLUMN field_hlc jsonb NOT NULL DEFAULT '{}';

-- Each asset's item in an album as its mutations left it: whether the latest add or removal kept it, its place in
-- the custom order and the clock of each, which outlive a removed item; album_items holds those present.
CREATE TABLE album_item_states (
    id uuid PRIMARY KEY,
    album_id uuid NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
    present boolean NOT NULL,
    sort_key text,
    field_hlc jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX album_item_states_album ON album_item_states (album_id);
CREATE INDEX album_item_states_asset ON album_item_states (asset_id);
