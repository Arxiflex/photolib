-- The admin console (M2-32, ADR-0063): paused job types and the instance's policies.

-- Workers lease no job of `type` before `until`; the pause then ends by itself.
CREATE TABLE job_pauses (
    type text PRIMARY KEY,
    until timestamptz NOT NULL,
    paused_by uuid REFERENCES users (id) ON DELETE SET NULL
);

-- Policies and defaults of the instance (OPS-20, OPS-23), one row, edited in the admin console.
CREATE TABLE instance_settings (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    require_two_factor boolean NOT NULL DEFAULT false,
    face_recognition_default boolean NOT NULL DEFAULT false,
    trash_retention_days integer NOT NULL DEFAULT 60 CHECK (trash_retention_days BETWEEN 1 AND 3650),
    min_free_disk_percent integer NOT NULL DEFAULT 5 CHECK (min_free_disk_percent BETWEEN 0 AND 50)
);
INSERT INTO instance_settings DEFAULT VALUES;

-- An administrator's API key may run the server too, but never pause maintenance (ADR-0063). The check only widens.
-- squawk-ignore-file ban-drop-constraint, constraint-missing-not-valid
ALTER TABLE api_keys DROP CONSTRAINT api_keys_scopes_check,
ADD CONSTRAINT api_keys_scopes_check CHECK (
    cardinality(scopes) > 0
    AND scopes <@ ARRAY['view', 'download', 'contribute', 'edit', 'delete', 'share', 'manage_users', 'manage_server']
);
