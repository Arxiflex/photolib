-- OpenID Connect sign-in (M2-04, ADR-0087): the identities providers vouch for, each linked to one account, which may
-- have several. An identity is its issuer and subject (OpenID Connect Core §2), never its email.
CREATE TABLE oidc_identities (
    issuer text NOT NULL,
    subject text NOT NULL,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (issuer, subject)
);
CREATE INDEX oidc_identities_user ON oidc_identities (user_id);
