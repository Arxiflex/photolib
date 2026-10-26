-- The ingest pipeline (ADR-0066): where an uploaded file was on its device, a motion photo's video as a range of its
-- original, and the camera burst a photo belongs to.

-- The file's path below its source's root as the client named it, e.g. DCIM/Camera/IMG_1.jpg; never a storage key.
ALTER TABLE uploads ADD COLUMN path text;

-- A virtual file, such as a motion photo's motion_extracted video, is `size` bytes of `key` from this offset.
ALTER TABLE asset_files ADD COLUMN byte_offset bigint;

-- Apple's BurstUUID or Google's BurstID, by which camera bursts are stacked.
ALTER TABLE assets ADD COLUMN burst_id text;
