-- ============================================================================
-- Volume 5 supplement, sql/00-identity.sql          (Apache-2.0)
-- Unforgeable seat identity, shared by the interlock (10-*) and the patched
-- hardening layer (code/03-hardening.patched.sql).
--
-- Run as a superuser (or a role with CREATEROLE) on a FRESH database.
--
-- What this file fixes relative to the published 03-hardening.sql:
--   * The published current_holon() is SECURITY DEFINER and keyed on
--     session_user. That works for direct per-seat logins, but it breaks behind
--     any edge layer that logs in once and then SET ROLEs per request (PostgREST,
--     pgbouncer with SET ROLE, Supabase). There session_user is the pooler, so
--     every request resolves to NULL (or to the pooler's holon).
--   * Here current_holon() is an ordinary (invoker) function reading a view the
--     store owner owns. Inside a view, current_user is still the querying role,
--     so the lookup sees the role the request is actually running as. The
--     mapping table stays sealed: seats may read the view (their own row only),
--     never the table.
-- ============================================================================

-- 1) the store owner. Owns every table. NOLOGIN: nobody operates as owner day to
--    day, and FORCE ROW LEVEL SECURITY (set per table) binds it anyway.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'store_owner') THEN
    CREATE ROLE store_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
  -- base capability role every seat inherits (name kept from the kit)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'membrane_app') THEN
    CREATE ROLE membrane_app NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;

GRANT USAGE, CREATE ON SCHEMA public TO store_owner;
GRANT USAGE ON SCHEMA public TO membrane_app;

SET ROLE store_owner;

-- 2) the sealed mapping: login role -> holon (owner-scope)
CREATE TABLE IF NOT EXISTS holon_roles (
  rolename text PRIMARY KEY,
  holon    text NOT NULL CHECK (holon ~ '^[a-z][a-z0-9_-]{1,62}$')
);
REVOKE ALL ON holon_roles FROM PUBLIC;

-- 3) the self-view. A seat sees at most its own mapping row.
--    current_user first (correct behind SET ROLE edges), session_user second
--    (correct for direct logins and inside SECURITY DEFINER trigger bodies).
-- revoked seats: a role listed here resolves to no holon at once, on every path
-- (direct login, or an edge session that already switched to the role)
CREATE TABLE IF NOT EXISTS revoked_seats (
  rolename   text PRIMARY KEY,
  revoked_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON revoked_seats FROM PUBLIC;

CREATE OR REPLACE VIEW holon_self WITH (security_barrier = true) AS
  -- the role this request runs as, if the session that switched to it is STILL a
  -- member (a revoked edge membership stops resolving at once) and it is not revoked
  SELECT holon, 1 AS pref FROM holon_roles
   WHERE rolename = current_user::text
     AND (current_user = session_user OR pg_has_role(session_user, current_user, 'MEMBER'))
     AND rolename NOT IN (SELECT rolename FROM revoked_seats)
  UNION ALL
  SELECT holon, 2 AS pref FROM holon_roles
   WHERE rolename = session_user::text
     AND rolename NOT IN (SELECT rolename FROM revoked_seats);
REVOKE ALL ON holon_self FROM PUBLIC;
GRANT SELECT ON holon_self TO membrane_app;

CREATE OR REPLACE FUNCTION current_holon() RETURNS text
  LANGUAGE sql STABLE SET search_path = public, pg_temp AS
$fn$ SELECT holon FROM holon_self ORDER BY pref LIMIT 1 $fn$;

-- the seat name (the login identity). Used to bind "who did this" columns so a
-- seat cannot type someone else's name into them.
CREATE OR REPLACE FUNCTION current_seat() RETURNS text
  LANGUAGE sql STABLE AS
$fn$ SELECT CASE WHEN current_holon() IS NULL THEN NULL ELSE current_user::text END $fn$;
-- current_seat() returns NULL for an unmapped role, so a ghost seat cannot
-- stamp rows. Call it only from INVOKER code (never from a SECURITY DEFINER
-- body, where current_user is the function owner).

RESET ROLE;

GRANT EXECUTE ON FUNCTION current_holon() TO membrane_app;
GRANT EXECUTE ON FUNCTION current_seat()  TO membrane_app;
