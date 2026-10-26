-- The job queue of photolib-jobs (ADR-0034): job states, the queue indexes and cron schedules.

ALTER TABLE jobs ADD CONSTRAINT jobs_status
CHECK (status IN ('queued', 'running', 'done', 'dead', 'cancelled')) NOT VALID;

-- Nothing wrote jobs before this migration, so these builds take no time.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX jobs_due ON jobs (priority DESC, run_after) WHERE status = 'queued';
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX jobs_leased ON jobs (lease_until) WHERE status = 'running';
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX jobs_grant ON jobs (grant_id) WHERE status IN ('queued', 'running');

-- `cron` is five fields in UTC; the scheduler enqueues `type` once per occurrence.
CREATE TABLE job_schedules (
    name text PRIMARY KEY,
    cron text NOT NULL,
    type text NOT NULL,
    payload bytea,
    next_run timestamptz NOT NULL
);

-- A UUIDv7 for rows made in SQL; PostgreSQL has uuidv7() only from 18.
CREATE FUNCTION photolib_uuidv7() RETURNS uuid LANGUAGE sql VOLATILE AS $$
SELECT encode(set_bit(set_bit(overlay(uuid_send(gen_random_uuid()) PLACING
    substring(int8send((extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3) FROM 1 FOR 6), 52, 1), 53, 1),
    'hex')::uuid
$$;
