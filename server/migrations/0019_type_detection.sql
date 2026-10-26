-- Type detection versions (ADR-0066): which version of ingest's type detection last checked an asset, so that a
-- release that learns a format checks again the assets an older one found no photo or video in. NULL: checked before
-- versions were recorded, older than any.
ALTER TABLE assets ADD COLUMN sniff_version smallint;
