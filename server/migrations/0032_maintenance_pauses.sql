-- The owner's answer on maintenance pauses (photolib-design#699, ADR-0063): one request pauses a maintenance type for
-- up to 7 days, and no pause is held to a week after it began, so its start, which only that clamp read, goes.
-- squawk-ignore ban-drop-column
ALTER TABLE job_pauses DROP COLUMN since;
