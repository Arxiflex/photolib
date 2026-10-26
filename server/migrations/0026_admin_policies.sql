-- The owner's answers on the admin console (photolib-design#376, ADR-0063).

-- When a type's pause began, kept while the pause is extended: a maintenance type stays paused at most 7 days in a row.
ALTER TABLE job_pauses ADD COLUMN since timestamptz NOT NULL DEFAULT now();

-- Uploads pause below the smaller of min_free_disk_percent and this many GB free on a filesystem they fill.
ALTER TABLE instance_settings ADD COLUMN min_free_disk_gb integer NOT NULL DEFAULT 20
CHECK (min_free_disk_gb BETWEEN 0 AND 100000);
