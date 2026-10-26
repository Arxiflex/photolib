-- Blob stores and the intent log of journaled file operations (photolib-design docs/07 §6, ADR-0022, ADR-0041).

-- A store's `.photolib/store.json` names the instance and the id here; a store that does not match is offline.
CREATE TABLE stores (
    name text PRIMARY KEY,
    id uuid NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- One row per multi-step file operation: a put writes `key` from the staged file `source`, a move copies `source` to
-- `key`, a delete removes `key`. Recovery rolls back a planned intent and completes a switched one, and takes an
-- intent over only when its process no longer holds the advisory lock `owner`.
CREATE TABLE file_intents (
    id uuid PRIMARY KEY,
    owner bigint NOT NULL,
    kind text NOT NULL CHECK (kind IN ('put', 'move', 'delete')),
    store text NOT NULL REFERENCES stores (name),
    key text NOT NULL,
    source text,
    hash bytea,
    size bigint,
    state text NOT NULL DEFAULT 'planned' CHECK (state IN ('planned', 'switched', 'done', 'rolled_back')),
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);
-- An open intent reserves its key in its store.
CREATE UNIQUE INDEX file_intents_reserved ON file_intents (store, key) WHERE state IN ('planned', 'switched');
CREATE INDEX file_intents_open ON file_intents (owner) WHERE state IN ('planned', 'switched');

-- Bytes that did not match their recorded hash when read; the job that read them failed.
CREATE TABLE integrity_findings (
    id uuid PRIMARY KEY,
    store text NOT NULL,
    key text NOT NULL,
    detail text NOT NULL,
    found_at timestamptz NOT NULL DEFAULT now()
);
