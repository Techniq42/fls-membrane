"""Red-team probes against the interlock SQL on a LOCAL throwaway Postgres only.
Run: python redteam/rt_interlock.py   (from supplement-v1.1)
Each probe prints SUCCEEDED (control bypassed) or FAILED (blocked)."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "code" / "tests"))
import _pg  # noqa: E402
import psycopg  # noqa: E402

files = _pg.INTERLOCK + [_pg.SQL / "30-contribution.sql"]
DB = _pg.fresh_db(files)
results = []


def run(seat, sql, args=()):
    with _pg.connect_as(DB, seat, autocommit=True) as c:
        cur = c.execute(sql, args)
        return cur.fetchall() if cur.description else None


def probe(name, fn):
    try:
        ok, detail = fn()
        tag = "SUCCEEDED" if ok else "FAILED (blocked)"
    except psycopg.Error as e:
        tag, detail = "FAILED (blocked)", str(e).splitlines()[0]
    results.append((name, tag, detail))
    print(f"[{tag}] {name}: {detail}")


# shared setup: alice's course goal (as her loop)
gid = run("loop_alice", "INSERT INTO loop_goal (course_id) SELECT id FROM course_context "
          "WHERE course_key='fractions-101' RETURNING id")[0][0]
SECRET = "I have ADHD (inattentive)"

# ---- 1. authority direct reads ----
probe("A1 authority SELECT skill_file",
      lambda: (lambda r: (len(r) > 0, f"{len(r)} rows"))(run("a_school", "SELECT body FROM skill_file")))
probe("A2 authority reads holon_roles mapping",
      lambda: (True, str(run("a_school", "SELECT * FROM holon_roles"))))
probe("A3 authority enumerates seats via pg_roles (catalog is world-readable)",
      lambda: (lambda r: (len(r) > 0, str([x[0] for x in r])))(
          run("a_school", "SELECT rolname FROM pg_roles WHERE pg_has_role(rolname,'participant','MEMBER') AND rolname<>'participant'")))
probe("A4 authority reads pg_stats on skill_file (sampled values)",
      lambda: (lambda r: (len(r) > 0, f"{len(r)} rows"))(run("a_school", "SELECT attname, most_common_vals FROM pg_stats WHERE tablename='skill_file'")))

# ---- 3/4. loop_runner (prompt-injected) exfiltration channels ----
def lr_attempt():
    run("loop_alice", "INSERT INTO loop_attempt (goal_id, iteration, concept_key, strategy, level, modality, "
        "expression_sha256, model_id, visibility, shared_with) VALUES (%s,1,'equal_parts',%s,1,'text','x','m','private',ARRAY['school'])",
        (gid, SECRET))
    r = run("a_school", "SELECT strategy FROM loop_attempt")
    return (any(SECRET in x[0] for x in r), str(r))
probe("L1 loop_runner writes skill text into loop_attempt.strategy, shared_with=[school]", lr_attempt)

def lr_tally():
    run("loop_alice", "INSERT INTO strategy_tally (cause, strategy, visibility) VALUES (%s,'x','commons')", (SECRET,))
    r = run("a_school", "SELECT cause FROM strategy_tally")
    return (any(SECRET in x[0] for x in r), str(r))
probe("L2 loop_runner writes free text into strategy_tally with visibility=commons", lr_tally)

def lr_assess():
    rows = run("loop_alice", "SELECT id FROM loop_attempt LIMIT 1")
    if not rows:  # harness fix: L1 is now blocked, so make a legitimate attempt to attack from
        rows = run("loop_alice", "INSERT INTO loop_attempt (goal_id, iteration, concept_key, strategy, level, modality, "
                   "expression_sha256, model_id) VALUES (%s,1,'equal_parts','baseline',1,'text',%s,'m') RETURNING id",
                   (gid, "0" * 64))
    aid = rows[0][0]
    run("loop_alice", "INSERT INTO assessment (attempt_id, pass, score, evidence, shared_with) VALUES (%s,false,0.1,%s,ARRAY['school'])",
        (aid, psycopg.types.json.Jsonb({"leak": SECRET})))
    r = run("a_school", "SELECT evidence FROM assessment")
    return (any(SECRET in str(x[0]) for x in r), str(r))
probe("L3 loop_runner puts text in assessment.evidence jsonb, shared_with=[school]", lr_assess)

def lr_goalplan():
    run("loop_alice", "INSERT INTO loop_goal (course_id, plan, visibility) SELECT id, %s, 'commons' "
        "FROM course_context WHERE course_key='fractions-101'", (psycopg.types.json.Jsonb({"x": SECRET}),))
    r = run("a_school", "SELECT plan FROM loop_goal")
    return (any(SECRET in str(x[0]) for x in r), str(r)[:120])
probe("L4 loop_runner course goal with plan jsonb text, visibility=commons", lr_goalplan)

def lr_help():
    run("loop_alice", "INSERT INTO help_record (goal_id, concept_key, reason, attempted, visibility, answer) "
        "VALUES (%s,'equal_parts','learner_asked',1,'commons',%s)", (gid, SECRET))
    r = run("a_school", "SELECT answer FROM help_record")
    return (any(x[0] and SECRET in x[0] for x in r), str(r))
probe("L5 loop_runner help_record visibility=commons + answer text at INSERT", lr_help)

def lr_tag():
    run("loop_alice", "INSERT INTO tag_record (giver, receiver, kind, what, source_ref) VALUES ('alice','x','knowledge',%s,'r')", (SECRET,))
    r = run("a_school", "SELECT what FROM tag_record")
    return (any(SECRET in x[0] for x in r), str(r))
probe("L6 loop_runner writes commons tag_record.what (suite 2 deployed)", lr_tag)

def lr_numeric():
    # 31 bits per row through iterations if the field is granted
    val = int.from_bytes(b"ADH", "big")
    run("loop_alice", "INSERT INTO monitoring (goal_id, score, mastery, guidance_code, iterations) "
        "VALUES (%s,0.5,false,'in_progress',%s)", (gid, val))
    r = run("a_school", "SELECT iterations FROM monitoring WHERE projection_of IS NOT NULL ORDER BY id DESC LIMIT 1")
    got = r[0][0].to_bytes(3, "big") if r and r[0][0] else b""
    return (got == b"ADH", f"decoded {got!r}")
probe("L7 covert numeric channel: bytes in monitoring.iterations reach recipient", lr_numeric)

def lr_vocab():
    run("a_school", "INSERT INTO guidance_vocab (code, meaning) VALUES ('flag_adhd','x')")
    run("loop_alice", "INSERT INTO monitoring (goal_id, score, mastery, guidance_code, iterations) "
        "VALUES (%s,0.5,false,'flag_adhd',1)", (gid,))
    r = run("a_school", "SELECT guidance_code FROM monitoring WHERE projection_of IS NOT NULL ORDER BY id DESC LIMIT 1")
    return (r and r[0][0] == "flag_adhd", str(r))
probe("L8 authority-defined guidance code accepted from loop (authority controls vocab)", lr_vocab)

def lr_concept():
    cid = run("a_school", "SELECT id FROM course_context")[0][0]
    run("a_school", "INSERT INTO course_concept (course_id, concept_key, title, shared_with) VALUES (%s,'dx_adhd','t',ARRAY['alice'])", (cid,))
    run("loop_alice", "INSERT INTO monitoring (goal_id, score, mastery, guidance_code, iterations, concept_key) "
        "VALUES (%s,0.5,false,'in_progress',1,'dx_adhd')", (gid,))
    return (True, "authority-added concept key accepted")
probe("L9 authority-planted concept_key accepted (graph is authority-controlled)", lr_concept)

# ---- 2. participant cross-holon ----
probe("P1 p_bob SELECT alice skill_file",
      lambda: (lambda r: (any("ADHD" in x[0] for x in r), f"{len(r)} rows"))(run("p_bob", "SELECT body FROM skill_file")))
probe("P2 p_bob set_config('app.holon','alice') then read",
      lambda: (lambda r: (any("ADHD" in x[0] for x in r), f"{len(r)} rows"))(
          run("p_bob", "SELECT set_config('app.holon','alice',false); SELECT body FROM skill_file")))
probe("P3 p_bob INSERT skill_file with holon='alice'",
      lambda: (run("p_bob", "INSERT INTO skill_file (holon, body) VALUES ('alice','x')") is None, "inserted"))
probe("P4 p_bob SET ROLE p_alice",
      lambda: (run("p_bob", "SET ROLE p_alice") is None, "switched"))
probe("P5 p_bob report_grant on behalf of alice",
      lambda: (run("p_bob", "INSERT INTO report_grant (holon, recipient, fields) VALUES ('alice','x',ARRAY['score'])") is None,
               "stored (check holon)") if False else
      (lambda _: (bool(run("a_school", "SELECT 1 FROM report_grant WHERE holon='alice' AND recipient='zz'")), "trigger rebinds holon"))(
          run("p_bob", "INSERT INTO report_grant (holon, recipient, fields) VALUES ('alice','zz',ARRAY['score'])")))

# ---- 1b. authority via help_seats naming itself ----
def auth_help_self():
    run("a_school", "INSERT INTO course_context (course_key, objective, shared_with, help_seats, visibility) "
        "VALUES ('c2','o',ARRAY['dan'],ARRAY['school'],'private')")
    cid = run("a_school", "SELECT id FROM course_context WHERE course_key='c2'")[0][0]
    run("a_school", "INSERT INTO course_concept (course_id, concept_key, title, shared_with) VALUES (%s,'k1','t',ARRAY['dan'])", (cid,))
    g = run("loop_dan", "INSERT INTO loop_goal (course_id) VALUES (%s) RETURNING id", (cid,))[0][0]
    run("loop_dan", "INSERT INTO help_record (goal_id, addressed_to, concept_key, reason, attempted, causes_tried) "
        "VALUES (%s,'school','k1','learner_asked',37,ARRAY['attention'])", (g,))
    r = run("a_school", "SELECT holon, concept_key, attempted, causes_tried FROM help_record WHERE holon='dan'")
    return (bool(r), f"dan made NO grant; school reads {r}")
probe("A5 authority lists itself in help_seats -> reads ungranted fields via help_record", auth_help_self)

# ---- 6. grant timing: project an OLD source row after a later grant ----
def late_project():
    src = run("loop_dan", "SELECT id FROM monitoring WHERE holon='dan' AND projection_of IS NULL LIMIT 1")
    if not src:
        g = run("loop_dan", "SELECT id FROM loop_goal WHERE holon='dan' LIMIT 1")
        if not g:  # harness fix: A5 is now blocked, so dan's goal is made on the course he is enrolled in
            g = run("loop_dan", "INSERT INTO loop_goal (course_id) SELECT id FROM course_context "
                    "WHERE course_key='fractions-101' RETURNING id")
        g = g[0][0]
        src = run("loop_dan", "INSERT INTO monitoring (goal_id, score, mastery, guidance_code, iterations) "
                  "VALUES (%s,0.2,false,'in_progress',99) RETURNING id", (g,))
    g = run("loop_dan", "SELECT goal_id FROM monitoring WHERE id=%s", (src[0][0],))[0][0]
    before = run("a_school", "SELECT count(*) FROM monitoring WHERE holon='dan'")[0][0]
    run("p_dan", "SELECT set_report_preset('school','progress_only')")
    run("loop_dan", "INSERT INTO monitoring (goal_id, projection_of, recipient) VALUES (%s,%s,'school')", (g, src[0][0]))
    after = run("a_school", "SELECT score FROM monitoring WHERE holon='dan'")
    return (before == 0 and len(after) > 0, f"pre-grant result now visible: {after}")
probe("G1 result written BEFORE grant is projected after grant (retroactive)", late_project)

def report_status_infer():
    r = run("a_school", "SELECT learner, field, status FROM report_status")
    return (len(r) >= 0, f"{len(r)} rows (per-field decline visible by design)")

# ---- 5. revocation via edge: SET ROLE persisting after REVOKE ----
def edge_revoke():
    with _pg.connect_as(DB, "authenticator", autocommit=True) as c:
        c.execute("SET ROLE p_alice")
        uri, _ = _pg.admin_uri_and_psql()
        with psycopg.connect(_pg._with(uri, DB.rsplit('/', 1)[-1]), autocommit=True) as su:
            su.execute("ALTER ROLE p_alice NOLOGIN")
            su.execute("REVOKE p_alice FROM authenticator")
            killed = su.execute("SELECT count(*) FROM pg_stat_activity WHERE usename='p_alice'").fetchone()[0]
        r = c.execute("SELECT current_user, current_holon(), (SELECT count(*) FROM skill_file)").fetchone()
        return (r[1] == "alice", f"backend not matched by usename (count={killed}); still acting as {r}")
probe("R1 edge session that already SET ROLE survives revoke-seat (usename=authenticator)", edge_revoke)

print("\nSUMMARY")
for n, t, d in results:
    print(f"{t:18} {n}")
