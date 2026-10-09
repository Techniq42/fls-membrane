-- edge-roles.sql - roles and revocation hooks for the PostgREST edge example. Apache-2.0.
-- Run as superuser after sql/00-identity.sql (or 03-hardening.patched.sql). Idempotent.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN IN ROLE membrane_app;      -- commons only: no holon_roles row
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;               -- set a password out of band
  END IF;
END $$;
GRANT web_anon TO authenticator;
-- per seat, at provisioning time:  GRANT <seat_role> TO authenticator;
-- A JWT {"role": "<seat_role>", "exp": <now + 15 minutes>} then runs as that seat.
-- Issue SHORT-LIVED tokens (15 minutes is a default to tune): expiry bounds how
-- long a token issued before revocation could be replayed if every other step failed.

-- deny list, checked on every request before any query runs
CREATE TABLE IF NOT EXISTS revoked_seats (
  rolename   text PRIMARY KEY,
  revoked_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE revoked_seats OWNER TO store_owner;
REVOKE ALL ON revoked_seats FROM PUBLIC;

-- PostgREST: db-pre-request = "public.edge_pre_request"
CREATE OR REPLACE FUNCTION edge_pre_request() RETURNS void
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $f$
BEGIN
  -- current_user here is the definer; the request's role is in the GUC PostgREST sets
  IF EXISTS (SELECT 1 FROM revoked_seats
              WHERE rolename = coalesce(current_setting('request.jwt.claims', true)::json ->> 'role', '')) THEN
    RAISE EXCEPTION 'seat revoked' USING ERRCODE = '42501';
  END IF;
END $f$;
ALTER FUNCTION edge_pre_request() OWNER TO store_owner;
GRANT SELECT ON revoked_seats TO store_owner;
REVOKE ALL ON FUNCTION edge_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION edge_pre_request() TO web_anon, membrane_app;
