-- Server policies (M2-40, ADR-0240): capability switches set for the server, an account or a library.

-- A switch set at one level: the server's when both ids are NULL. `pinned` marks the server's switches the
-- configuration file sets, which photolibd writes at every start. What decides is the pin, else the narrowest level
-- set: the library's, the account's, the server's; on when none is (`photolib_authz::policy`).
CREATE TABLE policy_switches (
    capability text NOT NULL CHECK (capability IN (
        'managed_libraries', 'uploads', 'folder_browser', 'device_folders', 'sharing', 'edits', 'deletes',
        'xmp_writes', 'face_recognition', 'ml_search'
    )),
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    library_id uuid REFERENCES libraries (id) ON DELETE CASCADE,
    enabled boolean NOT NULL,
    pinned boolean NOT NULL DEFAULT false,
    CHECK (user_id IS NULL OR library_id IS NULL),
    CHECK (NOT pinned OR (user_id IS NULL AND library_id IS NULL)),
    UNIQUE NULLS NOT DISTINCT (capability, user_id, library_id)
);

