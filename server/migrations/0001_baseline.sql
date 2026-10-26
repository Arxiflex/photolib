-- The baseline: every entity of the domain model (photolib-design docs/04-domain-model.md), including those whose
-- features arrive later. Ids are UUIDv7 made by whoever creates the row; enumerations are text with a CHECK.

-- The instance marker: photolibd creates it on a first start, before migrating (see pg.rs); this takes it over.
CREATE TABLE IF NOT EXISTS photolib_instance (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    instance_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users, devices and libraries (§3)

CREATE TABLE users (
    id uuid PRIMARY KEY,
    handle text NOT NULL UNIQUE,
    display_name text NOT NULL,
    email text UNIQUE,
    role text NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'invited')),
    quota_bytes bigint,
    locale text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- The public key bundle of a user's end-to-end encryption identity.
CREATE TABLE user_keys (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    key_bundle bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name text NOT NULL,
    platform text NOT NULL,
    app_version text,
    capabilities text [] NOT NULL DEFAULT '{}',
    device_public_key bytea,
    last_seen_at timestamptz,
    is_trusted_node boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_user ON devices (user_id);

CREATE TABLE libraries (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id),
    name text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('managed', 'external')),
    privacy text NOT NULL DEFAULT 'standard' CHECK (privacy IN ('standard', 'private')),
    access text NOT NULL DEFAULT 'rw' CHECK (access IN ('ro', 'rw')),
    root_uri text NOT NULL,
    is_upload_target boolean NOT NULL DEFAULT false,
    storage_template text,
    scan_policy jsonb,
    state text NOT NULL DEFAULT 'online' CHECK (state IN ('online', 'offline', 'scanning', 'error')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT external_libraries_are_standard CHECK (kind = 'managed' OR privacy = 'standard')
);
CREATE INDEX libraries_owner ON libraries (owner_id);

CREATE TABLE library_members (
    library_id uuid REFERENCES libraries (id) ON DELETE CASCADE,
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('viewer', 'contributor', 'editor')),
    PRIMARY KEY (library_id, user_id)
);

-- Places (§8): an offline reverse-geocoding hierarchy with localised names.
CREATE TABLE places (
    id uuid PRIMARY KEY,
    parent_id uuid REFERENCES places (id),
    level text NOT NULL CHECK (level IN ('country', 'region', 'district', 'city', 'poi')),
    names jsonb NOT NULL,
    lat double precision,
    lon double precision
);
CREATE INDEX places_parent ON places (parent_id);

-- Assets (§4)

CREATE TABLE stacks (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('burst', 'similar_series', 'raw_jpeg', 'bracket', 'manual')),
    cover_asset_id uuid,
    origin text NOT NULL CHECK (origin IN ('camera', 'auto', 'user')),
    review_state text NOT NULL DEFAULT 'unreviewed' CHECK (review_state IN ('unreviewed', 'reviewed')),
    ranking jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- In private libraries the server sees only ids, sizes and dates of upload and trash; the rest is in the meta_*
-- ciphertexts (§9).
CREATE TABLE assets (
    id uuid PRIMARY KEY,
    library_id uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    owner_id uuid NOT NULL REFERENCES users (id),
    original_filename text,
    source text NOT NULL CHECK (source IN ('upload', 'scan', 'import', 'edit_copy')),
    source_ref text,
    created_at timestamptz NOT NULL DEFAULT now(),
    content_hash bytea,
    media_kind text CHECK (media_kind IN ('image', 'video')),
    facets text [] NOT NULL DEFAULT '{}',
    -- The capture time as the camera showed it, without a zone; taken_utc is derived from it.
    -- squawk-ignore prefer-timestamp-tz
    taken_local timestamp,
    tz_offset_min integer,
    tz_name text,
    taken_utc timestamptz,
    time_source text NOT NULL DEFAULT 'unknown',
    time_confidence smallint CHECK (time_confidence BETWEEN 0 AND 100),
    time_precision text CHECK (time_precision IN ('year', 'month', 'day', 'minute', 'second', 'ms')),
    tz_assumed boolean NOT NULL DEFAULT false,
    lat double precision,
    lon double precision,
    alt double precision,
    accuracy_m real,
    location_source text CHECK (location_source IN ('exif', 'sidecar', 'user', 'import', 'estimated')),
    place_id uuid REFERENCES places (id),
    width integer,
    height integer,
    orientation smallint,
    duration_ms bigint,
    fps real,
    codec text,
    bitrate bigint,
    color jsonb,
    file_size_total bigint,
    make text,
    model text,
    lens text,
    focal_mm real,
    focal_35mm real,
    f_number real,
    exposure_s real,
    iso integer,
    flash text,
    software text,
    raw_metadata jsonb,
    title text,
    description text,
    rating smallint NOT NULL DEFAULT 0 CHECK (rating BETWEEN -1 AND 5),
    color_label text,
    archived boolean NOT NULL DEFAULT false,
    locked boolean NOT NULL DEFAULT false,
    trashed_at timestamptz,
    field_hlc jsonb NOT NULL DEFAULT '{}', -- the hybrid-logical-clock time of each user field's last edit
    rights jsonb, -- creator, copyright, licence and usage terms
    stack_id uuid REFERENCES stacks (id) ON DELETE SET NULL,
    stack_order integer,
    current_version_id uuid,
    meta_core bytea,
    meta_user bytea,
    meta_ml bytea
);
CREATE INDEX assets_timeline ON assets (library_id, taken_utc);
CREATE INDEX assets_owner ON assets (owner_id);
CREATE INDEX assets_content_hash ON assets (library_id, content_hash);
CREATE INDEX assets_stack ON assets (stack_id);
ALTER TABLE stacks ADD CONSTRAINT stacks_cover_asset_id_fkey
FOREIGN KEY (cover_asset_id) REFERENCES assets (id) ON DELETE SET NULL;

