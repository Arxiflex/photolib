-- Resumable uploads (ADR-0061): bytes are staged in work_dir; a complete upload is verified and written to its
-- library's store before it is acknowledged.

-- The store a library's files live in (ADR-0022 point 2).
ALTER TABLE libraries ADD COLUMN store text NOT NULL DEFAULT 'local';

CREATE TABLE uploads (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    library_id uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    length bigint NOT NULL CHECK (length >= 0),
    -- The BLAKE3 hash the client announced: the upload completes only with bytes that have it.
    hash bytea NOT NULL CHECK (length(hash) = 32),
    -- The bytes staged and fsynced so far.
    received bigint NOT NULL DEFAULT 0 CHECK (received BETWEEN 0 AND length),
    -- Where the verified bytes were written when the upload completed.
    store text,
    key text,
    completed_at timestamptz,
    -- An incomplete upload expires a day after its last append.
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX uploads_owner ON uploads (owner_id);
CREATE INDEX uploads_library ON uploads (library_id);
CREATE INDEX uploads_expiry ON uploads (expires_at) WHERE completed_at IS NULL;
