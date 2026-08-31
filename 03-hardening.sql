-- ============================================================================
-- MEMBRANE KIT - 03-hardening.sql   (Apache-2.0, see LICENSE + NOTICE)
-- Optional hardening layer, applied ON TOP of 01-schema.sql.
--
-- 01-schema.sql stands up a DEMO trust model: RLS on the escalations lane only,
-- seats declare their own holon via `app.holon`, one shared application role.
-- That is fine for a single trusted box. This file moves you to a MULTI-PARTY
-- trust model: every lane scoped, holon identity a seat cannot forge, and writes
-- narrowed to legal moves.
--     psql -d yourdb -f 01-schema.sql
--     psql -d yourdb -f 03-hardening.sql
-- ============================================================================

-- 1) EXTEND RLS TO EVERY LANE (the demo guards only escalations) --------------
ALTER TABLE coordination ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'commons';
ALTER TABLE coordination ADD COLUMN IF NOT EXISTS holon      text NOT NULL DEFAULT 'public';
ALTER TABLE registry     ADD COLUMN IF NOT EXISTS holon      text NOT NULL DEFAULT 'public';

ALTER TABLE coordination ENABLE ROW LEVEL SECURITY;
ALTER TABLE registry     ENABLE ROW LEVEL SECURITY;

-- 2) UNFORGEABLE HOLON IDENTITY (Option A - per-holon login roles) ------------
-- The demo lets any seat SET app.holon = 'anything' and read that holon's rows:
-- cooperative, not enforced. Here, identity is WHO YOU CONNECT AS, resolved by
-- the store - not a value the seat can claim.
CREATE TABLE IF NOT EXISTS holon_roles (
  rolename text PRIMARY KEY,
  holon    text NOT NULL
);
-- provision one login role per seat (do this per deployment, not in this file):
--   CREATE ROLE seat_acme LOGIN PASSWORD '...' IN ROLE membrane_app;
--   INSERT INTO holon_roles VALUES ('seat_acme', 'acme');

-- the holon of the CURRENT connection, resolved from its role (not claimable).
-- SECURITY DEFINER so a scoped seat need not - and cannot - read holon_roles itself
-- (that keeps the mapping table sealed). Keyed on session_user, NOT current_user:
-- under SECURITY DEFINER current_user becomes the function's owner, so current_user
-- would resolve the WRONG identity and return NULL. session_user stays the login role.
-- Pin search_path and own the function with a privileged role per deployment:
--   ALTER FUNCTION current_holon() OWNER TO postgres;
CREATE OR REPLACE FUNCTION current_holon() RETURNS text
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS
$fn$ SELECT holon FROM holon_roles WHERE rolename = session_user $fn$;

-- read policies now check identity, not a setting. Commons is board-wide;
-- everything else is visible only to its owning holon.
DROP POLICY IF EXISTS commons_or_mine ON escalations;
CREATE POLICY commons_or_mine ON escalations
  USING (visibility = 'commons' OR holon = current_holon());
DROP POLICY IF EXISTS commons_or_mine ON coordination;
CREATE POLICY commons_or_mine ON coordination
  USING (visibility = 'commons' OR holon = current_holon());
DROP POLICY IF EXISTS commons_or_mine ON registry;
CREATE POLICY commons_or_mine ON registry
  USING (visibility = 'commons' OR holon = current_holon());

-- 3) NARROW WRITES TO LEGAL MOVES (kill the blanket UPDATE grant) -------------
REVOKE UPDATE ON ALL TABLES IN SCHEMA public FROM membrane_app;

-- a seat may only INSERT rows into its own holon (or shared commons):
DROP POLICY IF EXISTS insert_own_or_commons ON coordination;
CREATE POLICY insert_own_or_commons ON coordination FOR INSERT
  WITH CHECK (visibility = 'commons' OR holon = current_holon());

-- coordination: a seat may edit only its own holon's rows:
GRANT UPDATE ON coordination TO membrane_app;
DROP POLICY IF EXISTS own_rows_only ON coordination;
CREATE POLICY own_rows_only ON coordination FOR UPDATE
  USING      (holon = current_holon())
  WITH CHECK (holon = current_holon());

-- escalations: only the claim/answer columns, and only forward transitions:
GRANT UPDATE (status, claimed_by, answer, answered_by, answered_at)
  ON escalations TO membrane_app;
DROP POLICY IF EXISTS claim_or_answer ON escalations;
CREATE POLICY claim_or_answer ON escalations FOR UPDATE
  USING      (status IN ('needs_help','claimed'))
  WITH CHECK (status IN ('claimed','answered'));

-- registry: append-only. Corrections arrive as a NEW row (or via an admin role).
-- (Deliberately no UPDATE grant here.)

-- 4) INTEGRITY (cheap, high trust-signal) -------------------------------------
-- enforce the status vocabulary for new rows without failing on legacy data:
ALTER TABLE escalations DROP CONSTRAINT IF EXISTS valid_status;
ALTER TABLE escalations ADD CONSTRAINT valid_status
  CHECK (status IN ('needs_help','claimed','answered')) NOT VALID;

CREATE INDEX IF NOT EXISTS escalations_poll ON escalations (status, created_at);

-- 5) EXTEND THE MODEL TO THE TICKET + HANDOFF LANES ---------------------------
-- Same pattern: scope reads to commons-or-own-holon, narrow writes to legal moves.

-- tickets: commons or own-holon visible; a seat opens into its own scope, and
-- writes are limited to the legal status transitions (+ only their columns).
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commons_or_mine ON tickets;
CREATE POLICY commons_or_mine ON tickets
  USING (visibility = 'commons' OR holon = current_holon());
DROP POLICY IF EXISTS insert_own_or_commons ON tickets;
CREATE POLICY insert_own_or_commons ON tickets FOR INSERT
  WITH CHECK (visibility = 'commons' OR holon = current_holon());
GRANT UPDATE (status, claimed_by, deliverable, critique, updated_at) ON tickets TO membrane_app;
DROP POLICY IF EXISTS legal_moves ON tickets;
CREATE POLICY legal_moves ON tickets FOR UPDATE
  USING (status IN ('open','claimed','delivered'));

-- handoffs: the baton is scoped to the SEATS it names. A seat sees a handoff only
-- if it is the sender or the addressee (the holon == seat-name convention), and it
-- may only create a handoff FROM itself. This is what stops a foreign scoped seat
-- from reading the whole board's internal task-passing.
ALTER TABLE handoffs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS own_seat ON handoffs;
CREATE POLICY own_seat ON handoffs FOR ALL
  USING      (to_seat = current_holon() OR from_seat = current_holon())
  WITH CHECK (from_seat = current_holon());
GRANT UPDATE (status, updated_at) ON handoffs TO membrane_app;

-- tags (the credit ledger): commons-readable bragging rights, append-only.
-- No UPDATE grant on purpose - credit is earned by a completed event, never edited.
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commons_or_mine ON tags;
CREATE POLICY commons_or_mine ON tags
  USING (visibility = 'commons' OR holon = current_holon());

-- ============================================================================
-- Sovereign alternative to per-holon roles: keep a single application role and
-- set the holon SERVER-SIDE inside a trusted capability layer (an MCP server, or
-- a SECURITY DEFINER context-setter behind a pooler), so clients get TOOLS, not
-- the ability to declare who they are. Same guarantee, different placement -
-- and the model this kit's own reference deployment uses.
-- ============================================================================
