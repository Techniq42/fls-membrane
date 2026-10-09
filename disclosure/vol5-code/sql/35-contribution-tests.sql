-- ============================================================================
-- Volume 5 supplement, sql/35-contribution-tests.sql   (Apache-2.0)
-- Run as superuser after 00, 10, 15, 30 on a throwaway database.
-- ============================================================================
\set ON_ERROR_STOP 1
CREATE ROLE prac_ana    LOGIN IN ROLE membrane_app, contributor;   -- a practitioner who opts in
CREATE ROLE lib_archive LOGIN IN ROLE membrane_app, contributor;   -- holds a public-domain text, tier 1 only
INSERT INTO holon_roles VALUES ('prac_ana','ana'), ('lib_archive','archive');

-- ---- Tier 1: tag records -------------------------------------------------------
SET SESSION AUTHORIZATION p_alice;
INSERT INTO tag_record (giver, receiver, kind, what, source_ref)
  VALUES ('alice', 'bob', 'labor', 'fixed the shared fence', 'note:2026-10-01');
SELECT expect_error($$INSERT INTO tag_record (giver, receiver, kind, what, source_ref)
                      VALUES ('kim', 'lee', 'goods', 'x', 'y')$$,
                    'C1 only a party to a gift can record it');
SELECT expect_error($$UPDATE tag_record SET what = 'more'$$, 'C2 tag records are append-only');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION loop_alice;
SELECT expect_error($$INSERT INTO tag_record (giver, receiver, kind, what, source_ref)
                      VALUES ('alice','x','knowledge','I have ADHD (inattentive)','r')$$,
                    'C2b RT-L6: the loop cannot write commons tag text');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION p_alice;
SELECT expect((SELECT gifts FROM contribution_signal WHERE holon = 'alice') = 1,
              'C3 the priority signal is a count of gifts, readable by all');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION lib_archive;
INSERT INTO tag_record (giver, receiver, kind, what, source_ref)
  VALUES ('archive', 'school', 'public_domain', '1911 field manual, scanned', 'catalogue:ARCH-1911-07');
INSERT INTO asset (title, tier, license, source_sha256) VALUES ('1911 field manual', 'tag', 'public-domain', repeat('1',64));
INSERT INTO asset_chunk (asset_id, start_char, end_char, chunk_sha256)
  SELECT id, s, s + 500, repeat('c',64) FROM asset, (VALUES (0), (500)) v(s) WHERE title = '1911 field manual';
RESET SESSION AUTHORIZATION;

-- ---- Tier 2: practitioner opts in -------------------------------------------------
SET SESSION AUTHORIZATION prac_ana;
INSERT INTO practitioner_optin DEFAULT VALUES;
INSERT INTO asset (title, tier, source_sha256) VALUES ('Forty years of clinical notes', 'practitioner', repeat('2',64));
INSERT INTO asset_chunk (asset_id, start_char, end_char, chunk_sha256)
  SELECT id, s, s + 400, repeat('d',64) FROM asset, (VALUES (0), (400)) v(s) WHERE title LIKE 'Forty%';
RESET SESSION AUTHORIZATION;

-- the generating party logs chunk ids per generation; only delivered + gate-passed generations are uses
SET SESSION AUTHORIZATION a_school;
INSERT INTO generation_log (model_id, chunk_ids, output_sha256, delivered, gate_passed, period)
SELECT 'local-small', ARRAY(SELECT c.id FROM asset_chunk c ORDER BY c.id), repeat('e',64), true, true, '2026-10';  -- 2 archive + 2 ana
INSERT INTO generation_log (model_id, chunk_ids, output_sha256, delivered, gate_passed, period)
SELECT 'local-small',
       ARRAY[(SELECT min(c.id) FROM asset_chunk c JOIN asset a ON a.id = c.asset_id WHERE a.holon = 'ana'),
             (SELECT min(c.id) FROM asset_chunk c JOIN asset a ON a.id = c.asset_id WHERE a.holon = 'archive')],
       repeat('f',64), true, true, '2026-10';
INSERT INTO generation_log (model_id, chunk_ids, output_sha256, delivered, gate_passed, period)
SELECT 'local-small', ARRAY[(SELECT max(id) FROM asset_chunk)], repeat('0',64), true, false, '2026-10';      -- failed gate: not a use
SELECT expect(record_attributions('2026-10') = 2, 'C4 one attribution record per (opted-in asset, use)');
SELECT expect((SELECT array_agg(weight ORDER BY use_id) FROM attribution_record) = ARRAY[0.5, 0.5]::numeric[],
              'C5 weight = asset chunks / all chunks in the use');
SELECT expect((SELECT share FROM attribution_share WHERE contributor = 'ana') = 0.5,
              'C6 share = (0.5 + 0.5) / 2 uses = 0.5; the failed-gate generation is not a use');
SELECT expect(NOT EXISTS (SELECT 1 FROM attribution_record WHERE contributor = 'archive'),
              'C7 tier-1 (public domain, no opt-in) never produces an attribution record');
SELECT expect(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                           AND column_name IN ('amount','payout','balance','pool')),
              'C7b no amount, payout, balance or pool column exists: settlement is out of scope');
SELECT expect_error($$INSERT INTO remediation_asset (concept_key, cause, strategy, level, modality, expression_sha256,
                        expression, learners_helped, median_gain, attribution)
                      VALUES ('common_denom','missing_prerequisite','bridge_example',2,'visual',repeat('a',64),
                              'x', 2, 0.3, 'school')$$,
                    'C8 a remediation is captured only after it helped at least 3 learners');
INSERT INTO remediation_asset (concept_key, cause, strategy, level, modality, expression_sha256, expression,
                               learners_helped, median_gain, attribution)
VALUES ('common_denom','missing_prerequisite','bridge_example',2,'visual',repeat('a',64),
        'Halves and thirds both fit into sixths.', 4, 0.35, 'Course fractions-101; grounded in archive 1911 manual');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION prac_ana;
SELECT expect((SELECT count(*) FROM attribution_record) = 2 AND (SELECT share FROM attribution_share) = 0.5,
              'C9 the contributor sees her own attribution records and can verify her share');
SELECT expect((SELECT count(*) FROM generation_log) = 0, 'C10 ... but not the generating party''s generation log');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION p_alice;
SELECT expect((SELECT count(*) FROM attribution_record) = 0, 'C11 a learner sees no attribution records');
SELECT expect((SELECT license FROM remediation_asset) = 'CC-BY-4.0', 'C12 captured remediation is CC BY 4.0 by default and commons-readable');
RESET SESSION AUTHORIZATION;
\echo 'ALL CONTRIBUTION TESTS PASSED'
