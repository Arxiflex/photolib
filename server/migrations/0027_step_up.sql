-- Step-up (M2-43, ADR-0242): when a session last proved its person with the password, a passkey or a second factor,
-- which removing or replacing a second factor needs within five minutes. NULL: never since this column came.
ALTER TABLE sessions ADD COLUMN proved_at timestamptz;