-- Typed custom fields defined per library.
CREATE TABLE custom_fields (
    id uuid PRIMARY KEY,
    library_id uuid NOT NULL REFERENCES libraries (id) ON DELETE CASCADE,
    name text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('text', 'number', 'date', 'enum')),
    options jsonb,
    UNIQUE (library_id, name)
);

CREATE TABLE asset_custom_values (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    field_id uuid REFERENCES custom_fields (id) ON DELETE CASCADE,
    value jsonb NOT NULL,
    PRIMARY KEY (asset_id, field_id)
);

-- Originals, sidecars and renditions; `role` is a file role of photolib-design docs/08-media-pipeline.md §4.
CREATE TABLE asset_files (
    id uuid PRIMARY KEY,
    asset_id uuid NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
    role text NOT NULL,
    storage text NOT NULL,
    key text NOT NULL,
    mime text,
    size bigint,
    content_hash bytea,
    state text NOT NULL DEFAULT 'present'
    CHECK (state IN ('present', 'missing', 'offline', 'pending_upload', 'integrity_error')),
    crypto_header bytea,
    render_spec jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX asset_files_asset ON asset_files (asset_id);

-- The immutable edit history; reverting moves assets.current_version_id.
CREATE TABLE versions (
    id uuid PRIMARY KEY,
    asset_id uuid NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
    parent_id uuid REFERENCES versions (id),
    kind text NOT NULL CHECK (kind IN ('original', 'edit', 'external_change', 'import_variant')),
    origin text,
    label text,
    batch_id uuid,
    recipe_hash bytea,
    process_version text,
    content_key bytea,
    base_missing boolean NOT NULL DEFAULT false,
    recipe bytea,
    render_file_id uuid REFERENCES asset_files (id) ON DELETE SET NULL,
    created_by_device uuid REFERENCES devices (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    note text
);
CREATE INDEX versions_asset ON versions (asset_id);
ALTER TABLE assets ADD CONSTRAINT assets_current_version_id_fkey
FOREIGN KEY (current_version_id) REFERENCES versions (id);

-- What each viewer of a shared asset keeps to themselves.
CREATE TABLE asset_user_state (
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    favorite boolean NOT NULL DEFAULT false,
    hidden_from_memories boolean NOT NULL DEFAULT false,
    last_viewed_at timestamptz,
    playback_position_ms bigint,
    PRIMARY KEY (user_id, asset_id)
);

-- Machine learning results, keyed by the model that made them.
CREATE TABLE asset_embeddings (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    model_id text,
    embedding bytea NOT NULL,
    PRIMARY KEY (asset_id, model_id)
);

CREATE TABLE asset_ocr (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    model_id text,
    text text NOT NULL,
    PRIMARY KEY (asset_id, model_id)
);

CREATE TABLE asset_quality (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    model_id text,
    scores jsonb NOT NULL,
    PRIMARY KEY (asset_id, model_id)
);

-- The localised vocabulary of automatic labels, which are suggestions and never user tags.
CREATE TABLE ml_labels (
    id text PRIMARY KEY,
    names jsonb NOT NULL
);

CREATE TABLE asset_ml_labels (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    label_id text REFERENCES ml_labels (id) ON DELETE CASCADE,
    model_id text,
    score real NOT NULL,
    PRIMARY KEY (asset_id, label_id, model_id)
);

-- Tags (§6): a tree per user with the materialised path (Places|Europe|Paris).

CREATE TABLE tags (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    parent_id uuid REFERENCES tags (id) ON DELETE CASCADE,
    name text NOT NULL,
    path text NOT NULL,
    color text,
    is_album boolean NOT NULL DEFAULT false,
    origin text NOT NULL DEFAULT 'user' CHECK (origin IN ('user', 'import', 'auto_accepted')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (owner_id, parent_id, name)
);
CREATE INDEX tags_parent ON tags (parent_id);

CREATE TABLE asset_tags (
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    tag_id uuid REFERENCES tags (id) ON DELETE CASCADE,
    origin text NOT NULL DEFAULT 'user' CHECK (origin IN ('user', 'import', 'ml')),
    confidence real,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (asset_id, tag_id)
);
CREATE INDEX asset_tags_tag ON asset_tags (tag_id);

-- Albums (§5): nested folders, and albums as ordered blocks.

CREATE TABLE album_folders (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    parent_id uuid REFERENCES album_folders (id) ON DELETE CASCADE,
    name text NOT NULL,
    sort_key text NOT NULL
);
CREATE INDEX album_folders_parent ON album_folders (owner_id, parent_id);

-- A smart album keeps its saved search in `query`, a tag album its `tag_id`, a folder-backed album its library
-- folder; `encrypted_meta` holds what a private album hides from the server.
CREATE TABLE albums (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    folder_id uuid REFERENCES album_folders (id) ON DELETE SET NULL,
    sort_key text,
    kind text NOT NULL DEFAULT 'regular' CHECK (kind IN ('regular', 'smart', 'tag', 'folder_backed')),
    title text,
    description text,
    cover_asset_id uuid REFERENCES assets (id) ON DELETE SET NULL,
    sort_mode text NOT NULL DEFAULT 'taken_asc'
    CHECK (sort_mode IN ('custom', 'taken_asc', 'taken_desc', 'added_desc', 'name', 'rating')),
    layout text NOT NULL DEFAULT 'grid' CHECK (layout IN ('grid', 'justified', 'story')),
    privacy text NOT NULL DEFAULT 'standard' CHECK (privacy IN ('standard', 'private')),
    query bytea,
    tag_id uuid REFERENCES tags (id) ON DELETE CASCADE,
    include_descendants boolean NOT NULL DEFAULT true,
    source_library_id uuid REFERENCES libraries (id) ON DELETE CASCADE,
    source_path text,
    encrypted_meta bytea,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((kind = 'smart') = (query IS NOT NULL)),
    CHECK ((kind = 'tag') = (tag_id IS NOT NULL)),
    CHECK ((kind = 'folder_backed') = (source_library_id IS NOT NULL))
);
CREATE INDEX albums_owner ON albums (owner_id, folder_id);

-- Blocks in fractional-index order (`sort_key`); a text, location, divider or date block stays before its
-- `anchor_asset_id` whatever the album's sort.
CREATE TABLE album_items (
    id uuid PRIMARY KEY,
    album_id uuid NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('asset', 'text', 'heading', 'location', 'divider', 'date')),
    asset_id uuid REFERENCES assets (id) ON DELETE CASCADE,
    caption text,
    body text,
    anchor_asset_id uuid REFERENCES assets (id) ON DELETE SET NULL,
    place_id uuid REFERENCES places (id),
    lat double precision,
    lon double precision,
    sort_key text,
    encrypted bytea,
    added_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((kind = 'asset') = (asset_id IS NOT NULL))
);
CREATE INDEX album_items_order ON album_items (album_id, sort_key);
CREATE INDEX album_items_asset ON album_items (asset_id);

CREATE TABLE album_members (
    album_id uuid REFERENCES albums (id) ON DELETE CASCADE,
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'contributor', 'editor')),
    added_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (album_id, user_id)
);
CREATE INDEX album_members_user ON album_members (user_id);

