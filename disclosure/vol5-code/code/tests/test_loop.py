"""Tests for interlock_loop.py: the loop contract (Section B) and the teaching
mechanics (Section D), run as loop_alice against a local throwaway store.
Apache-2.0."""
from __future__ import annotations
import unittest

import _pg
import interlock_loop as L
from interlock_loop import Evidence, Expression, ItemResult

PREREQS = {"equal_parts": [], "equivalent": ["equal_parts"],
           "common_denom": ["equivalent"], "add_unlike": ["common_denom"]}


def render(concept, strategy, level, modality, seed):
    # stand-in for any generator; deterministic so the hash is re-derivable
    return Expression(f"[{concept}|{strategy}|L{level}|{modality}|seed {seed}]", "test-generator", seed, 0.0)


class SimLearner:
    """A learner who knows some concepts. A concept is learned the first time it
    is taught while all its prerequisites are known. Errors on a concept whose
    prerequisite is missing are tagged prereq:<missing>."""

    def __init__(self, known, stuck=False):
        self.known, self.stuck = set(known), stuck

    def __call__(self, expr, concept, strategy, modality):
        missing = [p for p in PREREQS[concept] if p not in self.known]
        if not missing and not self.stuck:
            self.known.add(concept)
        if concept in self.known:
            return Evidence([ItemResult(concept, True) for _ in range(10)], modality)
        tag = [f"prereq:{missing[0]}"] if missing else []
        ok = {0, 3, 5, 8}                       # errors spread evenly (no fade)
        items = [ItemResult(concept, i in ok, [] if i in ok else tag) for i in range(10)]
        return Evidence(items, modality)


class DiagnosisTable(unittest.TestCase):
    def ev(self, items, **kw):
        return Evidence(items, "text", **kw)

    def test_each_cause_signature(self):
        att = self.ev([ItemResult("c", False, blank=True)] * 4 + [ItemResult("c", True)] * 6)
        self.assertEqual(L.diagnose(att)[0], "attention")
        pre = self.ev([ItemResult("c", False, ["prereq:p"])] * 5 + [ItemResult("c", True)] * 5)
        self.assertEqual(L.diagnose(pre)[:2], ("missing_prerequisite", "p"))
        voc = self.ev([ItemResult("c", False, ["term"])] * 5 + [ItemResult("c", True)] * 5)
        self.assertEqual(L.diagnose(voc)[0], "vocabulary_gap")
        abs_ = self.ev([ItemResult("c", i % 2 == 0, abstraction="concrete" if i % 2 == 0 else "abstract")
                        for i in range(10)])
        self.assertEqual(L.diagnose(abs_)[0], "abstraction_level")
        fmt = self.ev([ItemResult("c", i in (0, 3, 5, 8)) for i in range(10)], best_other_modality_score=0.9)
        self.assertEqual(L.diagnose(fmt)[0], "format_mismatch")
        unk = self.ev([ItemResult("c", i in (0, 3, 5, 8)) for i in range(10)])
        self.assertEqual(L.diagnose(unk)[0], "unknown")

    def test_assessment_contract(self):
        a = L.assess(self.ev([ItemResult("c", True)] * 9 + [ItemResult("c", False)]), 0.9)
        self.assertEqual((a.passed, a.score, a.cause), (True, 0.9, "none"))

    def test_bandit_prefers_what_worked_for_this_learner(self):
        tally = {}
        self.assertEqual(L.choose_strategy("vocabulary_gap", tally), "define_terms_first")
        tally[("vocabulary_gap", "define_terms_first")] = (4, 0)
        self.assertEqual(L.choose_strategy("vocabulary_gap", tally), "glossary_with_examples")
        tally[("vocabulary_gap", "glossary_with_examples")] = (4, 4)
        self.assertEqual(L.choose_strategy("vocabulary_gap", tally), "glossary_with_examples")

    def test_precedence_and_profile(self):
        skill = {"default_level": 3, "modality": "worked_example"}
        self.assertEqual(L.presentation(skill, {"modality": "audio"}, 2, None, "baseline", None),
                         (3, "worked_example"))                       # skill file beats profile
        self.assertEqual(L.presentation(skill, {}, 2, "abstraction_level", "concrete_first", 3)[0], 2)
        self.assertEqual(L.presentation({}, {"modality": "audio"}, 2, None, "baseline", None)[1], "audio")
        p = L.update_profile({}, {"latency": True}, {"latency": 1.0, "experiential": 1.0})
        self.assertIn("latency", p)
        self.assertNotIn("experiential", p)                           # no consent, no signal
        self.assertAlmostEqual(L.decay({"latency": 1.0}, 30)["latency"], 0.75)


