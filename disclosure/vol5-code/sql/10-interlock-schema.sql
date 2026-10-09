-- ============================================================================
-- Volume 5 supplement, sql/10-interlock-schema.sql      (Apache-2.0)
-- The interlock as a worked example: the user-held skill file, the authority's
-- course context, the reverse-navigation loop, and the monitoring record, all
-- governed by ONE per-record read rule evaluated by the store.
--
-- Requires sql/00-identity.sql. Run as a superuser on a fresh database:
--   psql -v ON_ERROR_STOP=1 -d interlock -f 00-identity.sql -f 10-interlock-schema.sql
--
-- THE RULE (identical text on every table below):
--     visibility = 'commons'
--  OR holon      = current_holon()
--  OR current_holon() = ANY (shared_with)
--
-- Reads use the rule. Writes are narrower: a seat writes only rows in its own
-- holon, plus a few named moves (claiming or declining a help record addressed
-- to it). Every table is owned by store_owner and has FORCE ROW LEVEL SECURITY,
-- so even the owner reads through the rule. No seat is owner, superuser, or
-- BYPASSRLS; 20-interlock-tests.sql asserts that.
-- ============================================================================

-- ---- roles (group roles; login roles are provisioned per deployment) --------
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['participant','authority','loop_runner','human_seat'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOBYPASSRLS IN ROLE membrane_app', r);
    END IF;
  END LOOP;
END $$;
-- participant : the person. Authors and holds their skill file.
-- authority   : the institution or source. Authors course context, reads monitoring.
-- loop_runner : the reverse-navigation loop. One login role PER participant,
--               mapped in holon_roles to THAT participant's holon, so the loop
--               runs in the participant's scope and nowhere else.
-- human_seat  : a person who answers help records (tutor, instructor, peer).

SET ROLE store_owner;

-- ---- 1. user-held skill file (Vol 1 calls this the SOUL) --------------------
-- Canonical copy lives on the participant's device (see 40-on-device). This row
-- is the OPTIONAL mirror the participant chooses to keep in the shared store.
-- The share switch is (visibility, shared_with), and only the holder can flip it.
CREATE TABLE skill_file (
  id             bigserial PRIMARY KEY,
  holon          text   NOT NULL DEFAULT current_holon(),
  visibility     text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with    text[] NOT NULL DEFAULT '{}',
  -- the visibility switch: visibility = 'private' (OFF, the default) or 'commons' (ON:
  -- readable by anyone on this shared resource). Only the holder can flip it.
  readable_by_engines text[] NOT NULL DEFAULT '{}',   -- model engines the holder lets read the narrative
  version        int    NOT NULL DEFAULT 1,
  body           text   NOT NULL,                 -- the narrative file itself
  params         jsonb  NOT NULL DEFAULT '{}',    -- machine-readable defaults (level, modality, ...)
  achievements   jsonb  NOT NULL DEFAULT '[]',    -- written back by the loop on mastery
  content_sha256 text,                            -- set by trigger; lets a device copy and the mirror be compared
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (holon)
);

-- ---- 2. authority context ---------------------------------------------------
CREATE TABLE course_context (
  id                bigserial PRIMARY KEY,
  holon             text   NOT NULL DEFAULT current_holon(),
  visibility        text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with       text[] NOT NULL DEFAULT '{}',  -- enrolled participant holons
  course_key        text   NOT NULL UNIQUE,
  objective         text   NOT NULL,               -- the flag at the destination
  body              text   NOT NULL DEFAULT '',    -- the authority's narrative context
  mastery_threshold numeric(4,3) NOT NULL DEFAULT 0.900 CHECK (mastery_threshold BETWEEN 0 AND 1),
  rotate_every      int    NOT NULL DEFAULT 12  CHECK (rotate_every > 0),  -- attempts without mastery before a new family of approaches + a help offer (never an end)
  no_gain_window    int    NOT NULL DEFAULT 3   CHECK (no_gain_window > 0),
  min_gain          numeric(4,3) NOT NULL DEFAULT 0.020,
  help_seats        text[] NOT NULL DEFAULT '{}',  -- human seats to escalate to, in order
  max_help_passes   int    NOT NULL DEFAULT 3,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- the learning-object graph (Section D): concepts with prerequisite edges, items tagged to concepts
CREATE TABLE course_concept (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  course_id   bigint NOT NULL REFERENCES course_context(id),
  concept_key text   NOT NULL,
  title       text   NOT NULL,
  prereqs     text[] NOT NULL DEFAULT '{}',   -- concept_keys this concept depends on
  UNIQUE (course_id, concept_key)
);

CREATE TABLE course_item (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  course_id   bigint NOT NULL REFERENCES course_context(id),
  concept_key text   NOT NULL,
  kind        text   NOT NULL CHECK (kind IN ('choice','short','demonstration')),
  prompt      text   NOT NULL,
  answer_key  jsonb  NOT NULL DEFAULT '{}'
);

-- the authority's closed vocabulary for guidance. Monitoring may only carry a code
-- from here, never free text, so nothing derived from a skill file can ride along.
CREATE TABLE guidance_vocab (
  code        text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  meaning     text   NOT NULL
);
-- base codes, owned by the commons, so a goal with NO authority still has a vocabulary.
-- (Inserted before RLS is enabled below; an authority may add its own codes.)
INSERT INTO guidance_vocab (code, holon, visibility, meaning) VALUES
  ('ready_to_advance','public','commons','Mastery reached; advance to the next objective.'),
  ('prereq_gap','public','commons','A prerequisite concept (see concept_key) is being rebuilt.'),
  ('needs_human','public','commons','The loop has asked a human seat for help.'),
  ('in_progress','public','commons','Working; no action needed.'),
  ('new_approach','public','commons','No gain yet; the loop is trying a different family of approaches.'),
  ('help_offered','public','commons','Help from a person was offered to the learner; taking it is the learner''s choice.');

-- ---- 3. loop records (participant holon) ------------------------------------
CREATE TABLE loop_goal (
  id                bigserial PRIMARY KEY,
  holon             text   NOT NULL DEFAULT current_holon(),
  visibility        text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with       text[] NOT NULL DEFAULT '{}',
  course_id         bigint REFERENCES course_context(id),   -- NULL = no authority (section A.9)
  goal_text         text,                                   -- self-set or drawn from an open corpus
  goal_source       text   NOT NULL DEFAULT 'course'
                    CHECK (goal_source IN ('course','self','open_corpus')),
  plan              jsonb  NOT NULL DEFAULT '{}',            -- concept graph when there is no course
  monitor_to        text[] NOT NULL DEFAULT '{}',            -- who receives monitoring (set by the store)
  help_seats        text[] NOT NULL DEFAULT '{}',            -- who may be asked for help (set by the store)
  max_help_passes   int    NOT NULL DEFAULT 3,
  status            text   NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','mastered','escalated','parked')),
  mastery_threshold numeric(4,3) NOT NULL DEFAULT 0.900,
  rotate_every     int    NOT NULL DEFAULT 12,
  created_at        timestamptz NOT NULL DEFAULT now(),
  closed_at         timestamptz
);

CREATE TABLE loop_attempt (
  id                bigserial PRIMARY KEY,
  holon             text   NOT NULL DEFAULT current_holon(),
  visibility        text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with       text[] NOT NULL DEFAULT '{}',
  goal_id           bigint NOT NULL REFERENCES loop_goal(id),
  iteration         int    NOT NULL CHECK (iteration >= 1),
  concept_key       text   NOT NULL,
  strategy          text   NOT NULL CHECK (strategy IN ('baseline','define_terms_first','glossary_with_examples','backtrack_prerequisite','bridge_example','switch_modality','interactive_steps','concrete_first','lower_level','shorter_chunks','single_item_checks','alternative_framing')),
  cause_targeted    text   CHECK (cause_targeted IN ('vocabulary_gap','missing_prerequisite','format_mismatch','abstraction_level','attention','unknown')),
  level             int    NOT NULL CHECK (level BETWEEN 0 AND 6),
  modality          text   NOT NULL CHECK (modality IN ('text','worked_example','visual','audio','interactive')),
  expression_sha256 text   NOT NULL CHECK (expression_sha256 ~ '^[0-9a-f]{64}$'),
  model_id          text   NOT NULL CHECK (model_id ~ '^[a-z0-9][a-z0-9:._-]{0,63}$'),
  seed              bigint,
  temperature       numeric(3,2),
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (goal_id, iteration)
);

CREATE TABLE assessment (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  attempt_id  bigint NOT NULL REFERENCES loop_attempt(id),
  pass        boolean NOT NULL,
  score       numeric(4,3) NOT NULL CHECK (score BETWEEN 0 AND 1),
  cause       text CHECK (cause IN ('none','vocabulary_gap','missing_prerequisite',
                                    'format_mismatch','abstraction_level','attention','unknown')),
  cause_concept text,                -- for missing_prerequisite: the prerequisite concept_key
  evidence    jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- per-learner strategy tally (the meta-learning rule, Section D)
CREATE TABLE strategy_tally (
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  cause       text   NOT NULL CHECK (cause IN ('vocabulary_gap','missing_prerequisite','format_mismatch','abstraction_level','attention','unknown')),
  strategy    text   NOT NULL CHECK (strategy IN ('baseline','define_terms_first','glossary_with_examples','backtrack_prerequisite','bridge_example','switch_modality','interactive_steps','concrete_first','lower_level','shorter_chunks','single_item_checks','alternative_framing')),
  tries       int    NOT NULL DEFAULT 0,
  successes   int    NOT NULL DEFAULT 0,
  PRIMARY KEY (holon, cause, strategy)
);

-- derived learner profile (observed signals). Distinct from the skill file, which
-- the person authors. Precedence rules are in Section D.
CREATE TABLE learner_profile (
  holon       text   PRIMARY KEY DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  signals     jsonb  NOT NULL DEFAULT '{}',
  consent     jsonb  NOT NULL DEFAULT '{}',  -- which signal classes the person allowed
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ---- 4. monitoring: participant-owned, shared with the authority -------------
-- Whitelisted columns only. No text column exists for anything to leak through.
CREATE TABLE monitoring (
  id            bigserial PRIMARY KEY,
  holon         text   NOT NULL DEFAULT current_holon(),
  visibility    text   NOT NULL DEFAULT 'private' CHECK (visibility = 'private'),
  shared_with   text[] NOT NULL DEFAULT '{}',      -- source row: nobody; projection: its one recipient
  goal_id       bigint NOT NULL REFERENCES loop_goal(id),
  course_id     bigint REFERENCES course_context(id),     -- NULL in no-authority mode
  -- A SOURCE row (projection_of IS NULL) holds the full result and is readable by
  -- the learner alone. A PROJECTION row is a copy made by the store for ONE
  -- recipient, holding only the fields the learner granted that recipient; every
  -- other field is NULL from the moment the row exists. Always present on a
  -- projection: id, holon (whose result), goal_id/course_id (which goal), created_at.
  projection_of bigint REFERENCES monitoring(id),
  recipient     text,
  score         numeric(4,3) CHECK (score BETWEEN 0 AND 1),
  mastery       boolean,
  guidance_code text   REFERENCES guidance_vocab(code),
  concept_key   text,                               -- validated against the goal's concept graph
  iterations    int    CHECK (iterations BETWEEN 0 AND 1000),   -- capped: a wide integer is a covert channel
  -- remediation evidence (section E.3): lets the authority COUNT distinct learners
  -- a strategy helped, without reading any loop record. Enumerated or range-checked only.
  strategy      text   CHECK (strategy IN ('baseline','define_terms_first','glossary_with_examples','backtrack_prerequisite','bridge_example','switch_modality','interactive_steps','concrete_first','lower_level','shorter_chunks','single_item_checks','alternative_framing')),
  level         int    CHECK (level BETWEEN 0 AND 6),
  modality      text   CHECK (modality IN ('text','worked_example','visual','audio','interactive')),
  remediated    boolean DEFAULT false,              -- this pass followed a cause-targeted strategy
  gain          numeric(4,3) CHECK (gain BETWEEN -1 AND 1),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---- 4b. what reports contain: decided by the learner, per recipient ---------
-- Plain-words names for every reportable field (commons; shown in the setup screen)
CREATE TABLE report_field (
  field       text PRIMARY KEY CHECK (field IN ('score','mastery','guidance_code','concept_key','iterations','strategy','level','modality','remediated','gain')),
  holon       text   NOT NULL DEFAULT 'public',
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  plain_words text   NOT NULL,
  in_preset   text   NOT NULL CHECK (in_preset IN ('progress_only','progress_plus','by_choice'))
);
INSERT INTO report_field (field, plain_words, in_preset) VALUES
  ('score',         'How well I did on the last check (a number from 0 to 1)', 'progress_only'),
  ('mastery',       'Whether I have got it yet (yes or no)',                    'progress_only'),
  ('strategy',      'Which kind of teaching approach worked',                   'progress_plus'),
  ('modality',      'Which format worked (text, worked example, picture, audio, hands-on)', 'progress_plus'),
  ('level',         'Which reading level I was working at',                     'progress_plus'),
  ('remediated',    'Whether a changed approach is what helped',                'progress_plus'),
  ('gain',          'How much the changed approach helped (a number)',          'progress_plus'),
  ('guidance_code', 'A short status code (working, ready to move on, trying something new)', 'by_choice'),
  ('concept_key',   'Which topic in the course I am on',                        'by_choice'),
  ('iterations',    'How many tries it has taken',                              'by_choice');

-- The learner's grant to one recipient. Mirrors the grants written in the
-- learner's skill file; the store enforces from this table. Default: no row,
-- which means nothing flows. Only the learner writes it; changes apply to the
-- next monitoring row.
CREATE TABLE report_grant (
  holon       text   NOT NULL DEFAULT current_holon(),     -- the learner (holder)
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility = 'private'),
  shared_with text[] NOT NULL DEFAULT '{}',                -- set to the recipient: they see WHICH fields, never why
  recipient   text   NOT NULL,
  fields      text[] NOT NULL DEFAULT '{}' CHECK (fields <@ ARRAY['score','mastery','guidance_code','concept_key','iterations','strategy','level','modality','remediated','gain']::text[]),
  preset      text   NOT NULL DEFAULT 'nothing_yet'
              CHECK (preset IN ('nothing_yet','progress_only','progress_plus','custom')),
  -- authority-defined terms (guidance codes beyond the commons base set, and concept
  -- keys) the learner has reviewed and approved for this recipient. A term not
  -- approved is never projected, so the authority cannot plant a signalling term.
  approved_terms text[] NOT NULL DEFAULT '{}',
  granted_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz,
  PRIMARY KEY (holon, recipient)
);

-- An institution (or any recipient) may REQUEST a field, with a stated reason and an
-- open "required for credit" flag. Shown to enrolled learners. Grants nothing.
CREATE TABLE report_request (
  id                  bigserial PRIMARY KEY,
  holon               text   NOT NULL DEFAULT current_holon(),   -- the requester
  visibility          text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with         text[] NOT NULL DEFAULT '{}',              -- set to the course's enrolled learners
  course_id           bigint NOT NULL REFERENCES course_context(id),
  field               text   NOT NULL REFERENCES report_field(field),
  reason              text   NOT NULL CHECK (length(trim(reason)) > 0),
  required_for_credit boolean NOT NULL DEFAULT false,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (course_id, field)
);

-- ---- 5. help record: the loop asks a human seat ------------------------------
CREATE TABLE help_record (
  id           bigserial PRIMARY KEY,
  holon        text   NOT NULL DEFAULT current_holon(),
  visibility   text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with  text[] NOT NULL DEFAULT '{}',        -- every human seat the request has been shown to
  addressed_to text,                                -- the ONE seat that may act on it now
  goal_id      bigint NOT NULL REFERENCES loop_goal(id),
  concept_key  text,
  reason       text   NOT NULL CHECK (reason IN ('offer_accepted','learner_asked','human_required')),
  attempted    int    CHECK (attempted BETWEEN 0 AND 1000),   -- iterations tried; NULL unless granted
  causes_tried text[] NOT NULL DEFAULT '{}'
               CHECK (causes_tried <@ ARRAY['vocabulary_gap','missing_prerequisite','format_mismatch',
                                            'abstraction_level','attention','unknown']::text[]),
  passes       int    NOT NULL DEFAULT 0,           -- how many seats have declined it
  declined_by  text[] NOT NULL DEFAULT '{}',
  status       text   NOT NULL DEFAULT 'needs_help'
               CHECK (status IN ('needs_help','claimed','declined','answered','parked')),
  claimed_by   text,
  answer       text,
  answered_by  text,
  park_reason  text CHECK (park_reason IN ('no_seat_accepted','pass_limit','no_helper','learner_stopped')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- ---- 6. THE RULE, applied identically to every table ------------------------
DO $$
DECLARE
  t text;
  rule constant text :=
    $r$visibility = 'commons' OR holon = current_holon() OR current_holon() = ANY (shared_with)$r$;
BEGIN
  FOREACH t IN ARRAY ARRAY['skill_file','course_context','course_concept','course_item',
                           'guidance_vocab','loop_goal','loop_attempt','assessment',
                           'strategy_tally','learner_profile','monitoring','help_record',
                           'report_field','report_grant','report_request'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON %I FROM PUBLIC', t);
    -- read: the one rule
    EXECUTE format('CREATE POLICY rule_read ON %I FOR SELECT USING (%s)', t, rule);
    -- write: own holon only
    EXECUTE format('CREATE POLICY own_insert ON %I FOR INSERT WITH CHECK (holon = current_holon())', t);
    EXECUTE format('CREATE POLICY own_update ON %I FOR UPDATE USING (holon = current_holon()) WITH CHECK (holon = current_holon())', t);
  END LOOP;
END $$;

-- the one extra write move: a human seat the request was shown to may act on it.
-- WHICH move it may make (only the current addressee may claim, answer or
-- decline) is decided by the trigger below, which can see OLD and NEW.
-- A seat that declines keeps read access to the request it was already shown.
-- Removing it would make the decliner's own UPDATE fail the read rule on the new
-- row (Postgres checks SELECT policies on the new row when the UPDATE has a
-- WHERE clause), and the request carries no skill-file content.
CREATE POLICY addressee_update ON help_record FOR UPDATE
  USING      (current_holon() = ANY (shared_with))
  WITH CHECK (current_holon() = ANY (shared_with));

-- ---- 7. triggers (INVOKER: they run with the caller's identity and RLS) -----

-- monitoring: bind course + addressee from the goal. The loop cannot choose who
-- sees the record; it always goes to the authority of the goal's course.
-- a concept key is valid for a goal when it is in the course graph (course goal)
-- or in the goal's own plan (no-course goal). Free text cannot pass as a key.
CREATE FUNCTION goal_has_concept(g loop_goal, k text) RETURNS boolean LANGUAGE sql STABLE AS $f$
  -- against the goal's own snapshot of its concept graph (taken when the goal was
  -- created), so a concept the authority adds later cannot become a signal
  SELECT k IS NULL OR (g.plan -> 'concepts') ? k
$f$;

CREATE FUNCTION monitoring_bind() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE g loop_goal; src monitoring; granted text[]; gr report_grant;
BEGIN
  SELECT * INTO g FROM loop_goal WHERE id = NEW.goal_id AND holon = current_holon();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'monitoring: goal % is not in your holon', NEW.goal_id;
  END IF;
  NEW.course_id  := g.course_id;          -- NULL when there is no authority
  NEW.holon      := current_holon();
  NEW.visibility := 'private';
  IF NEW.projection_of IS NULL THEN
    -- SOURCE row: the full result, readable by the learner alone
    IF NEW.score IS NULL OR NEW.mastery IS NULL OR NEW.guidance_code IS NULL OR NEW.iterations IS NULL THEN
      RAISE EXCEPTION 'monitoring: a source row needs score, mastery, guidance_code and iterations';
    END IF;
    IF NOT goal_has_concept(g, NEW.concept_key) THEN
      RAISE EXCEPTION 'monitoring: % is not a concept of this goal', NEW.concept_key;
    END IF;
    NEW.recipient := NULL;
    NEW.shared_with := '{}';
    NEW.created_at := now();                -- the store's clock, not the caller's
    RETURN NEW;
  END IF;
  -- PROJECTION row: copied from the learner's own source row, then masked by the
  -- learner's grant to this recipient. Values supplied by the caller are ignored.
  SELECT * INTO src FROM monitoring
   WHERE id = NEW.projection_of AND holon = current_holon() AND projection_of IS NULL;
  IF NOT FOUND OR src.goal_id <> NEW.goal_id THEN
    RAISE EXCEPTION 'monitoring: projection must copy your own source row of the same goal';
  END IF;
  IF NEW.recipient IS NULL OR NOT NEW.recipient = ANY (g.monitor_to) THEN
    RAISE EXCEPTION 'monitoring: % is not a recipient of this goal', NEW.recipient;
  END IF;
  SELECT * INTO gr FROM report_grant
   WHERE holon = current_holon() AND recipient = NEW.recipient AND revoked_at IS NULL;
  granted := gr.fields;
  IF granted IS NULL OR cardinality(granted) = 0 THEN
    RAISE EXCEPTION 'monitoring: nothing is granted to %', NEW.recipient;
  END IF;
  IF src.created_at < gr.granted_at THEN    -- no retroactive disclosure
    RAISE EXCEPTION 'monitoring: result predates the grant to %', NEW.recipient;
  END IF;
  NEW.shared_with   := ARRAY[NEW.recipient];
  -- numbers are coarsened (0.05 steps) so a projection carries few bits per field;
  -- authority-defined terms pass only if the learner approved them for this recipient
  NEW.score         := CASE WHEN 'score'         = ANY (granted) THEN round(src.score * 20) / 20 END;
  NEW.mastery       := CASE WHEN 'mastery'       = ANY (granted) THEN src.mastery END;
  NEW.guidance_code := CASE WHEN 'guidance_code' = ANY (granted)
                             AND (src.guidance_code IN (SELECT code FROM guidance_vocab WHERE holon = 'public')
                                  OR src.guidance_code = ANY (gr.approved_terms))
                            THEN src.guidance_code END;
  NEW.concept_key   := CASE WHEN 'concept_key'   = ANY (granted) AND src.concept_key = ANY (gr.approved_terms)
                            THEN src.concept_key END;
  NEW.iterations    := CASE WHEN 'iterations'    = ANY (granted) THEN src.iterations END;
  NEW.strategy      := CASE WHEN 'strategy'      = ANY (granted) THEN src.strategy END;
  NEW.level         := CASE WHEN 'level'         = ANY (granted) THEN src.level END;
  NEW.modality      := CASE WHEN 'modality'      = ANY (granted) THEN src.modality END;
  NEW.remediated    := CASE WHEN 'remediated'    = ANY (granted) THEN src.remediated END;
  NEW.gain          := CASE WHEN 'gain'          = ANY (granted) THEN round(src.gain * 20) / 20 END;
  NEW.created_at    := src.created_at;
  RETURN NEW;
END $f$;
CREATE TRIGGER monitoring_bind BEFORE INSERT ON monitoring
  FOR EACH ROW EXECUTE FUNCTION monitoring_bind();

-- after a SOURCE row: one projection per recipient that holds a non-empty grant.
-- No grant, no row: a recipient learns nothing, not even that a result exists.
CREATE FUNCTION monitoring_project() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE r text; g loop_goal;
BEGIN
  IF NEW.projection_of IS NOT NULL THEN RETURN NULL; END IF;
  SELECT * INTO g FROM loop_goal WHERE id = NEW.goal_id;
  FOREACH r IN ARRAY g.monitor_to LOOP
    IF EXISTS (SELECT 1 FROM report_grant WHERE holon = NEW.holon AND recipient = r
                 AND revoked_at IS NULL AND cardinality(fields) > 0) THEN
      INSERT INTO monitoring (goal_id, projection_of, recipient) VALUES (NEW.goal_id, NEW.id, r);
    END IF;
  END LOOP;
  RETURN NULL;
END $f$;
CREATE TRIGGER monitoring_project AFTER INSERT ON monitoring
  FOR EACH ROW EXECUTE FUNCTION monitoring_project();

-- report_grant: addressed to its recipient; an empty field list records a revocation
CREATE FUNCTION report_grant_bind() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  NEW.holon := current_holon();
  NEW.shared_with := ARRAY[NEW.recipient];
  NEW.updated_at := now();
  NEW.revoked_at := CASE WHEN cardinality(NEW.fields) = 0 THEN now() END;
  -- a grant (or any widening of it) covers only results from now on
  IF TG_OP = 'INSERT' OR OLD.revoked_at IS NOT NULL OR NOT (NEW.fields <@ OLD.fields)
     OR NOT (NEW.approved_terms <@ OLD.approved_terms) THEN
    NEW.granted_at := clock_timestamp();
  ELSE
    NEW.granted_at := OLD.granted_at;
  END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER report_grant_bind BEFORE INSERT OR UPDATE ON report_grant
  FOR EACH ROW EXECUTE FUNCTION report_grant_bind();

-- report_request: shown to the course's enrolled learners; only a course owner may ask
CREATE FUNCTION report_request_bind() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE c course_context;
BEGIN
  SELECT * INTO c FROM course_context WHERE id = NEW.course_id AND holon = current_holon();
  IF NOT FOUND THEN RAISE EXCEPTION 'report_request: not your course'; END IF;
  NEW.shared_with := c.shared_with;
  RETURN NEW;
END $f$;
CREATE TRIGGER report_request_bind BEFORE INSERT ON report_request
  FOR EACH ROW EXECUTE FUNCTION report_request_bind();

-- presets the learner can pick and change any time
CREATE FUNCTION set_report_preset(p_recipient text, p_preset text) RETURNS text[]
LANGUAGE plpgsql AS $f$
DECLARE f text[];
BEGIN
  f := CASE p_preset
         WHEN 'nothing_yet'   THEN '{}'::text[]
         WHEN 'progress_only' THEN ARRAY(SELECT field FROM report_field WHERE in_preset = 'progress_only' ORDER BY field)
         WHEN 'progress_plus' THEN ARRAY(SELECT field FROM report_field WHERE in_preset IN ('progress_only','progress_plus') ORDER BY field)
         ELSE NULL END;
  IF f IS NULL THEN RAISE EXCEPTION 'unknown preset %', p_preset; END IF;
  INSERT INTO report_grant (recipient, fields, preset) VALUES (p_recipient, f, p_preset)
  ON CONFLICT (holon, recipient) DO UPDATE SET fields = EXCLUDED.fields, preset = EXCLUDED.preset;
  RETURN f;
END $f$;

-- skill_file: keep the content hash current (device copy and store mirror compare by hash)
CREATE FUNCTION skill_file_hash() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  NEW.content_sha256 := encode(sha256(convert_to(NEW.body, 'UTF8')), 'hex');
  NEW.updated_at := now();
  RETURN NEW;
END $f$;
CREATE TRIGGER skill_file_hash BEFORE INSERT OR UPDATE ON skill_file
  FOR EACH ROW EXECUTE FUNCTION skill_file_hash();

-- loop_goal: with a course, thresholds, monitoring addressee and help seats are
-- copied from the course. With NO course (section A.9), defaults apply and the
-- addressees are limited to helpers the participant named in their own skill
-- file, so text the loop has read cannot add a reader. Status moves forward only.
CREATE FUNCTION plan_shape_ok(p jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_typeof(p) = 'object'
     AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('concepts','target'))
     AND (NOT p ? 'target' OR (p ->> 'target') ~ '^[a-z][a-z0-9_]{0,40}$')
     AND (NOT p ? 'concepts' OR (jsonb_typeof(p -> 'concepts') = 'object' AND NOT EXISTS (
            SELECT 1 FROM jsonb_each(p -> 'concepts') e
             WHERE e.key !~ '^[a-z][a-z0-9_]{0,40}$'
                OR jsonb_typeof(e.value) <> 'array'
                OR EXISTS (SELECT 1 FROM jsonb_array_elements(e.value) x
                            WHERE jsonb_typeof(x) <> 'string' OR (x #>> '{}') !~ '^[a-z][a-z0-9_]{0,40}$'))))
$f$;

CREATE FUNCTION loop_goal_guard() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE c course_context; helpers text[];
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.course_id IS NOT NULL THEN
      SELECT * INTO c FROM course_context WHERE id = NEW.course_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'loop_goal: course % not visible', NEW.course_id; END IF;
      NEW.goal_source       := 'course';
      NEW.goal_text         := c.objective;
      NEW.plan := jsonb_build_object('concepts', coalesce((SELECT jsonb_object_agg(concept_key, to_jsonb(prereqs))
                                                             FROM course_concept WHERE course_id = c.id), '{}'::jsonb));
      NEW.mastery_threshold := c.mastery_threshold;
      NEW.rotate_every     := c.rotate_every;
      NEW.monitor_to        := ARRAY[c.holon];
      NEW.help_seats        := c.help_seats;
      NEW.max_help_passes   := c.max_help_passes;
    ELSE
      IF NEW.goal_source = 'course' THEN NEW.goal_source := 'self'; END IF;
      IF NEW.goal_text IS NULL THEN RAISE EXCEPTION 'loop_goal: a goal with no course needs goal_text'; END IF;
      IF NOT plan_shape_ok(NEW.plan) THEN
        RAISE EXCEPTION 'loop_goal: plan must be {"concepts": {key: [prereq keys]}, "target": key} with short lowercase keys';
      END IF;
      SELECT coalesce(array(SELECT jsonb_array_elements_text(params -> 'helpers')), '{}')
        INTO helpers FROM skill_file WHERE holon = current_holon();
      helpers := coalesce(helpers, '{}');
      IF NOT (NEW.monitor_to <@ helpers AND NEW.help_seats <@ helpers) THEN
        RAISE EXCEPTION 'loop_goal: monitoring and help may go only to helpers named in the skill file (%)', helpers;
      END IF;
      NEW.mastery_threshold := 0.900;     -- defaults; tune locally
      NEW.rotate_every     := 12;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.monitor_to <> OLD.monitor_to OR NEW.help_seats <> OLD.help_seats
     OR NEW.course_id IS DISTINCT FROM OLD.course_id THEN
    RAISE EXCEPTION 'loop_goal: addressees and course are fixed at creation';
  END IF;
  -- persistence: no count closes or parks a goal. Only the learner may set a goal
  -- aside (parked), and a parked goal re-opens. Only mastered is final.
  IF OLD.status = 'mastered' AND NEW.status <> 'mastered' THEN
    RAISE EXCEPTION 'loop_goal: illegal transition % -> %', OLD.status, NEW.status;
  END IF;
  IF NEW.status = 'parked' AND OLD.status <> 'parked'
     AND NOT pg_has_role(current_user, 'participant', 'MEMBER') THEN
    RAISE EXCEPTION 'loop_goal: only the learner can set a goal aside';
  END IF;
  IF NEW.status = 'mastered' AND NEW.closed_at IS NULL THEN NEW.closed_at := now(); END IF;
  IF NEW.status = 'active' THEN NEW.closed_at := NULL; END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER loop_goal_guard BEFORE INSERT OR UPDATE ON loop_goal
  FOR EACH ROW EXECUTE FUNCTION loop_goal_guard();

-- help_record: legal moves only.
--   owner (the loop):  address an open, unaddressed request to a seat that has
--                      not declined (the seat is added to shared_with), or park it
--   addressee:         claim, answer, or decline. A decline re-opens the request
--                      (status needs_help, addressed_to NULL), appends declined_by
--                      and bumps passes.
CREATE FUNCTION help_record_moves() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE me text := current_holon();
BEGIN
  IF NEW.goal_id <> OLD.goal_id OR NEW.holon <> OLD.holon OR NEW.reason <> OLD.reason
     OR NEW.attempted IS DISTINCT FROM OLD.attempted OR NEW.causes_tried <> OLD.causes_tried THEN
    RAISE EXCEPTION 'help_record: the request itself is immutable';
  END IF;
  IF me = OLD.holon THEN                                   -- the asker's loop
    IF OLD.status <> 'needs_help' OR NEW.status NOT IN ('needs_help','parked') THEN
      RAISE EXCEPTION 'help_record: owner may only address or park an open request';
    END IF;
    IF NEW.addressed_to IS DISTINCT FROM OLD.addressed_to THEN
      IF OLD.addressed_to IS NOT NULL THEN
        RAISE EXCEPTION 'help_record: already addressed to %; wait for a decline', OLD.addressed_to;
      END IF;
      IF NOT NEW.addressed_to = ANY (SELECT unnest(help_seats) FROM loop_goal WHERE id = OLD.goal_id) THEN
        RAISE EXCEPTION 'help_record: % is not a help seat for this goal', NEW.addressed_to;
      END IF;
      IF NEW.addressed_to = ANY (OLD.declined_by) THEN
        RAISE EXCEPTION 'help_record: cannot re-address to a seat that declined';
      END IF;
      IF NEW.addressed_to IS NOT NULL THEN
        PERFORM help_record_mask(NEW, NEW.addressed_to);
        NEW := help_record_masked(NEW, NEW.addressed_to);    -- masks only ever narrow
        IF NOT NEW.addressed_to = ANY (OLD.shared_with) THEN
          NEW.shared_with := OLD.shared_with || NEW.addressed_to;
        END IF;
      END IF;
    END IF;
  ELSIF me = OLD.addressed_to THEN                         -- the current addressee
    IF OLD.status = 'needs_help' AND NEW.status = 'claimed' THEN
      NEW.claimed_by := me;
    ELSIF OLD.status IN ('needs_help','claimed') AND NEW.status = 'answered' THEN
      IF NEW.answer IS NULL OR length(NEW.answer) = 0 THEN
        RAISE EXCEPTION 'help_record: an answer needs text';
      END IF;
      NEW.answered_by := me; NEW.claimed_by := COALESCE(OLD.claimed_by, me);
    ELSIF OLD.status IN ('needs_help','claimed') AND NEW.status = 'declined' THEN
      NEW.status       := 'needs_help';
      NEW.claimed_by   := NULL;
      NEW.addressed_to := NULL;
      NEW.passes       := OLD.passes + 1;
      NEW.declined_by  := OLD.declined_by || me;
    ELSE
      RAISE EXCEPTION 'help_record: illegal move % -> % by addressee', OLD.status, NEW.status;
    END IF;
  ELSE
    RAISE EXCEPTION 'help_record: you are not the current addressee';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $f$;
CREATE TRIGGER help_record_moves BEFORE UPDATE ON help_record
  FOR EACH ROW EXECUTE FUNCTION help_record_moves();

-- a help record shows a helper only what the learner granted that helper:
-- concept_key needs 'concept_key' granted AND the term approved; attempted needs
-- 'iterations'; causes_tried needs 'strategy'. No grant at all: no help record.
CREATE FUNCTION help_record_mask(h help_record, seat text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM report_grant WHERE holon = current_holon() AND recipient = seat
                   AND revoked_at IS NULL AND cardinality(fields) > 0) THEN
    RAISE EXCEPTION 'help_record: grant % something first; helpers see only what you grant', seat;
  END IF;
END $f$;
CREATE FUNCTION help_record_masked(h help_record, seat text) RETURNS help_record LANGUAGE plpgsql AS $f$
DECLARE gr report_grant;
BEGIN
  SELECT * INTO gr FROM report_grant WHERE holon = current_holon() AND recipient = seat AND revoked_at IS NULL;
  IF NOT ('concept_key' = ANY (gr.fields) AND h.concept_key = ANY (gr.approved_terms)) THEN h.concept_key := NULL; END IF;
  IF NOT ('iterations' = ANY (gr.fields)) THEN h.attempted := NULL; END IF;
  IF NOT ('strategy' = ANY (gr.fields)) THEN h.causes_tried := '{}'; END IF;
  RETURN h;
END $f$;

-- help_record insert: the first addressee must be a help seat of the goal (the
-- course roster, or helpers the participant named); shared_with starts as that seat.
CREATE FUNCTION help_record_open() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE g loop_goal; seats text[];
BEGIN
  SELECT * INTO g FROM loop_goal WHERE id = NEW.goal_id AND holon = current_holon();
  IF NOT FOUND THEN RAISE EXCEPTION 'help_record: goal % is not yours', NEW.goal_id; END IF;
  seats := g.help_seats;
  IF NOT goal_has_concept(g, NEW.concept_key) THEN
    RAISE EXCEPTION 'help_record: % is not a concept of this goal', NEW.concept_key;
  END IF;
  IF NEW.addressed_to IS NOT NULL AND NOT NEW.addressed_to = ANY (seats) THEN
    RAISE EXCEPTION 'help_record: % is not a help seat for this goal', NEW.addressed_to;
  END IF;
  IF NOT (NEW.causes_tried <@ ARRAY['vocabulary_gap','missing_prerequisite','format_mismatch','abstraction_level','attention','unknown']::text[]) THEN
    RAISE EXCEPTION 'help_record: causes_tried must come from the cause vocabulary';
  END IF;
  NEW.visibility := 'private';
  NEW.answer := NULL; NEW.answered_by := NULL; NEW.claimed_by := NULL; NEW.park_reason := NULL;
  NEW.shared_with := CASE WHEN NEW.addressed_to IS NULL THEN '{}' ELSE ARRAY[NEW.addressed_to] END;
  NEW.status := 'needs_help'; NEW.passes := 0; NEW.declined_by := '{}';
  IF NEW.addressed_to IS NOT NULL THEN
    PERFORM help_record_mask(NEW, NEW.addressed_to);
    NEW := help_record_masked(NEW, NEW.addressed_to);
  END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER help_record_open BEFORE INSERT ON help_record
  FOR EACH ROW EXECUTE FUNCTION help_record_open();

-- ---- dashboard (Section D.7): built ONLY from monitoring, so the authority's
-- view of a hundred paths uses nothing the rule withholds from it.
CREATE VIEW dashboard_paths WITH (security_invoker = true) AS
  SELECT course_id, holon AS learner,
         max(iterations)                                   AS iterations,
         bool_or(mastery)                                  AS mastered,
         (array_agg(guidance_code ORDER BY id DESC))[1]    AS latest_guidance,
         (array_agg(concept_key   ORDER BY id DESC))[1]    AS latest_concept
    FROM monitoring WHERE projection_of IS NOT NULL GROUP BY course_id, holon;

-- expected iterations = cohort median of mastered paths x k (k = 1.5)
CREATE VIEW dashboard_baseline WITH (security_invoker = true) AS
  SELECT course_id,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY iterations)        AS median_iterations,
         1.5 * percentile_cont(0.5) WITHIN GROUP (ORDER BY iterations)  AS expected_iterations
    FROM dashboard_paths WHERE mastered GROUP BY course_id;

-- remediation evidence (section E.3): distinct learners a (concept, strategy,
-- level, modality) helped, and their median gain. Built from monitoring only.
CREATE VIEW remediation_evidence WITH (security_invoker = true) AS
  SELECT course_id, concept_key, strategy, level, modality,
         count(DISTINCT holon) AS learners_helped,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY gain) AS median_gain
    FROM monitoring
   WHERE projection_of IS NOT NULL AND remediated AND strategy IS NOT NULL AND course_id IS NOT NULL
   GROUP BY course_id, concept_key, strategy, level, modality;

-- for a recipient: per enrolled learner and requested field, 'shared' or 'not shared'.
-- A decline is visible as "not shared"; no reason exists anywhere to show.
CREATE VIEW report_status WITH (security_invoker = true) AS
  SELECT q.course_id, l.learner, q.field, q.required_for_credit,
         CASE WHEN q.field = ANY (coalesce(g.fields, '{}')) AND g.revoked_at IS NULL
              THEN 'shared' ELSE 'not shared' END AS status
    FROM report_request q
    JOIN course_context c ON c.id = q.course_id
    CROSS JOIN LATERAL unnest(c.shared_with) AS l(learner)
    LEFT JOIN report_grant g ON g.holon = l.learner AND g.recipient = c.holon;

-- learners stuck on the same prerequisite: a candidate small-group session (>= 3)
CREATE VIEW dashboard_clusters WITH (security_invoker = true) AS
  SELECT course_id, latest_concept AS concept_key, count(*) AS learners,
         array_agg(learner ORDER BY learner) AS who
    FROM dashboard_paths
   WHERE NOT mastered AND latest_guidance IN ('prereq_gap','new_approach','help_offered')
   GROUP BY course_id, latest_concept;

-- ---- 7b. loop records are strictly private ----------------------------------
-- A prompt-injected loop could otherwise mark its own working records commons or
-- share them with the authority. The only outbound paths are the monitoring
-- projection and the help record, both shaped by the learner's grant.
CREATE FUNCTION force_private() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  NEW.visibility := 'private';
  NEW.shared_with := '{}';
  RETURN NEW;
END $f$;
CREATE TRIGGER aa_force_private BEFORE INSERT OR UPDATE ON loop_goal      FOR EACH ROW EXECUTE FUNCTION force_private();
CREATE TRIGGER aa_force_private BEFORE INSERT OR UPDATE ON loop_attempt   FOR EACH ROW EXECUTE FUNCTION force_private();
CREATE TRIGGER aa_force_private BEFORE INSERT OR UPDATE ON assessment     FOR EACH ROW EXECUTE FUNCTION force_private();
CREATE TRIGGER aa_force_private BEFORE INSERT OR UPDATE ON strategy_tally FOR EACH ROW EXECUTE FUNCTION force_private();

-- course_context: an authority may not name itself (or any seat holding no grant)
-- as a help seat to read help records it was never granted
CREATE FUNCTION course_context_guard() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF NEW.holon = ANY (NEW.help_seats) THEN
    RAISE EXCEPTION 'course_context: a course cannot list its own holon as a help seat';
  END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER course_context_guard BEFORE INSERT OR UPDATE ON course_context
  FOR EACH ROW EXECUTE FUNCTION course_context_guard();

RESET ROLE;

-- ---- 8. grants (capability per role; RLS still decides WHICH rows) ----------
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO membrane_app;

-- every seat may try to SELECT everything; the rule decides what comes back.
-- (Granting SELECT broadly is deliberate: it proves the rule, not the grant,
--  is what withholds a skill file from the authority.)
GRANT SELECT ON skill_file, course_context, course_concept, course_item, guidance_vocab,
                loop_goal, loop_attempt, assessment, strategy_tally, learner_profile,
                monitoring, help_record, dashboard_paths, dashboard_baseline, dashboard_clusters, remediation_evidence,
                report_field, report_grant, report_request, report_status
  TO membrane_app;

-- participant: authors the skill file and holds the share switch
GRANT INSERT ON skill_file TO participant;
GRANT UPDATE (body, params, visibility, shared_with, readable_by_engines, version, updated_at) ON skill_file TO participant;
GRANT UPDATE (status) ON loop_goal TO participant;         -- the learner may set a goal aside, or take it up again
GRANT INSERT, UPDATE (fields, preset, approved_terms) ON report_grant TO participant;   -- only the learner grants
GRANT INSERT ON report_request TO authority;
GRANT INSERT, UPDATE ON learner_profile TO participant;            -- consent lives here

-- authority: authors course context, graph, vocabulary
GRANT INSERT, UPDATE ON course_context, course_concept, course_item, guidance_vocab TO authority;

-- loop_runner: runs as the participant. Writes loop records, monitoring, help.
GRANT UPDATE (achievements, updated_at) ON skill_file TO loop_runner;
GRANT INSERT (course_id, goal_text, goal_source, plan, monitor_to, help_seats, mastery_threshold, rotate_every)
  ON loop_goal TO loop_runner;
GRANT UPDATE (status, closed_at) ON loop_goal TO loop_runner;
GRANT INSERT (goal_id, iteration, concept_key, strategy, cause_targeted, level, modality,
              expression_sha256, model_id, seed, temperature) ON loop_attempt TO loop_runner;
GRANT INSERT (attempt_id, pass, score, cause, cause_concept, evidence) ON assessment TO loop_runner;
GRANT INSERT ON monitoring TO loop_runner;          -- every value is rebound or masked by the store
GRANT INSERT (cause, strategy, tries, successes), UPDATE (tries, successes) ON strategy_tally TO loop_runner;
GRANT UPDATE (signals, updated_at) ON learner_profile TO loop_runner;
GRANT INSERT (goal_id, addressed_to, concept_key, reason, attempted, causes_tried) ON help_record TO loop_runner;
GRANT UPDATE (addressed_to, status, park_reason) ON help_record TO loop_runner;

-- human_seat: claim / answer / decline a help record addressed to it. Only the
-- status and answer columns are grantable; the trigger fills claimed_by,
-- answered_by, passes, declined_by and addressed_to itself (column privileges
-- are checked on the SET list, not on columns a trigger rewrites).
GRANT UPDATE (status, answer) ON help_record TO human_seat;

-- Nothing grants UPDATE or DELETE on monitoring, loop_attempt, or assessment:
-- they are append-only for everyone, including the authority.
