-- Accounts (M2-01, ADR-0035): viewer-only accounts (OPS-27), delayed deletion (OPS-22) and an audit event for every
-- account change, whoever makes it.

-- The upgrade runs before anything is served, and no existing row can violate these checks: the replaced ones only
-- widen, and purge_at is new.
-- squawk-ignore-file ban-drop-constraint, constraint-missing-not-valid
ALTER TABLE users DROP CONSTRAINT users_role_check,
ADD CONSTRAINT users_role_check CHECK (role IN ('admin', 'user', 'viewer'));
ALTER TABLE users DROP CONSTRAINT users_status_check,
ADD CONSTRAINT users_status_check CHECK (status IN ('active', 'disabled', 'invited', 'deleted'));

-- A deleted account is purged at purge_at unless its status changes back first.
ALTER TABLE users ADD COLUMN purge_at timestamptz;
ALTER TABLE users ADD CONSTRAINT users_purge_at_check CHECK ((status = 'deleted') <> (purge_at IS NULL));

-- What chains audit_events: SHA-256 over the previous event's hash and this event's fields.
CREATE FUNCTION audit_hash(
    prev bytea, at timestamptz, actor_user uuid, actor_device uuid, action text, target jsonb, details jsonb
) RETURNS bytea LANGUAGE sql STABLE AS $$
    SELECT sha256(coalesce(prev, '') || convert_to(
        jsonb_build_array(extract(EPOCH FROM at), actor_user, actor_device, action, target, details)::text, 'UTF8'
    ))
$$;

-- Appends an event. The lock holds other writers until this transaction ends, so that the chain stays linear.
CREATE FUNCTION audit_append(actor_user uuid, action text, target jsonb, details jsonb) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    prev bytea;
BEGIN
    LOCK TABLE audit_events IN SHARE ROW EXCLUSIVE MODE;
    SELECT hash INTO prev FROM audit_events ORDER BY id DESC LIMIT 1;
    INSERT INTO audit_events (at, actor_user_id, action, target, details, prev_hash, hash)
    VALUES (now(), actor_user, action, target, details, prev,
            audit_hash(prev, now(), actor_user, NULL, action, target, details));
END
$$;

-- Audits every change to an account. photolibd names the acting user in the transaction's `photolib.actor` setting;
-- a change made around it (psql) has no actor. Personal fields are named, never copied, so that the append-only
-- chain keeps no personal data of a purged account.
CREATE FUNCTION audit_users() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    old_row jsonb := to_jsonb(OLD);
    new_row jsonb := to_jsonb(NEW);
BEGIN
    IF old_row = new_row THEN
        RETURN NULL;
    END IF;
    PERFORM audit_append(
        nullif(current_setting('photolib.actor', true), '')::uuid,
        CASE TG_OP WHEN 'INSERT' THEN 'user.create' WHEN 'UPDATE' THEN 'user.update' ELSE 'user.purge' END,
        jsonb_build_object('user_id', coalesce(new_row, old_row) -> 'id'),
        (
            SELECT jsonb_build_object('fields', coalesce(jsonb_agg(key ORDER BY key), '[]'))
                || coalesce(jsonb_object_agg(key, value) FILTER (
                    WHERE key NOT IN ('handle', 'display_name', 'email')
                ), '{}')
            FROM jsonb_each(new_row)
            WHERE key NOT IN ('id', 'created_at') AND (old_row -> key) IS DISTINCT FROM value
        )
    );
    RETURN NULL;
END
$$;

CREATE TRIGGER users_audit AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION audit_users();
