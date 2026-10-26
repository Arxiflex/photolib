-- Faces are found only for accounts that agreed (ADR-0389, design 09 §7): `face_consents` holds a row for each account
-- that opted in, with the version of the notice it was shown; withdrawing deletes the row and, with it, the faces and
-- scans of the account's assets (the application does both in one transaction, and logs each as an audit event).
-- Server only: devices learn it from the face consent API.
CREATE TABLE face_consents (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    notice_version integer NOT NULL CHECK (notice_version > 0),
    granted_at timestamptz NOT NULL DEFAULT now()
);

-- The detector's confidence, the model that found the face, and for a video the moment of its keyframe.
ALTER TABLE faces ADD COLUMN score real, ADD COLUMN detector text, ADD COLUMN time_ms integer CHECK (time_ms >= 0);

-- An asset a model has looked at, with or without faces in it, so that it is not looked at again.
CREATE TABLE face_scans (
    asset_id uuid NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
    model_id text NOT NULL,
    faces integer NOT NULL CHECK (faces >= 0),
    scanned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (asset_id, model_id)
);
