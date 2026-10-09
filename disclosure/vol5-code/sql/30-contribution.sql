-- ============================================================================
-- Volume 5 supplement, sql/30-contribution.sql          (Apache-2.0)
-- Contribution tracking in two tiers (Section E). Runs on top of 00 + 10.
--
--   Tier 1, default for everyone: TAG RECORDS. Who gave what to whom. A
--   non-circulating memory: no balance, no ledger, no settlement. Covers
--   donations, public-domain works, and anything generated internally.
--
--   Tier 2, opt-in for practitioners: ATTRIBUTION. A use event is defined,
--   every generation logs the source chunks it drew on, a weight is computed
--   per (asset, use), an attribution record is written per (contributor,
--   asset, use), and a contributor's share of a period is computed from those
--   weights. Only assets whose holder has opted in produce attribution records.
--
--   Settlement and payment are OUT OF SCOPE. Nothing here moves money or holds
--   a balance. Any payment rail, grant program, or none at all may read these
--   records and decide what, if anything, to do with them.
-- Same rule on every table: commons OR own holon OR named in shared_with.
-- ============================================================================
SET ROLE store_owner;

-- ---- Tier 1: tag records ------------------------------------------------------
CREATE TABLE tag_record (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),   -- who recorded it (giver or receiver)
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  giver       text   NOT NULL,
  receiver    text   NOT NULL,
  kind        text   NOT NULL CHECK (kind IN ('donation','public_domain','internal','labor','knowledge','goods')),
  what        text   NOT NULL,
  source_ref  text   NOT NULL,          -- provenance: receipt id, catalogue id, commit, URL
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (holon IN (giver, receiver))    -- only a party to the gift may record it
);

-- the priority signal (Vol 1 statement 23): how often a holon has given.
-- A count, never a balance; it never decreases and cannot be spent or moved.
CREATE VIEW contribution_signal WITH (security_invoker = true) AS
  SELECT giver AS holon, count(*) AS gifts, max(created_at) AS last_gift
    FROM tag_record GROUP BY giver;

-- ---- Tier 2: attribution (opt-in) ----------------------------------
CREATE TABLE practitioner_optin (
  holon       text PRIMARY KEY DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  license     text   NOT NULL DEFAULT 'CC-BY-4.0',
  opted_in_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE asset (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),   -- the contributor
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  title       text   NOT NULL,
  tier        text   NOT NULL DEFAULT 'tag' CHECK (tier IN ('tag','practitioner')),
  license     text   NOT NULL DEFAULT 'CC-BY-4.0',
  source_sha256 text NOT NULL
);

CREATE TABLE asset_chunk (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  asset_id    bigint NOT NULL REFERENCES asset(id),
  start_char  int    NOT NULL,
  end_char    int    NOT NULL CHECK (end_char > start_char),
  chunk_sha256 text  NOT NULL
);

