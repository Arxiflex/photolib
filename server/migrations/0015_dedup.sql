-- Per-user deduplication (ADR-0092): uploads and CheckHashes find the files that hold a hash.

-- No release has ingested assets yet, so the table is small and this build is quick.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX asset_files_content_hash ON asset_files (content_hash)
WHERE role IN ('original', 'original_alt', 'live_motion');
