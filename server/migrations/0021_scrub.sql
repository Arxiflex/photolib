-- Integrity scrubbing and the backup watchdog (M2-33, ADR-0234).

-- What a finding is: bytes that read otherwise than recorded (`content`, as every finding before), an object that is
-- gone (`missing`), has another size (`size`) or carries another hash (`hash`), or one under a library that no file
-- names (`orphan`). A finding is resolved once a scrub finds the object as recorded again.
ALTER TABLE integrity_findings
ADD COLUMN kind text NOT NULL DEFAULT 'content' CHECK (kind IN ('content', 'missing', 'size', 'hash', 'orphan')),
ADD COLUMN resolved_at timestamptz;
-- The table holds a few rows, if any, so this takes no time.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX integrity_findings_open ON integrity_findings (store, key) WHERE resolved_at IS NULL;

-- Which file names an object, for the scrub's orphans. Built while photolibd upgrades, before it serves anything:
-- seconds for a million files.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX asset_files_key ON asset_files (storage, key);

-- Each store's scrub: the last file its routine cycle checked and the last one its full re-hash read, in id order, the
-- bytes a cycle covers, when it last ran and last ended, and what the re-hash downloaded in the month of `egress_month`.
CREATE TABLE scrubs (
    store text PRIMARY KEY,
    checked_after uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
    read_after uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
    cycle_bytes bigint NOT NULL DEFAULT 0,
    ran_at timestamptz NOT NULL DEFAULT now(),
    cycle_ended_at timestamptz,
    egress_month date NOT NULL DEFAULT '2000-01-01',
    egress_bytes bigint NOT NULL DEFAULT 0
);

-- Each device's last backup report (ING-26): when, and how many items it still had to back up then.
CREATE TABLE device_backups (
    device_id uuid PRIMARY KEY REFERENCES devices (id) ON DELETE CASCADE,
    reported_at timestamptz NOT NULL DEFAULT now(),
    pending bigint NOT NULL CHECK (pending >= 0)
);

-- The days in which the scrub checks every file once, and the hours without a report after which a device's backup
-- counts as silent.
ALTER TABLE instance_settings
ADD COLUMN scrub_days integer NOT NULL DEFAULT 90 CHECK (scrub_days BETWEEN 1 AND 3650),
ADD COLUMN backup_silent_hours integer NOT NULL DEFAULT 48 CHECK (backup_silent_hours BETWEEN 1 AND 8760);
