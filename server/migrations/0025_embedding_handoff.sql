-- Device hand-off (photolib-design docs/09 §3.2): the vector a device computed for an upload with the active model,
-- as half floats, checked when the upload was created; ingest keeps it for the asset. NULL without one.
ALTER TABLE uploads ADD COLUMN embedding_model text, ADD COLUMN embedding bytea;
