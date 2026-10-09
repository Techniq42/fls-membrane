"""On-device variant: loop runs locally, only monitoring syncs. Apache-2.0."""
from __future__ import annotations
import unittest

import _pg
import interlock_loop as L
from on_device import Device
from test_loop import SimLearner

PKG = {"course_key": "fractions-101", "objective": "add unlike fractions",
       "mastery_threshold": 0.9, "rotate_every": 12, "no_gain_window": 3, "min_gain": 0.02,
       "concepts": {"equal_parts": [], "equivalent": ["equal_parts"],
                    "common_denom": ["equivalent"], "add_unlike": ["common_denom"]},
       "branches": {"add_unlike|baseline|2": "To add 1/2 and 1/3, first rename both as sixths...",
                    "common_denom|backtrack_prerequisite|2": "Halves and thirds both fit into sixths..."}}


class OnDevice(unittest.TestCase):
    def test_runs_offline_and_only_monitoring_leaves(self):
        dev = Device()
        dev.write_skill_file("Worked example first. Private medical note stays here.",
                             {"default_level": 2, "modality": "worked_example"})
        dev.install_course(PKG)
        self.assertEqual(dev.run("fractions-101", "add_unlike", SimLearner({"equal_parts", "equivalent"})),
                         "mastered")
        self.assertEqual(dev.db.execute("SELECT count(*) FROM loop_attempt").fetchone()[0], 3)

        db = _pg.shared_interlock_db()
        store = L.PgStore(_pg.connect_as(db, "loop_alice"))
        counts = ("SELECT count(*) AS n FROM loop_attempt", "SELECT count(*) AS n FROM assessment",
                  "SELECT count(*) AS n FROM monitoring WHERE projection_of IS NULL")
        before = {k: store.q(q)[0]["n"] for k, q in zip(("loop_attempt", "assessment", "monitoring"), counts)}
        self.assertEqual(dev.sync(store), 2)                 # prereq_gap + ready_to_advance
        self.assertEqual(dev.sync(store), 0)                 # outbox drained
        after = {k: store.q(q)[0]["n"] for k, q in zip(("loop_attempt", "assessment", "monitoring"), counts)}
        self.assertEqual(after["loop_attempt"], before["loop_attempt"])   # attempts never left
        self.assertEqual(after["assessment"], before["assessment"])
        self.assertEqual(after["monitoring"], before["monitoring"] + 2)
        auth = L.PgStore(_pg.connect_as(db, "a_school"))
        last = auth.q("SELECT score, mastery, guidance_code FROM monitoring ORDER BY id DESC LIMIT 1")[0]
        self.assertEqual((float(last["score"]), last["mastery"], last["guidance_code"]),
                         (1.0, True, "ready_to_advance"))
        store.c.close(); auth.c.close(); dev.db.close()


if __name__ == "__main__":
    unittest.main()
