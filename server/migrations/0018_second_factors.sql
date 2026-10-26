-- Second factors (M2-05, ADR-0088): passkeys, TOTP and recovery codes.

-- WebAuthn credentials: the COSE public key as the authenticator gave it, and its signature counter. A credential id
-- is unique across accounts, so that nobody registers someone else's.
CREATE TABLE passkeys (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    credential_id bytea NOT NULL UNIQUE,
    public_key bytea NOT NULL,
    sign_count bigint NOT NULL DEFAULT 0,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz
);
CREATE INDEX passkeys_user ON passkeys (user_id);

-- An account's TOTP secret (RFC 6238), which checking a code needs in the clear, and the last time step a code counted
-- for, so that no code counts twice.
CREATE TABLE totp_secrets (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    secret bytea NOT NULL,
    last_step bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- The SHA-256 of an account's unused recovery codes, 80 random bits each; a code is deleted when it is used.
CREATE TABLE recovery_codes (
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    code_hash bytea NOT NULL,
    PRIMARY KEY (user_id, code_hash)
);
