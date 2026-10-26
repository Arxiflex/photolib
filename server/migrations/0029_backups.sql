-- What the scheduled backups, their restore drills and the restores of the admin console did (ADR-0266): the console
-- shows the newest of each, and the metrics the newest that worked.
CREATE TABLE backup_runs (
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('backup', 'drill', 'restore')),
    store text NOT NULL,
    dump text NOT NULL,
    ok boolean NOT NULL,
    detail text NOT NULL,
    finished_at timestamptz NOT NULL DEFAULT now()
);
