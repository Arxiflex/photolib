-- Private mode's keys (M6-02, ADR-0255). An account's identity log starts at `user_keys.key_bundle`; here are the seeds
-- of its identity keys, wrapped under its account master key (AMK), and the AMK wrapped once per way in. The server
-- reads only their headers. `recovery_verified_at` is when the person last proved they hold the recovery kit.
CREATE TABLE account_keys (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    amk_id bytea NOT NULL CHECK (length(amk_id) = 16),
    signing_key bytea NOT NULL CHECK (length(signing_key) = 144),
    decryption_key bytea NOT NULL CHECK (length(decryption_key) = 144),
    recovery_verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- The AMK wrapped under the key of the password, with its Argon2id parameters, or of the recovery kit.
CREATE TABLE unlock_paths (
    user_id uuid NOT NULL REFERENCES account_keys (user_id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('password', 'recovery')),
    wrap bytea NOT NULL CHECK (length(wrap) = 144),
    params bytea CHECK (length(params) = 26),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, kind),
    CHECK ((kind = 'password') = (params IS NOT NULL))
);
