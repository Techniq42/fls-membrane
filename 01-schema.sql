-- ============================================================================
-- MEMBRANE KIT — reference schema (generic — Apache-2.0, see LICENSE+NOTICE)
-- The shared commons an "oracle" agent should stand on: legible state,
-- multi-writer handoff, and a lane to escalate hard questions to a bigger tier.
-- Blackboard architecture (Hearsay-II, 1970s) for LLM agent seats.
-- Canonical write-up + the SOUL it pairs with: https://livingsys.org/resources/agent-constitution
-- ============================================================================

-- 1) COORDINATION — the seat-to-seat status board. "Who is doing what."
--    Each agent/chat writes its own rows; everyone reads all of them.
CREATE TABLE IF NOT EXISTS coordination (
  id         bigserial PRIMARY KEY,
  agent      text NOT NULL,          -- 'coordinator', 'laptop-seat', 'frontier', ...
  focus      text,                   -- what this seat is working on
  status     text DEFAULT 'active',  -- active | blocked | fyi | done
  note       text,
  ref        text,
  created_at timestamptz DEFAULT now()
);

-- 2) REGISTRY — legible shared FACTS. This is the "ACME is added" fix:
--    instead of poking the oracle four times, you add ONE row everyone can see.
CREATE TABLE IF NOT EXISTS registry (
  id          bigserial PRIMARY KEY,
  entity      text UNIQUE NOT NULL,  -- 'ACME'
  kind        text,                  -- 'organisation'
  added_by    text,
  approved_by text,                  -- governance: who authorised it
  source_url  text,                  -- provenance
  visibility  text DEFAULT 'commons',
  created_at  timestamptz DEFAULT now()
);

-- 3) ESCALATIONS — hand a hard question to a bigger tier; the answer returns HERE.
--    frozen small model posts -> frontier (a bigger model or a human) answers back.
CREATE TABLE IF NOT EXISTS escalations (
  id          bigserial PRIMARY KEY,
  from_agent  text NOT NULL,
  topic       text,
  prompt      text NOT NULL,
  status      text DEFAULT 'needs_help',  -- needs_help -> claimed -> answered
  claimed_by  text,
  answer      text,
  answered_by text,
  visibility  text DEFAULT 'commons',
  holon       text DEFAULT 'public',      -- which sovereign owns this row (for RLS)
  created_at  timestamptz DEFAULT now(),
  answered_at timestamptz
);

-- 4) TICKETS — a unit of work on the board. open -> claimed -> delivered ->
--    critiqued -> closed. Any seat opens one; any seat claims it; the deliverable
--    and the critique are legible to everyone the row's visibility allows.
CREATE TABLE IF NOT EXISTS tickets (
  id          bigserial PRIMARY KEY,
  title       text NOT NULL,
  body        text,
  status      text DEFAULT 'open',    -- open -> claimed -> delivered -> critiqued -> closed
  opened_by   text NOT NULL,
  claimed_by  text,
  deliverable text,
  critique    text,
  visibility  text DEFAULT 'commons',
  holon       text DEFAULT 'public',  -- which sovereign owns a private ticket (for RLS)
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

-- 5) HANDOFFS — the baton. Do your leg, pass the next leg to a NAMED seat.
--    Addressed by SEAT (to_seat), not by session id, so it survives churn + sleep:
--    the seat is the identity, the session number is just today's address.
--    pending -> accepted -> done | passed.
CREATE TABLE IF NOT EXISTS handoffs (
  id          bigserial PRIMARY KEY,
  task        text NOT NULL,          -- the baton label, carried across passes
  from_seat   text NOT NULL,          -- who hands off
  to_seat     text NOT NULL,          -- the seat taking the next leg
  summary     text,                   -- what was done
  need        text,                   -- what is needed next
  refs        text,                   -- bus rows / files / links
  status      text DEFAULT 'pending', -- pending -> accepted -> done | passed
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

-- 6) TAGS — the credit ledger for the coordination game (05-coordination-game.md).
--    One row per system-applied credit event (a delivery, a check). Append-only:
--    credit is earned by completed cross-holon work, never self-declared.
CREATE TABLE IF NOT EXISTS tags (
  id         bigserial PRIMARY KEY,
  holon      text NOT NULL,           -- who earned the credit
  tag        text NOT NULL,           -- 'delivered' | 'checked' | ...
  ref        text,                    -- the ticket/event it came from
  visibility text DEFAULT 'commons',  -- credit = public bragging rights by default
  created_at timestamptz DEFAULT now()
);

-- ============================================================================
-- THE "EYES" — Row-Level Security = capability-not-capacity.
-- A seat connecting as this role sees COMMONS rows + only its OWN holon's rows.
-- This is where sovereignty lives: not in the agent's SOUL, but in what each
-- call is allowed to SEE. Apply the same pattern to every lane you want scoped.
-- ============================================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='membrane_app') THEN
    CREATE ROLE membrane_app NOLOGIN;
  END IF;
END $$;

ALTER TABLE escalations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS commons_or_mine ON escalations;
CREATE POLICY commons_or_mine ON escalations
  USING (visibility = 'commons' OR holon = current_setting('app.holon', true));

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO membrane_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO membrane_app;
-- A seat then sets its scope per-connection:  SET app.holon = 'acme';
