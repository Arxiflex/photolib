-- The sync RPC (M2-14, ADR-0091): a library's assets page newest first, undated last, and what hangs off an asset or
-- was deleted is read by transaction, whichever asset or scope it belongs to. Only indexes; no release predates this
-- migration, so the tables are small wherever it runs.
-- squawk-ignore-file require-concurrent-index-creation
CREATE INDEX assets_newest ON assets (library_id, coalesce(taken_utc, '-infinity'::timestamptz), id);
CREATE INDEX asset_files_changes ON asset_files (txid);
CREATE INDEX versions_changes ON versions (txid);
CREATE INDEX asset_custom_values_changes ON asset_custom_values (txid);
CREATE INDEX faces_changes ON faces (txid);
CREATE INDEX asset_embeddings_changes ON asset_embeddings (txid);
CREATE INDEX asset_ocr_changes ON asset_ocr (txid);
CREATE INDEX asset_quality_changes ON asset_quality (txid);
CREATE INDEX asset_ml_labels_changes ON asset_ml_labels (txid);
CREATE INDEX tombstones_changes ON tombstones (entity, txid);
