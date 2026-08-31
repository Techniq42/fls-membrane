-- ============================================================================
-- DEMO A — the four-times-ACME fix: poke-and-hope  ->  look-at-the-board
-- ============================================================================
-- BEFORE: A steward asks the oracle "add ACME" 4x because the state is invisible.
-- AFTER: it's ONE row every seat + human reads. Add once; everyone sees it.
INSERT INTO registry (entity, kind, added_by, approved_by, source_url)
VALUES ('ACME','organisation','coordinator','a-steward','https://livingsys.org/resources/agent-constitution')
ON CONFLICT (entity) DO NOTHING;

-- anyone (bot, worker, human) now just READS it — no re-poking the oracle:
SELECT entity, kind, added_by, approved_by, created_at
FROM registry WHERE entity='ACME';

-- ============================================================================
-- DEMO B — escalate-to-frontier: a hard question handed UP, answer comes BACK
-- ============================================================================
-- 1) the frozen/small agent hands off a question it can't answer well:
INSERT INTO escalations (from_agent, topic, prompt) VALUES (
  'small-local',
  'agent-knowledge',
  'To give a frozen agent knowledge about our orgs, should we fine-tune the model or use retrieval + a shared commons? Give a crisp recommendation.'
);

-- 2) a FRONTIER seat (a bigger model or a human) claims + answers
--    back INTO the row (see 03-frontier-answer, run by the frontier).
-- 3) the small agent then just reads the answer:
--    SELECT answer, answered_by FROM escalations WHERE status='answered' ORDER BY id DESC LIMIT 1;
