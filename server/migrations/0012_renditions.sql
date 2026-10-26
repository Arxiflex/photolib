-- Image renditions (M2-09, ADR-0084).

-- The ThumbHash of the asset's smallest rendition (photolib-design docs/08 §4.1): about 25 bytes, an instant
-- placeholder.
ALTER TABLE assets ADD COLUMN thumbhash bytea;
