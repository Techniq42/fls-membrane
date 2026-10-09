#!/usr/bin/env python3
"""
run_all_tests.py - Volume 5 supplement test runner. Apache-2.0.

Runs every SQL and Python test in this supplement against a THROWAWAY, LOCAL
Postgres. Never point it at a live store: it creates LOGIN roles with no
password and drops/creates databases.

Postgres source, in order:
  1. $TEST_PG_URI  (e.g. postgresql://postgres@127.0.0.1:5432/postgres) - a local
     server you started yourself for testing;
  2. otherwise an embedded server from `pip install pixeltable-pgserver`
     (or `pip install pgserver`), started in ./.pgtest and stopped on exit.

Each suite gets its own fresh database. Roles are cluster-wide, so the runner
also uses a fresh embedded data directory per run.
"""
from __future__ import annotations
import os, shutil, subprocess, sys, tempfile
from pathlib import Path
from urllib.parse import urlparse, urlunparse

HERE = Path(__file__).resolve().parent
SQL = HERE / "sql"
CODE = HERE / "code"


def start_server():
    uri = os.environ.get("TEST_PG_URI")
    if uri:
        host = urlparse(uri).hostname
        if host not in ("127.0.0.1", "localhost", "::1"):
            sys.exit("refusing: TEST_PG_URI must be a local throwaway server")
        return uri, None, shutil.which("psql")
    try:
        import pixeltable_pgserver as pgs
    except ImportError:
        import pgserver as pgs  # type: ignore
    data = Path(tempfile.mkdtemp(prefix="pgtest-"))
    srv = pgs.get_server(str(data), cleanup_mode="delete")
    bindir = Path(pgs.__file__).parent / "pginstall" / "bin"
    psql = str(bindir / ("psql.exe" if os.name == "nt" else "psql"))
    return srv.get_uri(), srv, psql


def with_db(uri: str, db: str) -> str:
    u = urlparse(uri)
    return urlunparse(u._replace(path="/" + db))


def psql(psql_bin: str, uri: str, *files: Path, sql: str | None = None) -> str:
    args = [psql_bin, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
    for f in files:
        args += ["-f", str(f)]
    if sql:
        args += ["-c", sql]
    args += ["-d", uri]   # options first: Windows psql ignores options after the URI
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        print(out)
        raise SystemExit(f"FAILED: {' '.join(f.name for f in files) or sql}")
    return out


def fresh_db(psql_bin, admin_uri, name):
    psql(psql_bin, admin_uri, sql=f"DROP DATABASE IF EXISTS {name}")
    psql(psql_bin, admin_uri, sql=f"CREATE DATABASE {name}")
    return with_db(admin_uri, name)


def report(out: str):
    passes = [l for l in out.splitlines() if "PASS:" in l]
    for l in passes:
        print("   ", l.split("NOTICE:")[-1].strip())
    return len(passes)


def run_sql_suite(title, dbname, files):
    """Each SQL suite gets its own embedded server (roles are cluster-wide)."""
    print(f"== {title}")
    uri, srv, psql_bin = start_server()
    try:
        db = fresh_db(psql_bin, uri, dbname)
        return report(psql(psql_bin, db, *files))
    finally:
        if srv is not None:
            srv.cleanup()


def main():
    if os.environ.get("TEST_PG_URI"):
        print("note: TEST_PG_URI set; SQL suites share one cluster, so run them one at a time")
    total = 0
    total += run_sql_suite("suite 1: interlock (sql/00, 10, 15, 20)", "interlock_test",
                           [SQL / "00-identity.sql", SQL / "10-interlock-schema.sql",
                            SQL / "15-interlock-fixtures.sql", SQL / "20-interlock-tests.sql"])
    total += run_sql_suite("suite 2: contribution tiers (sql/00, 10, 15, 30, 35)", "contribution_test",
                           [SQL / "00-identity.sql", SQL / "10-interlock-schema.sql",
                            SQL / "15-interlock-fixtures.sql", SQL / "30-contribution.sql",
                            SQL / "35-contribution-tests.sql"])
    total += run_sql_suite("suite 3: patched 03-hardening (01-schema + 03-hardening.patched)", "hardening_test",
                           [CODE / "01-schema.sql", CODE / "03-hardening.patched.sql",
                            CODE / "tests" / "test-03-hardening.sql"])
    total += run_sql_suite("suite 4: the bug in the PUBLISHED 03-hardening.sql, reproduced", "original_bug_test",
                           [CODE / "01-schema.sql", CODE / "orig" / "03-hardening.sql",
                            CODE / "tests" / "test-03-original-bug.sql"])

    print("== suite 5: python (loop contract, teaching mechanics, modem gate, on-device, MCP identity, revocation)")
    env = {k: v for k, v in os.environ.items() if k not in ("TEST_PG_URI_ADMIN", "TEST_PSQL")}
    r = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(CODE / "tests"),
                        "-p", "test_*.py", "-v"], env=env, cwd=str(CODE), text=True,
                       capture_output=True, encoding="utf-8", errors="replace")
    print(r.stdout[-8000:], r.stderr[-8000:])
    if r.returncode != 0:
        raise SystemExit("FAILED: python tests")

    print("== suite 6: red-team scripts (every probe must be blocked; A3, role names in the catalog, is a documented residual)")
    for script in ("rt_interlock.py", "rt_hardening_anon.py"):
        r = subprocess.run([sys.executable, "-W", "ignore", str(HERE / "redteam" / script)], cwd=str(HERE),
                           text=True, capture_output=True, encoding="utf-8", errors="replace")
        bad = [l for l in r.stdout.splitlines()
               if l.startswith("[SUCCEEDED]") and not l.startswith("[SUCCEEDED] A3 ")]
        print(f"   {script}: {'all blocked' if not bad and r.returncode == 0 else 'PROBLEM'}")
        if bad or r.returncode != 0:
            print(r.stdout[-3000:], r.stderr[-3000:])
            raise SystemExit(f"FAILED: red team {script}")
    print(f"\nALL SUITES PASSED ({total} SQL assertions, plus the python tests listed above)")


if __name__ == "__main__":
    main()