-- every generation logs the chunk ids retrieval fed it. A USE is a generation
-- that was delivered to a learner AND passed the comprehension gate.
CREATE TABLE generation_log (
  id            bigserial PRIMARY KEY,
  holon         text   NOT NULL DEFAULT current_holon(),  -- the generating party
  visibility    text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with   text[] NOT NULL DEFAULT '{}',
  model_id      text   NOT NULL,
  chunk_ids     bigint[] NOT NULL,
  output_sha256 text   NOT NULL,
  delivered     boolean NOT NULL DEFAULT false,
  gate_passed   boolean NOT NULL DEFAULT false,
  period        text   NOT NULL CHECK (period ~ '^\d{4}-\d{2}$'),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- one row per (contributor, asset, use). Owned by the generating party, shared with the contributor.
CREATE TABLE attribution_record (
  id          bigserial PRIMARY KEY,
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  contributor text   NOT NULL,
  asset_id    bigint NOT NULL REFERENCES asset(id),
  use_id      bigint NOT NULL REFERENCES generation_log(id),
  weight      numeric(9,6) NOT NULL CHECK (weight > 0 AND weight <= 1),
  period      text   NOT NULL,
  UNIQUE (asset_id, use_id)
);

-- per period: how many uses there were, shared with that period's contributors so
-- each can compute and verify their own share. No amount, no balance.
CREATE TABLE attribution_period (
  holon       text   NOT NULL DEFAULT current_holon(),
  visibility  text   NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','commons')),
  shared_with text[] NOT NULL DEFAULT '{}',
  period      text   NOT NULL,
  n_uses      int    NOT NULL CHECK (n_uses >= 0),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (holon, period)
);

-- a remediation that worked, captured as a reusable asset (identity-free by
-- construction: a rendered expression depends on concept, strategy, level and
-- modality, never on who the learner was)
CREATE TABLE remediation_asset (
  id                bigserial PRIMARY KEY,
  holon             text   NOT NULL DEFAULT current_holon(),   -- the authority that rendered it
  visibility        text   NOT NULL DEFAULT 'commons' CHECK (visibility IN ('private','commons')),
  shared_with       text[] NOT NULL DEFAULT '{}',
  concept_key       text   NOT NULL,
  cause             text   NOT NULL,
  strategy          text   NOT NULL,
  level             int    NOT NULL,
  modality          text   NOT NULL,
  expression_sha256 text   NOT NULL,
  expression        text   NOT NULL,
  learners_helped   int    NOT NULL CHECK (learners_helped >= 3),   -- success test: k = 3
  median_gain       numeric(4,3) NOT NULL CHECK (median_gain >= 0.2),
  grounded_in       bigint[] NOT NULL DEFAULT '{}',               -- asset_chunk ids
  license           text   NOT NULL DEFAULT 'CC-BY-4.0',
  attribution       text   NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  t text;
  rule constant text :=
    $r$visibility = 'commons' OR holon = current_holon() OR current_holon() = ANY (shared_with)$r$;
BEGIN
  FOREACH t IN ARRAY ARRAY['tag_record','practitioner_optin','asset','asset_chunk','generation_log',
                           'attribution_record','attribution_period','remediation_asset'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON %I FROM PUBLIC', t);
    EXECUTE format('CREATE POLICY rule_read ON %I FOR SELECT USING (%s)', t, rule);
    EXECUTE format('CREATE POLICY own_insert ON %I FOR INSERT WITH CHECK (holon = current_holon())', t);
  END LOOP;
END $$;

-- record a period's attributions: the generating party computes weights over its
-- OWN uses. Weight of asset a in use u = (chunks of a in u) / (all chunks in u).
-- Chunks from tier-'tag' assets, or from holders who have not opted in, count in
-- the denominator and produce no attribution record.
CREATE FUNCTION record_attributions(p_period text) RETURNS int
LANGUAGE plpgsql AS $f$
DECLARE n int; uses int; contributors text[];
BEGIN
  INSERT INTO attribution_record (shared_with, contributor, asset_id, use_id, weight, period)
  SELECT ARRAY[a.holon], a.holon, a.id, g.id,
         count(*)::numeric / cardinality(g.chunk_ids), p_period
    FROM generation_log g
    CROSS JOIN LATERAL unnest(g.chunk_ids) AS u(chunk_id)
    JOIN asset_chunk c ON c.id = u.chunk_id
    JOIN asset a       ON a.id = c.asset_id
    JOIN practitioner_optin o ON o.holon = a.holon
   WHERE g.holon = current_holon() AND g.period = p_period
     AND g.delivered AND g.gate_passed AND a.tier = 'practitioner'
   GROUP BY a.holon, a.id, g.id, g.chunk_ids;
  GET DIAGNOSTICS n = ROW_COUNT;
  SELECT count(*) INTO uses FROM generation_log
   WHERE holon = current_holon() AND period = p_period AND delivered AND gate_passed;
  SELECT coalesce(array_agg(DISTINCT contributor), '{}') INTO contributors
    FROM attribution_record WHERE holon = current_holon() AND period = p_period;
  INSERT INTO attribution_period (period, n_uses, shared_with) VALUES (p_period, uses, contributors);
  RETURN n;
END $f$;

-- a contributor's share of a period = (sum of the contributor's weights) / (uses in the period).
-- What anyone does with a share (nothing, a grant, a payment) is outside this method.
CREATE VIEW attribution_share WITH (security_invoker = true) AS
  SELECT r.holon AS generating_party, r.period, r.contributor,
         count(*) AS records,
         round(sum(r.weight) / p.n_uses, 6) AS share
    FROM attribution_record r
    JOIN attribution_period p ON p.holon = r.holon AND p.period = r.period
   WHERE p.n_uses > 0
   GROUP BY r.holon, r.period, r.contributor, p.n_uses;

RESET ROLE;

-- grants: everyone may record gifts and read the commons; tier-2 tables by role
-- Writing contribution records is a person's or an institution's act. The
-- loop_runner role is deliberately NOT a contributor: a prompt-injected loop must
-- not be able to write commons text (tag_record.what, asset titles).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'contributor') THEN
    CREATE ROLE contributor NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
GRANT contributor TO participant, authority, human_seat;
GRANT SELECT ON tag_record TO membrane_app;
GRANT INSERT ON tag_record TO contributor;                   -- append-only: no UPDATE/DELETE
GRANT SELECT ON contribution_signal, practitioner_optin, asset, asset_chunk,
                attribution_record, attribution_period, attribution_share, remediation_asset TO membrane_app;
GRANT INSERT ON practitioner_optin, asset, asset_chunk TO contributor;
GRANT SELECT ON generation_log TO membrane_app;            -- the rule, not the grant, withholds it
GRANT INSERT ON generation_log TO authority;
GRANT UPDATE (delivered, gate_passed) ON generation_log TO authority;
CREATE POLICY own_update ON generation_log FOR UPDATE USING (holon = current_holon()) WITH CHECK (holon = current_holon());
GRANT INSERT ON attribution_record, attribution_period, remediation_asset TO authority;
GRANT EXECUTE ON FUNCTION record_attributions(text) TO authority;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO membrane_app;
