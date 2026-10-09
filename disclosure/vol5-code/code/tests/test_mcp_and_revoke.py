"""Tests for membrane-mcp.patched.py (identity bound from the connection,
refuse unscoped connections) and revoke-seat.sql (live sessions end).
Apache-2.0. Uses a stand-in for fastmcp so the tool functions can be called
directly; the database is a local throwaway."""
from __future__ import annotations
import importlib.util, os, subprocess, sys, types, unittest

import psycopg
import _pg

# stand-in for fastmcp: @mcp.tool returns the plain function
fake = types.ModuleType("fastmcp")


class _FastMCP:
    def __init__(self, name): self.name = name
    def tool(self, f): return f
    def run(self): pass


fake.FastMCP = _FastMCP
sys.modules.setdefault("fastmcp", fake)


def load_server(dsn: str):
    os.environ["MEMBRANE_DSN"] = dsn
    spec = importlib.util.spec_from_file_location("membrane_mcp_patched", _pg.CODE / "membrane-mcp.patched.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class McpIdentity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = _pg.fresh_db([_pg.CODE / "01-schema.sql", _pg.CODE / "03-hardening.patched.sql"])
        admin, _ = _pg.admin_uri_and_psql()
        with psycopg.connect(_pg._with(admin, cls.db.rsplit("/", 1)[1]), autocommit=True) as c:
            for r in ("mcp_a", "mcp_b", "mcp_ghost"):
                c.execute(f"DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{r}') "
                          f"THEN CREATE ROLE {r} LOGIN IN ROLE membrane_app; END IF; END $$")
            c.execute("INSERT INTO holon_roles VALUES ('mcp_a','a'), ('mcp_b','b')")
        cls.admin_db = _pg._with(admin, cls.db.rsplit("/", 1)[1])

    def test_refuses_superuser_and_unmapped(self):
        m = load_server(self.admin_db)                     # the published default: owner/superuser
        with self.assertRaises(m.UnscopedConnection) as e:
            m.assert_scoped()
        self.assertIn("SUPERUSER", str(e.exception))
        g = load_server(_pg._with(self.db, user="mcp_ghost"))
        with self.assertRaises(g.UnscopedConnection):
            g.assert_scoped()

    def test_identity_comes_from_the_connection(self):
        a = load_server(_pg._with(self.db, user="mcp_a"))
        self.assertEqual(a.whoami(), {"seat": "mcp_a", "holon": "a"})
        self.assertEqual(a.bus_post("checking identity")[0]["agent"], "mcp_a")
        eid = a.escalate("q", "should we fine-tune or retrieve?")[0]["id"]
        b = load_server(_pg._with(self.db, user="mcp_b"))
        self.assertEqual(b.claim(eid)[0]["claimed_by"], "mcp_b")
        self.assertEqual(b.answer(eid, "Retrieve.")[0]["answered_by"], "mcp_b")
        tid = a.ticket_open("summarise notes")[0]["id"]
        b.ticket_claim(tid)
        b.ticket_deliver(tid, "three lines")
        with self.assertRaises(psycopg.Error):              # deliverer cannot check itself
            b.ticket_critique(tid, "looks great", "endorse")
        self.assertEqual(a.ticket_critique(tid, "source for line 2?")[0]["critic"], "mcp_a")
        h = a.handoff_send("baton", "b", "leg one")[0]
        self.assertEqual(h["from_seat"], "a")
        self.assertEqual([r["id"] for r in b.handoff_inbox()], [h["id"]])
        import inspect
        for fn in (a.bus_post, a.escalate, a.answer, a.ticket_open, a.ticket_claim, a.handoff_send,
                   a.handoff_inbox, a.handoff_accept):
            params = set(inspect.signature(fn).parameters)
            self.assertFalse(params & {"agent", "from_agent", "answered_by", "claimed_by",
                                       "opened_by", "from_seat", "seat"}, fn.__name__)


class Revocation(unittest.TestCase):
    def test_revoke_ends_live_session_blocks_new_ones_and_closes_the_edge(self):
        db = _pg.fresh_db([_pg.CODE / "01-schema.sql", _pg.CODE / "03-hardening.patched.sql",
                           _pg.CODE / "edge" / "edge-roles.sql"])
        admin, psql = _pg.admin_uri_and_psql()
        admin_db = _pg._with(admin, db.rsplit("/", 1)[1])
        with psycopg.connect(admin_db, autocommit=True) as c:
            c.execute("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rv_seat') "
                      "THEN CREATE ROLE rv_seat LOGIN IN ROLE membrane_app; END IF; END $$")
            c.execute("ALTER ROLE rv_seat LOGIN")
            c.execute("GRANT rv_seat TO authenticator")              # the edge may assume this seat
        live = psycopg.connect(_pg._with(db, user="rv_seat"), autocommit=True)
        self.addCleanup(live.close)
        live.execute("SELECT 1")
        r = subprocess.run([psql, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-v", "seat=rv_seat",
                            "-f", str(_pg.CODE / "revoke-seat.sql"), "-d", admin_db],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        with self.assertRaises(psycopg.OperationalError):
            live.execute("SELECT 1")                        # the open session was terminated
        with self.assertRaises(psycopg.OperationalError):
            psycopg.connect(_pg._with(db, user="rv_seat"))  # and no new one is allowed
        with psycopg.connect(admin_db, autocommit=True) as c:
            member = c.execute("SELECT pg_has_role('authenticator', 'rv_seat', 'MEMBER')").fetchone()[0]
            self.assertFalse(member)                        # the edge can no longer assume the seat
            self.assertEqual(c.execute("SELECT count(*) FROM revoked_seats WHERE rolename = 'rv_seat'")
                             .fetchone()[0], 1)             # deny list holds it until tokens expire
            c.execute("SELECT set_config('request.jwt.claims', '{\"role\": \"rv_seat\"}', false)")
            with self.assertRaises(psycopg.errors.InsufficientPrivilege):
                c.execute("SELECT edge_pre_request()")      # a still-valid token is refused
            c.execute("SELECT set_config('request.jwt.claims', '{\"role\": \"web_anon\"}', false)")
            c.execute("SELECT edge_pre_request()")          # others pass


if __name__ == "__main__":
    unittest.main()
