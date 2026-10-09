"""Unmapped edge role (web_anon) vs patched 03-hardening: the move triggers
skip their checks when current_seat() IS NULL. LOCAL throwaway Postgres only."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "code" / "tests"))
import _pg  # noqa: E402
import psycopg  # noqa: E402

C = _pg.CODE
DB = _pg.fresh_db([C / "01-schema.sql", C / "03-hardening.patched.sql", C / "edge" / "edge-roles.sql"])
uri, _ = _pg.admin_uri_and_psql()
with psycopg.connect(_pg._with(uri, DB.rsplit("/", 1)[-1]), autocommit=True) as su:
    su.execute("DO $$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='rt_seat') THEN "
               "CREATE ROLE rt_seat LOGIN IN ROLE membrane_app; END IF; END$$")
    su.execute("INSERT INTO holon_roles VALUES ('rt_seat','acme') ON CONFLICT DO NOTHING")
with _pg.connect_as(DB, "rt_seat", autocommit=True) as s:
    eid = s.execute("INSERT INTO escalations (from_agent, topic, prompt) VALUES ('','t','q') RETURNING id").fetchone()[0]
    tid = s.execute("INSERT INTO tickets (title, opened_by) VALUES ('t','') RETURNING id").fetchone()[0]
with _pg.connect_as(DB, "authenticator", autocommit=True) as a:
    a.execute("SET ROLE web_anon")
    try:
        r = a.execute("UPDATE escalations SET status='answered', answer='forged by anonymous' WHERE id=%s "
                      "RETURNING status, answer, answered_by", (eid,)).fetchall()
        print("[SUCCEEDED]" if r else "[FAILED]", "E1 anonymous answers a commons escalation:", r)
    except psycopg.Error as e:
        print("[FAILED (blocked)] E1:", str(e).splitlines()[0])
    try:
        r = a.execute("UPDATE tickets SET status='claimed' WHERE id=%s RETURNING status, claimed_by, claimed_holon",
                      (tid,)).fetchall()
        r2 = a.execute("UPDATE tickets SET status='delivered', deliverable='anon' WHERE id=%s RETURNING status, deliverable",
                       (tid,)).fetchall()
        print("[SUCCEEDED]" if r2 else "[FAILED]", "T1 anonymous claims+delivers a commons ticket (no claimer):", r, r2)
    except psycopg.Error as e:
        print("[FAILED (blocked)] T1:", str(e).splitlines()[0])
