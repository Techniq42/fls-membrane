"""
on_device.py - the on-device variant of the interlock (Volume 5, Section A.6).
Apache-2.0.

The canonical skill file, the course content the learner was given, and every
loop record live in a local SQLite file on the participant's device. The loop
runs on the device. The ONLY thing that leaves the device is a monitoring row
with whitelisted fields (score, mastery, guidance_code, concept_key,
iterations), pushed to the shared store through the participant's own seat.
On the device, the per-record rule reduces to the device boundary: one holder,
one file. In the shared store the full rule still applies to what arrives.

Offline operation (Section D.6): the course package carries pre-generated
branches (one rendered expression per concept x strategy x level), so the loop
can run with no network and no model. Scoring is local. The outbox drains when
a connection appears.
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Callable

import interlock_loop as L

WHITELIST = ("score", "mastery", "guidance_code", "concept_key", "iterations")

SCHEMA = """
CREATE TABLE IF NOT EXISTS skill_file (id INTEGER PRIMARY KEY CHECK (id = 1), body TEXT NOT NULL,
  params TEXT NOT NULL DEFAULT '{}', achievements TEXT NOT NULL DEFAULT '[]');
CREATE TABLE IF NOT EXISTS course_package (course_key TEXT PRIMARY KEY, objective TEXT,
  mastery_threshold REAL, rotate_every INTEGER, no_gain_window INTEGER, min_gain REAL,
  concepts TEXT, branches TEXT);
CREATE TABLE IF NOT EXISTS loop_goal (id INTEGER PRIMARY KEY, course_key TEXT, status TEXT,
  remote_goal_id INTEGER);
CREATE TABLE IF NOT EXISTS loop_attempt (id INTEGER PRIMARY KEY, goal_id INTEGER, iteration INTEGER,
  concept_key TEXT, strategy TEXT, cause_targeted TEXT, level INTEGER, modality TEXT,
  expression_sha256 TEXT);
CREATE TABLE IF NOT EXISTS assessment (id INTEGER PRIMARY KEY, attempt_id INTEGER, pass INTEGER,
  score REAL, cause TEXT, cause_concept TEXT, evidence TEXT);
CREATE TABLE IF NOT EXISTS strategy_tally (cause TEXT, strategy TEXT, tries INTEGER, successes INTEGER,
  PRIMARY KEY (cause, strategy));
CREATE TABLE IF NOT EXISTS monitoring_outbox (id INTEGER PRIMARY KEY, goal_id INTEGER, payload TEXT,
  sent INTEGER NOT NULL DEFAULT 0);
