-- Password login and sessions (M2-02, ADR-0052).

-- The OPAQUE registration record of an account (RFC 9807 §5.1.4): the client's public key, the masking key and the
-- envelope. Without the OPRF seed in the key file outside the database it checks no password guess. The credential
-- identifier is the account id and 16 random bytes, new for every password, so that setting a password never evaluates
-- the OPRF key of the one that signs in. ksf_params are the account's Argon2id parameters, which clients need before
-- they can sign in.
CREATE TABLE password_records (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    credential bytea NOT NULL,
    record bytea NOT NULL,
    ksf_params bytea NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- One-time tokens with which a person sets their own password; only their SHA-256 is stored.
CREATE TABLE password_setups (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    token_hash bytea NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL
);

-- The sessions of a device; only the SHA-256 of a token is stored. Deleting the device ends them.
CREATE TABLE sessions (
    id uuid PRIMARY KEY,
    device_id uuid NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
    token_hash bytea NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_device ON sessions (device_id);
