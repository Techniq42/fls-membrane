-- ============================================================================
-- Reproduces the bug in the PUBLISHED 03-hardening.sql (code/orig/), so the fix
-- is shown against a real failure. Run on a throwaway DB after
-- 01-schema.sql + orig/03-hardening.sql. Each "BUG" line passing means the
-- published file allowed the move.   (Apache-2.0)
-- ============================================================================
\set ON_ERROR_STOP 1
CREATE OR REPLACE FUNCTION expect(cond boolean, label text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF cond IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END $f$;
GRANT EXECUTE ON FUNCTION expect(boolean,text) TO PUBLIC;

CREATE ROLE seat_a LOGIN IN ROLE membrane_app;
CREATE ROLE seat_b LOGIN IN ROLE membrane_app;
INSERT INTO holon_roles VALUES ('seat_a','a'), ('seat_b','b');

-- seed an answered commons escalation and a commons coordination row owned by a
INSERT INTO escalations (from_agent, prompt, status, answer, answered_by, holon)
  VALUES ('seat_a', 'q', 'answered', 'the answer', 'seat_c', 'a');
INSERT INTO coordination (agent, focus, holon) VALUES ('seat_a', 'mine', 'a');

SET SESSION AUTHORIZATION seat_b;
WITH u AS (UPDATE escalations SET status = 'needs_help', answered_by = 'seat_b' RETURNING 1)
SELECT expect((SELECT count(*) FROM u) = 1,
  'BUG-1 (published file) seat_b moved an ANSWERED commons escalation back to needs_help and re-signed it');
WITH u AS (UPDATE coordination SET note = 'vandalised' RETURNING 1)
SELECT expect((SELECT count(*) FROM u) = 1,
  'BUG-2 (published file) seat_b edited seat_a''s commons coordination row');
WITH u AS (INSERT INTO escalations (from_agent, prompt, status, answer) VALUES ('frontier', 'x', 'answered', 'forged') RETURNING from_agent)
SELECT expect((SELECT from_agent FROM u) = 'frontier',
  'BUG-3 (published file) seat_b posted under another seat''s name, pre-answered');
RESET SESSION AUTHORIZATION;
