-- Integrity findings in external libraries (photolib-design#605, ADR-0234): an external file's key is its path under
-- its library's root, which other libraries may repeat, so a finding there names the library. NULL for an object of a
-- store, whose key is the store's own.
ALTER TABLE integrity_findings ADD COLUMN library_id uuid;
