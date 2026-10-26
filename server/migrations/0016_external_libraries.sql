-- External libraries (photolib-design docs/07 §4, ADR-0093): scans checkpointed by folder, and the files they found.

-- A scan: one `scan` job per folder, of which `pending` are not listed yet; it is over at 0. One runs per library.
CREATE TABLE library_scans (
    id uuid PRIMARY KEY,
    library_id uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    pending integer NOT NULL CHECK (pending >= 0),
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);
CREATE UNIQUE INDEX library_scans_running ON library_scans (library_id) WHERE finished_at IS NULL;

-- Every regular file a scan found under a library's root, by folder (`dir`, '' at the root) and name, with the
-- identity it has until it is hashed. It is `pending` until ingest reads it, then `ingested` into `asset_id`,
-- `unsupported` (not media) or `failed` for the reason in `error`.
CREATE TABLE library_files (
    library_id uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    dir text NOT NULL,
    name text NOT NULL,
    dev bigint NOT NULL,
    inode bigint NOT NULL,
    size bigint NOT NULL,
    mtime_ns bigint NOT NULL,
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'ingested', 'unsupported', 'failed')),
    asset_id uuid REFERENCES assets (id) ON DELETE SET NULL,
    error text,
    PRIMARY KEY (library_id, dir, name)
);
CREATE INDEX library_files_asset ON library_files (asset_id);

-- The head of each type's queue in lease order, so that a type is leased without reading another's backlog, such as
-- the hash jobs of a library behind its two million thumbnails. No release has run external libraries yet, so the
-- queue is small and this build is quick.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX jobs_queued ON jobs (type, priority DESC, run_after, id) WHERE status = 'queued';