class LoopAgainstStore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = _pg.shared_interlock_db()

    def store(self, user):
        c = _pg.connect_as(self.db, user)
        self.addCleanup(c.close)
        return L.PgStore(c)

    def test_backtrack_then_mastery_writes_both_sides(self):
        s = self.store("loop_alice")
        res = L.run_goal(s, "fractions-101", render,
                         SimLearner({"equal_parts", "equivalent"}), "add_unlike")
        self.assertEqual(res.status, "mastered")
        self.assertEqual([p[0] for p in res.path], ["add_unlike", "common_denom", "add_unlike"])
        auth = self.store("a_school")
        codes = [r["guidance_code"] for r in auth.q("SELECT guidance_code FROM monitoring ORDER BY id")]
        self.assertIn("prereq_gap", codes)
        self.assertEqual(codes[-1], "ready_to_advance")
        self.assertEqual(auth.q("SELECT count(*) AS n FROM skill_file")[0]["n"], 0)
        alice = self.store("p_alice")
        self.assertGreaterEqual(len(alice.q("SELECT achievements FROM skill_file")[0]["achievements"]), 1)
        # the prerequisite pass is recorded as remediation evidence the authority can count
        rem = auth.q("SELECT strategy, remediated FROM monitoring WHERE remediated ORDER BY id DESC LIMIT 1")
        self.assertEqual(rem[0]["strategy"], "backtrack_prerequisite")
        # hashes recorded for re-derivation
        self.assertTrue(all(len(r["expression_sha256"]) == 64
                            for r in s.q("SELECT expression_sha256 FROM loop_attempt")))

    def test_finds_what_works_by_changing_approach(self):
        """A learner who only gets it from a picture. No repetition: the loop comes
        back around with different approaches until one lands."""
        class VisualOnly(SimLearner):
            def __call__(self, expr, concept, strategy, modality):
                if modality == "visual":
                    self.known.add(concept)
                if concept in self.known:
                    return Evidence([ItemResult(concept, True) for _ in range(10)], modality)
                return Evidence([ItemResult(concept, i in (0, 3, 5, 8)) for i in range(10)], modality)
        s = self.store("loop_alice")
        res = L.run_goal(s, "fractions-101", render, VisualOnly(set()), "equal_parts")
        self.assertEqual(res.status, "mastered")
        self.assertIn("switch_modality", [p[1] for p in res.path])
        strategies = [p[1] for p in res.path]
        self.assertEqual(len(strategies), len(set(strategies)))          # never the same approach twice here
        tally = s.q("SELECT successes FROM strategy_tally WHERE strategy = 'switch_modality'")
        self.assertEqual(tally[0]["successes"], 1)                         # the loop remembers what worked

    def test_never_declared_stuck_help_is_only_offered(self):
        s = self.store("loop_alice")
        res = L.run_goal(s, "fractions-101", render, SimLearner(set(), stuck=True), "equal_parts",
                         session_attempts=30, accept_help=lambda concept: False)
        self.assertEqual(res.status, "active")                             # the goal persists
        self.assertEqual(res.help_id, None)                                # learner declined the offer
        self.assertGreaterEqual(res.help_offered, 2)
        g = s.q("SELECT id, status FROM loop_goal ORDER BY id DESC LIMIT 1")[0]
        self.assertEqual(g["status"], "active")
        hashes = [r["expression_sha256"] for r in
                  s.q("SELECT expression_sha256 FROM loop_attempt WHERE goal_id = %s", (g["id"],))]
        self.assertEqual(len(hashes), len(set(hashes)))                    # no identical content, ever
        seeds = {r["seed"] for r in s.q("SELECT seed FROM loop_attempt WHERE goal_id = %s", (g["id"],))}
        self.assertGreater(len(seeds), 1)                                  # repeats were re-varied
        codes = {r["guidance_code"] for r in s.q("SELECT guidance_code FROM monitoring WHERE goal_id = %s", (g["id"],))}
        self.assertTrue({"new_approach", "help_offered"} <= codes)
        self.assertEqual(s.q("SELECT count(*) AS n FROM help_record WHERE goal_id = %s", (g["id"],))[0]["n"], 0)

    def test_offer_taken_then_declines_reopen_then_request_parks_goal_stays_open(self):
        s = self.store("loop_alice")
        res = L.run_goal(s, "fractions-101", render, SimLearner(set(), stuck=True), "equal_parts",
                         session_attempts=12, accept_help=lambda concept: True)
        self.assertEqual(res.status, "active")
        kim, lee = self.store("tutor_kim"), self.store("tutor_lee")
        rows = kim.q("SELECT reason FROM help_record WHERE id = %s", (res.help_id,))
        self.assertEqual(rows[0]["reason"], "offer_accepted")
        kim.q("UPDATE help_record SET status = 'declined' WHERE id = %s", (res.help_id,))
        self.assertEqual(L.readdress(s, res.help_id), "lee")
        lee.q("UPDATE help_record SET status = 'declined' WHERE id = %s", (res.help_id,))
        self.assertEqual(L.readdress(s, res.help_id), "parked")
        h = s.q("SELECT status, passes, declined_by, park_reason, goal_id FROM help_record WHERE id = %s",
                (res.help_id,))[0]
        self.assertEqual((h["status"], h["passes"], h["declined_by"], h["park_reason"]),
                         ("parked", 2, ["kim", "lee"], "no_seat_accepted"))
        # the REQUEST is parked; the learner's goal is still open
        self.assertEqual(s.q("SELECT status FROM loop_goal WHERE id = %s", (h["goal_id"],))[0]["status"], "active")


