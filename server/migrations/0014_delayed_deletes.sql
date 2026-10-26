-- Delayed deletes (ADR-0089): a switched delete waits until `due`, so that the source of a library's store move stays
-- readable for a grace period. The purge job does them; recovery leaves them alone.
ALTER TABLE file_intents ADD COLUMN due timestamptz;
