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
-- if it is the sender or the addressee (the holon == seat-name convention). Split
-- per command so the recipient can actually WORK the baton:
--   SELECT  - either named party may see it.
--   INSERT  - you may only open a handoff FROM yourself (no forging the sender).
--   UPDATE  - EITHER named party may advance it (the addressee accepts/finishes,
--             the sender re-routes). The column grant below limits every caged
--             write to (status, updated_at), so a recipient can move the baton
--             forward but can never rewrite task / from_seat / to_seat.
-- A single FOR ALL policy with WITH CHECK (from_seat = current_holon()) was the
-- earlier form; it silently blocked the ADDRESSEE from accept/done (its rows have
-- from_seat = someone else), so caged seats could receive a baton but never pick it
-- up. This split is what completes a scoped/foreign seat's round trip.
ALTER TABLE handoffs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS own_seat        ON handoffs;
DROP POLICY IF EXISTS handoffs_select ON handoffs;
DROP POLICY IF EXISTS handoffs_insert ON handoffs;
DROP POLICY IF EXISTS handoffs_update ON handoffs;
CREATE POLICY handoffs_select ON handoffs FOR SELECT
  USING (to_seat = current_holon() OR from_seat = current_holon());
CREATE POLICY handoffs_insert ON handoffs FOR INSERT
  WITH CHECK (from_seat = current_holon());
CREATE POLICY handoffs_update ON handoffs FOR UPDATE
  USING      (to_seat = current_holon() OR from_seat = current_holon())
  WITH CHECK (to_seat = current_holon() OR from_seat = current_holon());
GRANT UPDATE (status, updated_at) ON handoffs TO membrane_app;

-- tags (the credit ledger): commons-readable bragging rights, append-only.
-- No UPDATE grant on purpose - credit is earned by a completed event, never edited.
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commons_or_mine ON tags;
CREATE POLICY commons_or_mine ON tags
  USING (visibility = 'commons' OR holon = current_holon());

-- 6) BIND THE HANDS TO THE IDENTITY (names a row records = who really wrote it) -
-- RLS above caps the EYES: what a seat can see. It does not check the NAMES a
-- write carries: opened_by / claimed_by / agent / from_agent / answered_by /
-- added_by are plain text the caller supplies, so a seat connected as bob could
-- open, claim, deliver, post and answer as 'alice'. handoffs already closes this
-- with from_seat = current_holon(); these triggers apply the same rule to every
-- other lane. The store stamps the name; the seat cannot claim it.
--   - a seat may label its own sub-agents '<holon>:<label>' (e.g. bob:researcher);
--     any other name is replaced by the seat's holon.
--   - a connection with no holon (the owner/admin, or a single-role box) is the
--     trusted path and is left as written. Every caged seat MUST have a
--     holon_roles row - add-caged-seat.sh does this.
-- Run `bash test-identity.sh` to prove it on a throwaway cluster.
CREATE OR REPLACE FUNCTION bind_name(supplied text, me text) RETURNS text
  LANGUAGE sql IMMUTABLE AS
$fn$ SELECT CASE WHEN supplied = me OR supplied LIKE me || ':%' THEN supplied ELSE me END $fn$;

-- coordination / registry / escalations / tickets: stamp the author on INSERT.
CREATE OR REPLACE FUNCTION stamp_author() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public, pg_temp AS
$fn$
DECLARE me text := current_holon();
BEGIN
  IF me IS NULL THEN RETURN NEW; END IF;
  CASE TG_TABLE_NAME
    WHEN 'coordination' THEN NEW.agent      := bind_name(NEW.agent, me);
    WHEN 'registry'     THEN NEW.added_by   := bind_name(NEW.added_by, me);
    WHEN 'escalations'  THEN NEW.from_agent := bind_name(NEW.from_agent, me);
    WHEN 'tickets'      THEN NEW.opened_by  := bind_name(NEW.opened_by, me);
  END CASE;
  RETURN NEW;
END $fn$;
-- (registry.approved_by is a claim ABOUT someone else; it stays as written.
--  Make approval its own signed write if you need it unforgeable.)

DROP TRIGGER IF EXISTS stamp_author ON coordination;
CREATE TRIGGER stamp_author BEFORE INSERT ON coordination FOR EACH ROW EXECUTE FUNCTION stamp_author();
DROP TRIGGER IF EXISTS stamp_author ON registry;
CREATE TRIGGER stamp_author BEFORE INSERT ON registry     FOR EACH ROW EXECUTE FUNCTION stamp_author();
DROP TRIGGER IF EXISTS stamp_author ON escalations;
CREATE TRIGGER stamp_author BEFORE INSERT ON escalations  FOR EACH ROW EXECUTE FUNCTION stamp_author();
DROP TRIGGER IF EXISTS stamp_author ON tickets;
CREATE TRIGGER stamp_author BEFORE INSERT ON tickets      FOR EACH ROW EXECUTE FUNCTION stamp_author();

