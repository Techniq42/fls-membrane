"""Regression tests for red-team findings that need two live sessions or a
helper's view (redteam/rt_interlock.py R1, help-record masking). The single-
session findings are in sql/20-interlock-tests.sql (T16, RT-*) and
code/tests/test-03-hardening.sql (RT-E1, RT-T1). Apache-2.0. Local DB only."""
from __future__ import annotations
import unittest

import psycopg
import _pg


class EdgeRevocation(unittest.TestCase):
    """RT-R1: an edge session that already ran SET ROLE <seat> must stop acting
    as the seat the moment the seat is revoked, even though its usename is
    'authenticator' and it was never terminated."""

    @classmethod
    def setUpClass(cls):
        cls.db = _pg.shared_interlock_db()
        admin, _ = _pg.admin_uri_and_psql()
        cls.admin_db = _pg._with(admin, cls.db.rsplit("/", 1)[1])

    def _su(self):
        c = psycopg.connect(self.admin_db, autocommit=True)
        self.addCleanup(c.close)
        return c

    def _restore(self):
        with psycopg.connect(self.admin_db, autocommit=True) as su:
            su.execute("ALTER ROLE p_alice LOGIN")
            su.execute("GRANT p_alice TO authenticator")
            su.execute("DELETE FROM revoked_seats WHERE rolename = 'p_alice'")

    def test_membership_revoke_alone_stops_a_switched_edge_session(self):
        self.addCleanup(self._restore)
        edge = _pg.connect_as(self.db, "authenticator", autocommit=True)
        self.addCleanup(edge.close)
        edge.execute("SET ROLE p_alice")
        self.assertEqual(edge.execute("SELECT current_holon()").fetchone()[0], "alice")
        su = self._su()
        su.execute("ALTER ROLE p_alice NOLOGIN")
        su.execute("REVOKE p_alice FROM authenticator")          # exactly what the probe does
        holon, files = edge.execute("SELECT current_holon(), (SELECT count(*) FROM skill_file)").fetchone()
        self.assertIsNone(holon)
        self.assertEqual(files, 0)

    def test_deny_list_alone_stops_a_switched_edge_session(self):
        self.addCleanup(self._restore)
        edge = _pg.connect_as(self.db, "authenticator", autocommit=True)
        self.addCleanup(edge.close)
        edge.execute("SET ROLE p_alice")
        self._su().execute("INSERT INTO revoked_seats (rolename) VALUES ('p_alice')")
        self.assertIsNone(edge.execute("SELECT current_holon()").fetchone()[0])


class HelpRecordMasking(unittest.TestCase):
    """RT-A5 follow-up: a helper sees only the help-record fields the learner granted it."""

    def test_helper_sees_only_granted_fields(self):
        db = _pg.shared_interlock_db()
        with _pg.connect_as(db, "loop_carol", autocommit=True) as c:
            gid = c.execute("INSERT INTO loop_goal (goal_text, goal_source, plan, monitor_to, help_seats) "
                            "VALUES ('Fix the pump seal', 'self', %s, ARRAY['kim'], ARRAY['kim']) RETURNING id",
                            ('{"concepts": {"seals": []}}',)).fetchone()[0]
            c.execute("INSERT INTO help_record (goal_id, addressed_to, concept_key, reason, attempted, causes_tried) "
                      "VALUES (%s, 'kim', 'seals', 'learner_asked', 7, ARRAY['attention'])", (gid,))
        with _pg.connect_as(db, "tutor_kim", autocommit=True) as k:
            row = k.execute("SELECT concept_key, attempted, causes_tried, reason FROM help_record "
                            "WHERE goal_id = %s", (gid,)).fetchone()
        # carol granted kim score, mastery and guidance only
        self.assertEqual(row, (None, None, [], "learner_asked"))


if __name__ == "__main__":
    unittest.main()
