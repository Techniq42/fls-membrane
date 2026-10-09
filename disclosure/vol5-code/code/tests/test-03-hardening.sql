-- ============================================================================
-- tests for code/03-hardening.patched.sql   (Apache-2.0)
-- Run as superuser on a throwaway DB after 01-schema.sql + 03-hardening.patched.sql.
-- Covers: forward-only transitions, the FOR ALL override bug, stamped identity,
-- cross-holon append-only critique, system-applied credit, provenance.
-- ============================================================================
\set ON_ERROR_STOP 1

CREATE OR REPLACE FUNCTION expect(cond boolean, label text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $f$;
CREATE OR REPLACE FUNCTION expect_error(q text, label text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE refused boolean := false; why text;
BEGIN
  BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN refused := true; why := SQLERRM; END;
  IF NOT refused THEN RAISE EXCEPTION 'FAIL: % (was allowed)', label; END IF;
  RAISE NOTICE 'PASS: % (refused: %)', label, why;
END $f$;
-- "no rows changed" helper: RLS filters an UPDATE silently instead of raising
CREATE OR REPLACE FUNCTION expect_no_change(q text, label text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE n bigint;
BEGIN
  BEGIN
    EXECUTE q; GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: % (refused: %)', label, SQLERRM; RETURN;
  END;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: % (% rows changed)', label, n; END IF;
  RAISE NOTICE 'PASS: % (0 rows changed)', label;
END $f$;
GRANT EXECUTE ON FUNCTION expect(boolean,text), expect_error(text,text), expect_no_change(text,text) TO PUBLIC;

CREATE ROLE seat_a LOGIN IN ROLE membrane_app;
CREATE ROLE seat_b LOGIN IN ROLE membrane_app;
CREATE ROLE seat_c LOGIN IN ROLE membrane_app;
INSERT INTO holon_roles VALUES ('seat_a','a'), ('seat_b','b'), ('seat_c','c');

-- ---- identity is stamped, not declared ---------------------------------------
SET SESSION AUTHORIZATION seat_a;
INSERT INTO coordination (agent, focus) VALUES ('someone-else', 'testing');
SELECT expect((SELECT agent = 'seat_a' AND holon = 'a' FROM coordination WHERE focus = 'testing'),
              'H1 coordination.agent is stamped from the login, not the argument');
INSERT INTO escalations (from_agent, topic, prompt, status, answer)
  VALUES ('frontier', 'q', 'a hard question', 'answered', 'forged answer');
SELECT expect((SELECT from_agent = 'seat_a' AND status = 'needs_help' AND answer IS NULL FROM escalations),
              'H2 a new escalation cannot arrive pre-answered or under a forged name');
SELECT expect_error($$INSERT INTO registry (entity, kind) VALUES ('NOPROV','org')$$,
                    'H3 registry rows need a source_url (provenance)');
INSERT INTO registry (entity, kind, source_url) VALUES ('ACME2','org','https://example.org');
SELECT expect_error($$INSERT INTO tags (holon, tag) VALUES ('a','delivered')$$, 'H4 a seat cannot award itself credit');
RESET SESSION AUTHORIZATION;

-- ---- the FOR ALL override bug: another seat edits a commons row ---------------
SET SESSION AUTHORIZATION seat_b;
SELECT expect_no_change($$UPDATE coordination SET note = 'vandalised' WHERE focus = 'testing'$$,
                        'H5 seat_b cannot edit seat_a''s commons coordination row');
RESET SESSION AUTHORIZATION;

-- ---- escalations move forward only --------------------------------------------
SET SESSION AUTHORIZATION seat_b;
UPDATE escalations SET status = 'claimed';
SELECT expect((SELECT claimed_by FROM escalations) = 'seat_b', 'H6 claim stamps claimed_by = seat_b');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_c;
SELECT expect_error($$UPDATE escalations SET status = 'answered', answer = 'sniped'$$,
                    'H7 a non-claimer cannot answer a claimed escalation');
SELECT expect_error($$UPDATE escalations SET status = 'needs_help'$$,
                    'H8 a non-claimer cannot un-claim it');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_b;
UPDATE escalations SET status = 'needs_help';      -- decline
SELECT expect((SELECT status = 'needs_help' AND passes = 1 AND declined_by = ARRAY['seat_b'] AND claimed_by IS NULL
                 FROM escalations), 'H9 decline re-opens: passes 1, declined_by seat_b');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_c;
UPDATE escalations SET status = 'claimed';
UPDATE escalations SET status = 'answered', answer = 'Retrieval plus a shared commons.';
SELECT expect((SELECT status = 'answered' AND answered_by = 'seat_c' FROM escalations), 'H10 claimer answers');
SELECT expect_no_change($$UPDATE escalations SET status = 'needs_help'$$,
                        'H11 answered -> needs_help is refused (the published FOR ALL policy allowed this)');
SELECT expect_no_change($$UPDATE escalations SET answer = 'rewritten'$$,
                        'H12 an answered row cannot be rewritten');
RESET SESSION AUTHORIZATION;

-- ---- tickets: legal moves, write-once deliverable, cross-holon critique --------
SET SESSION AUTHORIZATION seat_a;
INSERT INTO tickets (title, opened_by, body) VALUES ('Summarise the cold-chain notes', 'nobody', 'body');
SELECT expect((SELECT opened_by = 'seat_a' AND holon = 'a' AND status = 'open' FROM tickets), 'H13 ticket stamped to seat_a');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_b;
UPDATE tickets SET status = 'claimed';
SELECT expect_error($$UPDATE tickets SET status = 'closed'$$, 'H14 claimed -> closed skips delivery: refused');
UPDATE tickets SET status = 'delivered', deliverable = 'Three-line summary.';
SELECT expect_error($$INSERT INTO ticket_critiques (ticket_id, verdict, body) SELECT id, 'endorse', 'great work' FROM tickets$$,
                    'H15 the deliverer cannot critique its own delivery');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_c;
SELECT expect_error($$UPDATE tickets SET status = 'open'$$, 'H16 delivered -> open (backward) refused');
SELECT expect_error($$UPDATE tickets SET deliverable = 'overridden by checker'$$, 'H17 a checker cannot override the deliverable');
INSERT INTO ticket_critiques (ticket_id, critic, verdict, body)
  SELECT id, 'seat_a', 'question', 'Line two needs a source.' FROM tickets;
SELECT expect((SELECT critic FROM ticket_critiques) = 'seat_c', 'H18 cross-holon critique accepted, critic stamped seat_c');
SELECT expect_error($$UPDATE ticket_critiques SET body = 'softened'$$, 'H19 critique is append-only (no UPDATE)');
SELECT expect_error($$DELETE FROM ticket_critiques$$, 'H20 critique is append-only (no DELETE)');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_a;
UPDATE tickets SET status = 'closed';
SELECT expect((SELECT status FROM tickets) = 'closed', 'H21 requester closes');
SELECT expect_no_change($$UPDATE tickets SET status = 'open'$$, 'H22 a closed ticket cannot be re-opened');
SELECT expect((SELECT count(*) FROM tags WHERE holon = 'b' AND tag = 'delivered') = 1
          AND (SELECT count(*) FROM tags WHERE holon = 'c' AND tag = 'checked') = 1,
              'H23 credit applied by the store: delivered -> b, checked -> c');
RESET SESSION AUTHORIZATION;

-- ---- handoffs: forward only, sender stamped -------------------------------------
SET SESSION AUTHORIZATION seat_a;
INSERT INTO handoffs (task, from_seat, to_seat, summary) VALUES ('baton', 'a', 'b', 'leg one');
INSERT INTO handoffs (task, from_seat, to_seat) VALUES ('forged', 'c', 'b');
SELECT expect((SELECT from_seat FROM handoffs WHERE task = 'forged') = 'a', 'H24 forged sender rewritten to the real sender');
SELECT expect_error($$UPDATE handoffs SET status = 'accepted' WHERE task = 'baton'$$, 'H25 the sender cannot accept on the addressee''s behalf');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION seat_b;
UPDATE handoffs SET status = 'accepted' WHERE task = 'baton';
UPDATE handoffs SET status = 'done' WHERE task = 'baton';
SELECT expect_error($$UPDATE handoffs SET status = 'pending' WHERE task = 'baton'$$, 'H26 done -> pending refused');
RESET SESSION AUTHORIZATION;

-- ---- red-team regressions (redteam/rt_hardening_anon.py): an unmapped edge role
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN IN ROLE membrane_app;
  END IF;
END $$;
SET SESSION AUTHORIZATION seat_a;
INSERT INTO escalations (from_agent, topic, prompt) VALUES ('', 't', 'rt question');
INSERT INTO tickets (title, opened_by) VALUES ('rt ticket', '');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION web_anon;
SELECT expect_error($$UPDATE escalations SET status = 'answered', answer = 'forged by anonymous' WHERE prompt = 'rt question'$$,
                    'RT-E1 an anonymous edge role cannot answer a commons escalation');
SELECT expect_error($$UPDATE tickets SET status = 'claimed' WHERE title = 'rt ticket'$$,
                    'RT-T1 an anonymous edge role cannot claim a commons ticket');
SELECT expect_error($$INSERT INTO coordination (agent, focus) VALUES ('x','y')$$,
                    'RT-T1b an anonymous edge role cannot post');
RESET SESSION AUTHORIZATION;

\echo 'ALL HARDENING TESTS PASSED'