-- Per-user visibility, materialised so that timeline queries never join albums.
CREATE TABLE album_user_state (
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    album_id uuid REFERENCES albums (id) ON DELETE CASCADE,
    hide_from_timeline boolean NOT NULL DEFAULT false,
    hide_from_memories boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, album_id)
);

CREATE TABLE library_user_state (
    user_id uuid REFERENCES users (id) ON DELETE CASCADE,
    library_id uuid REFERENCES libraries (id) ON DELETE CASCADE,
    hide_from_timeline boolean NOT NULL DEFAULT false,
    hide_from_memories boolean NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, library_id)
);

-- Public links to albums; only a hash of the token is stored.
CREATE TABLE links (
    id uuid PRIMARY KEY,
    album_id uuid NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
    token_hash bytea NOT NULL UNIQUE,
    created_by uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    password_hash text,
    allow_download boolean NOT NULL DEFAULT false,
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE partner_shares (
    owner_id uuid REFERENCES users (id) ON DELETE CASCADE,
    partner_id uuid REFERENCES users (id) ON DELETE CASCADE,
    taken_since date,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, partner_id),
    CHECK (owner_id <> partner_id)
);

-- People and pets (§7), per user; `merged_into` leaves a redirect for offline clients.

CREATE TABLE persons (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind text NOT NULL DEFAULT 'human' CHECK (kind IN ('human', 'pet')),
    name text,
    birth_date date,
    cover_face_id uuid,
    hidden boolean NOT NULL DEFAULT false,
    merged_into uuid REFERENCES persons (id),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX persons_owner ON persons (owner_id);

CREATE TABLE faces (
    id uuid PRIMARY KEY,
    asset_id uuid NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
    version_basis uuid REFERENCES versions (id) ON DELETE SET NULL,
    bbox real [] NOT NULL CHECK (cardinality(bbox) = 4), -- normalised x, y, width, height
    landmarks jsonb,
    model_id text NOT NULL,
    embedding bytea,
    quality real,
    person_id uuid REFERENCES persons (id) ON DELETE SET NULL,
    assignment text NOT NULL DEFAULT 'auto' CHECK (assignment IN ('auto', 'user', 'import')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX faces_asset ON faces (asset_id);
CREATE INDEX faces_person ON faces (person_id);
ALTER TABLE persons ADD CONSTRAINT persons_cover_face_id_fkey
FOREIGN KEY (cover_face_id) REFERENCES faces (id) ON DELETE SET NULL;

-- A user's must-link and cannot-link decisions, which every re-clustering and model upgrade respects.
CREATE TABLE face_constraints (
    id uuid PRIMARY KEY,
    face_id uuid NOT NULL REFERENCES faces (id) ON DELETE CASCADE,
    person_id uuid REFERENCES persons (id) ON DELETE CASCADE,
    other_face_id uuid REFERENCES faces (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('must_link', 'cannot_link')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(person_id, other_face_id) = 1)
);
CREATE INDEX face_constraints_face ON face_constraints (face_id);

-- Named circles such as "Home", used for search, memories and location stripping on share.
CREATE TABLE user_places (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name text NOT NULL,
    lat double precision NOT NULL,
    lon double precision NOT NULL,
    radius_m real NOT NULL,
    strip_on_share boolean NOT NULL DEFAULT false
);

-- The title is a template localised when shown.
CREATE TABLE memories (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('on_this_day', 'trip', 'person', 'year', 'theme')),
    title_template text NOT NULL,
    params jsonb NOT NULL DEFAULT '{}',
    date date NOT NULL,
    asset_ids uuid [] NOT NULL,
    cover_asset_id uuid REFERENCES assets (id) ON DELETE SET NULL,
    state text NOT NULL DEFAULT 'new' CHECK (state IN ('new', 'seen', 'dismissed', 'saved')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX memories_owner ON memories (owner_id, date);

-- Jobs, grants and audit (§10)

CREATE TABLE processing_grants (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    processor text NOT NULL, -- a server-processor key id or a device id
    scope jsonb NOT NULL,
    purposes text [] NOT NULL,
    wrapped_keys bytea,
    ledger_ref text,
    user_signature bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    revoked_at timestamptz
);

-- The job system (M0-17) defines the states and the queue indexes.
CREATE TABLE jobs (
    id uuid PRIMARY KEY,
    type text NOT NULL,
    payload bytea,
    status text NOT NULL,
    priority smallint NOT NULL DEFAULT 0,
    placement text NOT NULL DEFAULT 'server' CHECK (placement IN ('server', 'device', 'trusted_node')),
    grant_id uuid REFERENCES processing_grants (id),
    attempts integer NOT NULL DEFAULT 0,
    run_after timestamptz NOT NULL DEFAULT now(),
    lease_owner text,
    lease_until timestamptz,
    progress real,
    result bytea,
    error text,
    idempotency_key text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Append-only and hash-chained, so it has no foreign keys that could rewrite a row.
CREATE TABLE audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    at timestamptz NOT NULL DEFAULT now(),
    actor_user_id uuid,
    actor_device_id uuid,
    action text NOT NULL,
    target jsonb,
    details jsonb,
    prev_hash bytea,
    hash bytea NOT NULL
);