"""


class Device:
    def __init__(self, path: str = ":memory:"):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    # ---- the person's file, held here ------------------------------------
    def write_skill_file(self, body: str, params: dict):
        self.db.execute("INSERT OR REPLACE INTO skill_file (id, body, params) VALUES (1, ?, ?)",
                        (body, json.dumps(params)))
        self.db.commit()

    def install_course(self, pkg: dict):
        """pkg: course_key, objective, thresholds, concepts {key: [prereqs]},
        branches {"concept|strategy|level": expression_text} (pre-generated)."""
        self.db.execute("INSERT OR REPLACE INTO course_package VALUES (?,?,?,?,?,?,?,?)",
                        (pkg["course_key"], pkg["objective"], pkg["mastery_threshold"],
                         pkg["rotate_every"], pkg["no_gain_window"], pkg["min_gain"],
                         json.dumps(pkg["concepts"]), json.dumps(pkg["branches"])))
        self.db.commit()

    # ---- the loop, on the device -----------------------------------------
    def run(self, course_key: str, target: str,
            learner: Callable[[L.Expression, str, str, str], L.Evidence],
            session_attempts: int = 24) -> str:
        """One sitting. Returns 'mastered', or 'active' when the sitting ends: the
        goal persists, and nothing on the device parks it but the learner."""
        c = self.db.execute("SELECT * FROM course_package WHERE course_key = ?", (course_key,)).fetchone()
        concepts, branches = json.loads(c["concepts"]), json.loads(c["branches"])
        skill = json.loads(self.db.execute("SELECT params FROM skill_file").fetchone()["params"])
        gid = self.db.execute("INSERT INTO loop_goal (course_key, status) VALUES (?, 'active')",
                              (course_key,)).lastrowid
        tally = {(r["cause"], r["strategy"]): (r["tries"], r["successes"])
                 for r in self.db.execute("SELECT * FROM strategy_tally")}
        stack, cause, strategy, level, prev = [target], None, "baseline", None, None
        tried: dict[str, set[str]] = {}
        for it in range(1, session_attempts + 1):
            concept = stack[-1]
            level, modality = L.presentation(skill, {}, 2, cause, strategy, level)
            text = (branches.get(f"{concept}|{strategy}|{level}")
                    or branches.get(f"{concept}|baseline|{level}")
                    or branches.get(f"{concept}|baseline|2", f"[{concept}]"))
            expr = L.Expression(text, "pre-generated", 0, 0.0)
            tried.setdefault(concept, set()).add(strategy)
            aid = self.db.execute(
                "INSERT INTO loop_attempt (goal_id, iteration, concept_key, strategy, cause_targeted, level,"
                " modality, expression_sha256) VALUES (?,?,?,?,?,?,?,?)",
                (gid, it, concept, strategy, cause, level, modality, expr.sha256)).lastrowid
            a = L.assess(learner(expr, concept, strategy, modality), c["mastery_threshold"])
            self.db.execute("INSERT INTO assessment (attempt_id, pass, score, cause, cause_concept, evidence)"
                            " VALUES (?,?,?,?,?,?)", (aid, a.passed, a.score, a.cause, a.cause_concept,
                                                      json.dumps(a.evidence)))
            if cause is not None:
                ok = a.passed or (prev is not None and a.score - prev >= c["min_gain"])
                t, w = tally.get((cause, strategy), (0, 0))
                tally[(cause, strategy)] = (t + 1, w + int(ok))
                self.db.execute("INSERT OR REPLACE INTO strategy_tally VALUES (?,?,?,?)",
                                (cause, strategy, t + 1, w + int(ok)))
            prev = a.score
            if a.passed and len(stack) == 1:
                self._outbox(gid, a.score, True, "ready_to_advance", concept, it)
                ach = json.loads(self.db.execute("SELECT achievements FROM skill_file").fetchone()[0])
                ach.append({"course": course_key, "concept": concept, "score": a.score})
                self.db.execute("UPDATE skill_file SET achievements = ?", (json.dumps(ach),))
                self.db.execute("UPDATE loop_goal SET status = 'mastered' WHERE id = ?", (gid,))
                self.db.commit()
                return "mastered"
            if a.passed:
                stack.pop(); cause, strategy = None, "baseline"; continue
            if a.cause == "missing_prerequisite" and a.cause_concept in concepts.get(concept, []):
                stack.append(a.cause_concept)
                self._outbox(gid, a.score, False, "prereq_gap", a.cause_concept, it)
                cause, strategy = a.cause, "backtrack_prerequisite"; continue
            cause, strategy = a.cause, L.next_approach(a.cause, tally, tried.get(concept, set()))
            if it % c["rotate_every"] == 0:
                self._outbox(gid, a.score, False, "help_offered", concept, it)
        self.db.commit()
        return "active"

    def _outbox(self, gid, score, mastery, code, concept, iterations):
        payload = {"score": round(float(score), 3), "mastery": bool(mastery), "guidance_code": code,
                   "concept_key": concept, "iterations": iterations}
        assert set(payload) == set(WHITELIST)
        self.db.execute("INSERT INTO monitoring_outbox (goal_id, payload) VALUES (?, ?)",
                        (gid, json.dumps(payload)))

    # ---- sync: only the outbox leaves -------------------------------------
    def sync(self, shared_store) -> int:
        """shared_store: an interlock_loop.PgStore connected AS the participant's
        loop seat. Creates a content-free goal row on first sync, then pushes
        whitelisted monitoring rows. Returns rows sent."""
        sent = 0
        for row in self.db.execute("SELECT o.*, g.course_key, g.remote_goal_id FROM monitoring_outbox o"
                                   " JOIN loop_goal g ON g.id = o.goal_id WHERE o.sent = 0 ORDER BY o.id"
                                   ).fetchall():
            remote = row["remote_goal_id"]
            if remote is None:
                cid = shared_store.q("SELECT id FROM course_context WHERE course_key = %s",
                                     (row["course_key"],))[0]["id"]
                remote = shared_store.q("INSERT INTO loop_goal (course_id, mastery_threshold, rotate_every)"
                                        " VALUES (%s, 0, 0) RETURNING id", (cid,))[0]["id"]
                self.db.execute("UPDATE loop_goal SET remote_goal_id = ? WHERE id = ?", (remote, row["goal_id"]))
            p = json.loads(row["payload"])
            if set(p) - set(WHITELIST):
                raise ValueError("refusing to sync a non-whitelisted field")
            shared_store.q("INSERT INTO monitoring (goal_id, course_id, score, mastery, guidance_code,"
                           " concept_key, iterations) VALUES (%s, 0, %s, %s, %s, %s, %s)",
                           (remote, p["score"], p["mastery"], p["guidance_code"], p["concept_key"],
                            p["iterations"]))
            self.db.execute("UPDATE monitoring_outbox SET sent = 1 WHERE id = ?", (row["id"],))
            sent += 1
        self.db.commit()
        return sent
