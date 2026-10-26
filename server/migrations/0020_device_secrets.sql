-- Device secrets and the rotation grace of sessions (ADR-0052, as the owner answered photolib-design#370).

-- The SHA-256 of the secret a device's last sign-in gave it: at StartLogin it proves the device, whose attempts then
-- count apart from everyone else's.
ALTER TABLE devices ADD COLUMN secret_hash bytea;

-- The token a session had before RotateSession: it keeps working until the new one is first used, or until
-- previous_expires_at, 24 hours after the rotation, so that a lost response signs no device out.
ALTER TABLE sessions ADD COLUMN previous_token_hash bytea, ADD COLUMN previous_expires_at timestamptz;
-- Only rotated sessions have one, and few devices have sessions: the build is quick, and the upgrade runs before
-- anything is served. Tokens are random, so it need not be unique.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX sessions_previous_token ON sessions (previous_token_hash) WHERE previous_token_hash IS NOT NULL;