PUMP = {"concepts": {"parts": [], "priming": ["parts"], "seals": ["parts"]}}


class PumpLearner(SimLearner):
    def __call__(self, expr, concept, strategy, modality):
        missing = [p for p in PUMP["concepts"][concept] if p not in self.known]
        if not missing and not self.stuck:
            self.known.add(concept)
        if concept in self.known:
            return Evidence([ItemResult(concept, True) for _ in range(10)], modality)
        tag = [f"prereq:{missing[0]}"] if missing else []
        ok = {0, 3, 5, 8}
        return Evidence([ItemResult(concept, i in ok, [] if i in ok else tag) for i in range(10)], modality)


class NoAuthority(unittest.TestCase):
    """A learner and the AI alone: no institution, no course, no lesson plan."""

    @classmethod
    def setUpClass(cls):
        cls.db = _pg.shared_interlock_db()

    def store(self, user):
        c = _pg.connect_as(self.db, user)
        self.addCleanup(c.close)
        return L.PgStore(c)

    def test_learner_and_ai_alone(self):
        s = self.store("loop_carol")
        res = L.run_goal(s, None, render, PumpLearner(set()), "seals",
                         goal_text="Maintain the hand pump (open manual)", goal_source="open_corpus",
                         plan=PUMP, helpers=["kim"])
        self.assertEqual(res.status, "mastered")
        self.assertEqual([p[0] for p in res.path], ["seals", "parts", "seals"])
        kim = self.store("tutor_kim")
        self.assertEqual(kim.q("SELECT guidance_code FROM monitoring WHERE holon = 'carol' ORDER BY id DESC LIMIT 1")
                         [0]["guidance_code"], "ready_to_advance")
        school = self.store("a_school")
        self.assertEqual(school.q("SELECT count(*) AS n FROM monitoring WHERE holon = 'carol'")[0]["n"], 0)

    def test_narrative_goes_only_to_engines_the_holder_chose(self):
        carol, loop = self.store("p_carol"), self.store("loop_carol")
        carol.q("UPDATE skill_file SET readable_by_engines = ARRAY['local:small-model']")
        self.assertIn("narrative", L.skill_context_for_engine(loop, "local:small-model"))
        hosted = L.skill_context_for_engine(loop, "hosted:big-model")
        self.assertNotIn("narrative", hosted)
        self.assertEqual(hosted["params"]["modality"], "visual")
        carol.q("UPDATE skill_file SET readable_by_engines = '{}'")

    def test_alone_with_no_helper_keeps_going(self):
        s = self.store("loop_carol")
        res = L.run_goal(s, None, render, PumpLearner(set(), stuck=True), "parts",
                         goal_text="Name the pump parts", plan=PUMP, helpers=[], session_attempts=15)
        self.assertEqual((res.status, res.help_id, res.help_offered), ("active", None, 0))


if __name__ == "__main__":
    unittest.main()
