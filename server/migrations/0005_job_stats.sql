-- What /metrics counts at every scrape (ADR-0038): the open and dead jobs by type, without reading finished ones.

-- No release has run the job system yet, so the table is small and this build is quick.
-- squawk-ignore require-concurrent-index-creation
CREATE INDEX jobs_stats ON jobs (type, status, created_at) WHERE status IN ('queued', 'running', 'dead');
