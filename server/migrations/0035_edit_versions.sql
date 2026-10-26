-- Edit recipes and version history (M8-01, ADR-0391). A version is the immutable record of one edit: its recipe, its
-- hash, its parent and its kind never change, so that a revert only moves `assets.current_version_id` and a comparison
-- of two versions always compares what they were. What describes a version (its label and note, the file rendered for
-- it) may change.
CREATE FUNCTION photolib_version_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (OLD.asset_id, OLD.parent_id, OLD.kind, OLD.recipe, OLD.recipe_hash, OLD.process_version, OLD.created_at)
        IS DISTINCT FROM (NEW.asset_id, NEW.parent_id, NEW.kind, NEW.recipe, NEW.recipe_hash, NEW.process_version,
                          NEW.created_at) THEN
        RAISE EXCEPTION 'versions are immutable' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER versions_immutable BEFORE UPDATE ON versions
    FOR EACH ROW EXECUTE FUNCTION photolib_version_immutable();

-- A face is found in one version (`version_basis`); `bbox` is where it is in that version's frame. `source_bbox` is
-- where it is in the original's frame, set when an edit first moves it, so that any version's box is computed from it
-- and a revert loses nothing; `cropped` marks a face the current version's frame cuts out.
ALTER TABLE faces ADD COLUMN source_bbox real [] CHECK (source_bbox IS NULL OR cardinality(source_bbox) = 4);
ALTER TABLE faces ADD COLUMN cropped boolean NOT NULL DEFAULT false;

-- The text OCR read was read in one version of the picture (`version_id`; NULL for the pictures read before versions
-- had recipes, which were read as they came) and `regions` says where each line is, as fractions of that version.
ALTER TABLE asset_ocr ADD COLUMN version_id uuid;
ALTER TABLE asset_ocr ADD COLUMN regions jsonb;