-- escalations: the claimer/answerer is whoever makes the move; a claimed
-- question is answered only by its claimer.
CREATE OR REPLACE FUNCTION escalation_moves() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public, pg_temp AS
$fn$
DECLARE me text := current_holon();
BEGIN
  IF me IS NULL THEN RETURN NEW; END IF;
  IF NEW.status = 'claimed' AND OLD.status = 'needs_help' THEN
    NEW.claimed_by := bind_name(NEW.claimed_by, me);
  ELSE
    NEW.claimed_by := OLD.claimed_by;
  END IF;
  IF NEW.status = 'answered' AND OLD.status <> 'answered' THEN
    IF OLD.status = 'claimed' AND bind_name(OLD.claimed_by, me) IS DISTINCT FROM OLD.claimed_by THEN
      RAISE EXCEPTION 'escalation % is claimed by %; only the claimer answers it', OLD.id, OLD.claimed_by;
    END IF;
    NEW.answered_by := bind_name(NEW.answered_by, me);
  ELSE
    NEW.answered_by := OLD.answered_by;
    NEW.answer      := OLD.answer;
  END IF;
  RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS escalation_moves ON escalations;
CREATE TRIGGER escalation_moves BEFORE UPDATE ON escalations FOR EACH ROW EXECUTE FUNCTION escalation_moves();

-- tickets: only the legal transitions, each made by the right hand.
--   open -> claimed        any seat; claimed_by := that seat
--   claimed -> delivered   the claimer only; the only move that sets deliverable
--   delivered -> critiqued | closed   any seat; the only move that sets critique
-- (the cross-holon "can't grade your own homework" rule from
--  05-coordination-game.md layers on top of this.)
CREATE OR REPLACE FUNCTION ticket_moves() RETURNS trigger
  LANGUAGE plpgsql SET search_path = public, pg_temp AS
$fn$
DECLARE me text := current_holon();
BEGIN
  IF me IS NULL THEN RETURN NEW; END IF;
  IF (OLD.status, NEW.status) NOT IN (('open','claimed'), ('claimed','delivered'),
                                      ('delivered','critiqued'), ('delivered','closed')) THEN
    RAISE EXCEPTION 'ticket %: % -> % is not a legal move', OLD.id, OLD.status, NEW.status;
  END IF;
  NEW.claimed_by  := CASE WHEN NEW.status = 'claimed'   THEN bind_name(NEW.claimed_by, me) ELSE OLD.claimed_by END;
  NEW.deliverable := CASE WHEN NEW.status = 'delivered' THEN NEW.deliverable ELSE OLD.deliverable END;
  NEW.critique    := CASE WHEN OLD.status = 'delivered' THEN NEW.critique    ELSE OLD.critique END;
  IF NEW.status = 'delivered' AND bind_name(OLD.claimed_by, me) IS DISTINCT FROM OLD.claimed_by THEN
    RAISE EXCEPTION 'ticket % is claimed by %; only the claimer delivers it', OLD.id, OLD.claimed_by;
  END IF;
  RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS ticket_moves ON tickets;
CREATE TRIGGER ticket_moves BEFORE UPDATE ON tickets FOR EACH ROW EXECUTE FUNCTION ticket_moves();

-- tags: seats can READ credit but never WRITE it. Credit is system-applied by a
-- trigger owned by a privileged role (it bypasses this), never self-declared.
-- The RESTRICTIVE policy holds even if 01-schema.sql's blanket grant is re-run.
REVOKE INSERT ON tags FROM membrane_app;
DROP POLICY IF EXISTS no_seat_credit ON tags;
CREATE POLICY no_seat_credit ON tags AS RESTRICTIVE FOR INSERT TO membrane_app WITH CHECK (false);

-- ============================================================================
-- Sovereign alternative to per-holon roles: keep a single application role and
-- set the holon SERVER-SIDE inside a trusted capability layer (an MCP server, or
-- a SECURITY DEFINER context-setter behind a pooler), so clients get TOOLS, not
-- the ability to declare who they are. Same guarantee, different placement -
-- and the model this kit's own reference deployment uses.
-- ============================================================================
