-- API keys (M2-06, ADR-0055): credentials for scripts, the CLI and other programs, each scoped to some of its
-- account's actions, with an expiry, its last use and a rate of its own.
CREATE TABLE api_keys (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name text NOT NULL,
    -- SHA-256 of the secret, 256 random bits that are never stored.
    token_hash bytea NOT NULL UNIQUE,
    scopes text [] NOT NULL CHECK (
        cardinality(scopes) > 0
        AND scopes <@ ARRAY['view', 'download', 'contribute', 'edit', 'delete', 'share', 'manage_users']
    ),
    expires_at timestamptz NOT NULL,
    requests_per_minute integer NOT NULL CHECK (requests_per_minute BETWEEN 1 AND 60000),
    -- To the minute, so that a busy key does not write on every request.
    last_used_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX api_keys_user ON api_keys (user_id);
