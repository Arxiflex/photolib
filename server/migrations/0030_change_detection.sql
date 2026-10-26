-- Change detection of external libraries (photolib-design docs/07 §4, ADR-0257): files that move keep their rows,
-- files a scan does not find turn missing under the mass-disappearance guard, and an offline root changes nothing.

-- A file a scan no longer finds (deleted, moved out or excluded) is missing since then until it is found again;
-- `unseen` is the last scan whose listing of its folder lacked it, `found_at` when it was found or last moved.
ALTER TABLE library_files ADD COLUMN missing_since timestamptz;
ALTER TABLE library_files ADD COLUMN unseen uuid;
ALTER TABLE library_files ADD COLUMN found_at timestamptz NOT NULL DEFAULT now();
-- A file that moved is found by its inode. No release has run external libraries yet, so the table is small.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX library_files_inode ON library_files (library_id, inode);

-- The folders a scan listed, or `skipped` as unreadable (what lies under them stays as it was), until the next scan:
-- the files of folders it never reached are missing.
CREATE TABLE scan_dirs (
    scan_id uuid NOT NULL REFERENCES library_scans (id) ON DELETE CASCADE,
    dir text NOT NULL,
    skipped boolean NOT NULL DEFAULT false,
    PRIMARY KEY (scan_id, dir)
);

-- How many assets a scan found missing; `held` while hiding them waits for an administrator's confirmation.
ALTER TABLE library_scans ADD COLUMN missing integer;
ALTER TABLE library_scans ADD COLUMN held boolean NOT NULL DEFAULT false;

-- The names at the root of an external library at its last scan, which a root must still hold to be its own; and how
-- many of its folders no watch covers, polled instead (NULL: no watcher has looked).
ALTER TABLE libraries ADD COLUMN fingerprint text [];
ALTER TABLE libraries ADD COLUMN unwatched integer;
