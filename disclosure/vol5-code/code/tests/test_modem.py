"""Tests for modem_gate.py (Section C). Apache-2.0. No database needed."""
from __future__ import annotations
import json, random, tempfile, unittest
from pathlib import Path

import _pg  # noqa: F401  (puts code/ on sys.path)
import modem_gate as M

CORPUS = ("A shared board lets many seats read and write the same state. "
          "The store decides who sees each row, so a prompt cannot change the rule.")

NODE = {
    "id": "0123456789abcdef", "title": "The rule lives in the store",
    "summary": "The store, not the prompt, decides who sees each row.",
    "propositions": [
        {"id": "p1", "text": "access is decided by the store", "key_terms": ["store|database"]},
        {"id": "p2", "text": "per row", "key_terms": ["row|record|line"]},
        {"id": "p3", "text": "instructions cannot change it", "key_terms": ["cannot|can't", "rule"]},
    ],
    "provenance": {"doc_id": "corpus", "doc_sha256": M.sha256(CORPUS), "start": 62, "end": len(CORPUS)},
    "parent": None, "children": [], "lane": "general", "depth": 1,
    "derivation": {"cache_key": "x", "extractor": "t", "prompt_sha256": "y"},
}


class Gate(unittest.TestCase):
    def test_node_schema(self):
        self.assertEqual(M.validate_node(NODE), [])
        bad = dict(NODE, provenance=dict(NODE["provenance"], start=10, end=5))
        self.assertTrue(M.validate_node(bad))

    def test_pass_fail_and_drift_span(self):
        good = "The database checks each row. Words typed at the machine cannot change that rule."
        self.assertEqual(M.gate(NODE, good, 2).verdict, "pass")
        bad = "The database checks each row. It is very safe."
        g = M.gate(NODE, bad, 2)
        self.assertEqual(g.verdict, "fail")
        self.assertEqual(g.missing, ["p3"])
        self.assertIsNotNone(g.drift_span)

    def test_level_limits(self):
        long = ("The persistence layer evaluates authorization predicates individually for every "
                "record retrieved, independently of any instruction the conversational agent ingests, "
                "therefore the rule cannot be changed by prompts in the database row.")
        g = M.gate(NODE, long, 0)
        self.assertEqual(g.verdict, "fail")
        self.assertIn("L0", g.reason)
        self.assertEqual(M.gate(NODE, long, 4).verdict, "pass")      # fine for a practitioner
        self.assertEqual(M.gate(NODE, CORPUS, 6).verdict, "pass")

    def test_no_belief_target_parameter(self):
        import inspect
        self.assertEqual(list(inspect.signature(M.gate).parameters), ["node", "expression", "level", "judge"])

    def test_regeneration_aims_at_drift(self):
        briefs = []

        def render(node, level, brief):
            briefs.append(brief)
            if brief is None:
                return "The database checks each row. It is very safe."
            # repair only the drift span, keep the rest
            s, e = brief["drift_span"]
            return brief["previous"][:s] + " Typing cannot change that rule." + brief["previous"][e:]
        expr, g, n = M.regenerate_until_pass(NODE, 1, render)
        self.assertEqual(g.verdict, "pass")
        self.assertEqual(n, 1)
        self.assertEqual(briefs[1]["missing"][0]["id"], "p3")
        self.assertTrue(expr.startswith("The database checks each row."))

    def test_gives_up_to_review(self):
        expr, g, n = M.regenerate_until_pass(NODE, 2, lambda node, lv, b: "Nice weather today.")
        self.assertEqual((g.verdict, n), ("review", M.MAX_REGEN))


class Extraction(unittest.TestCase):
    def test_rederivable_despite_nondeterministic_model(self):
        rng = random.Random()

        def flaky_model(prompt, text, params):
            # a model that words its summary differently on every call
            return json.dumps([{"start": 62, "end": text.index("rule.") + 5, "title": "The rule lives in the store",
                                "summary": f"variant {rng.random()}", "propositions": NODE["propositions"]}])
        with tempfile.TemporaryDirectory() as d:
            ex = M.Extractor(Path(d), "model-x", "extract one idea per node", flaky_model)
            a = ex.extract("corpus", CORPUS)
            b = ex.extract("corpus", CORPUS)
            self.assertEqual(a, b)                                    # cache = derivation record
            ex2 = M.Extractor(Path(d), "model-x", "extract one idea per node", flaky_model)
            c = ex2.extract("corpus", CORPUS + " New sentence.")      # corpus changed
            self.assertEqual(a[0]["id"], c[0]["id"])                  # unchanged span keeps its id
            self.assertNotEqual(a[0]["derivation"]["cache_key"], c[0]["derivation"]["cache_key"])


if __name__ == "__main__":
    unittest.main()
