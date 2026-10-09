"""Shared helper for the Python tests: a fresh database on a LOCAL throwaway
Postgres, loaded with the interlock SQL, and connections AS a given seat.
Apache-2.0."""
from __future__ import annotations
import os, subprocess, sys, uuid
from pathlib import Path
from urllib.parse import urlparse, urlunparse

import psycopg

ROOT = Path(__file__).resolve().parents[2]          # supplement-v1.1/
SQL = ROOT / "sql"
CODE = ROOT / "code"
sys.path.insert(0, str(CODE))

_server = None


def admin_uri_and_psql():
    global _server
    uri, ps = os.environ.get("TEST_PG_URI_ADMIN"), os.environ.get("TEST_PSQL")
    if uri and ps:
        return uri, ps
    import pixeltable_pgserver as pgs
    import tempfile
    if _server is None:
        _server = pgs.get_server(tempfile.mkdtemp(prefix="pgtest-"), cleanup_mode="delete")
    ps = str(Path(pgs.__file__).parent / "pginstall" / "bin" / ("psql.exe" if os.name == "nt" else "psql"))
    os.environ["TEST_PG_URI_ADMIN"], os.environ["TEST_PSQL"] = _server.get_uri(), ps
    return _server.get_uri(), ps


def _with(uri: str, db: str | None = None, user: str | None = None) -> str:
    u = urlparse(uri)
    netloc = u.netloc
    if user:
        netloc = user + "@" + netloc.split("@", 1)[-1]
    return urlunparse(u._replace(netloc=netloc, path="/" + (db or u.path.lstrip("/"))))


def fresh_db(files: list[Path], roles_cleanup: list[str] = ()) -> str:
    """Create a uniquely named database and load the given SQL files."""
    uri, ps = admin_uri_and_psql()
    name = "t_" + uuid.uuid4().hex[:10]
    with psycopg.connect(uri, autocommit=True) as c:
        c.execute(f"CREATE DATABASE {name}")
    db = _with(uri, name)
    args = [ps, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
    for f in files:
        args += ["-f", str(f)]
    args += ["-d", db]
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise RuntimeError(r.stdout + r.stderr)
    return db


def drop_cluster_roles(names: list[str]):
    """Roles are cluster-wide; tests that create them clean up first."""
    uri, _ = admin_uri_and_psql()
    with psycopg.connect(uri, autocommit=True) as c:
        for n in names:
            dbs = [r[0] for r in c.execute("SELECT datname FROM pg_database WHERE datname LIKE 't_%'")]
            for d in dbs:
                try:
                    with psycopg.connect(_with(uri, d), autocommit=True) as c2:
                        c2.execute(f'DROP OWNED BY "{n}" CASCADE')
                except Exception:
                    pass
            c.execute(f'DROP ROLE IF EXISTS "{n}"')


def connect_as(db_uri: str, user: str, **kw):
    return psycopg.connect(_with(db_uri, user=user), **kw)


_shared = {}


def shared_interlock_db() -> str:
    """One interlock database per test process (fixture roles are cluster-wide)."""
    if "db" not in _shared:
        _shared["db"] = fresh_db(INTERLOCK)
    return _shared["db"]


INTERLOCK = [SQL / "00-identity.sql", SQL / "10-interlock-schema.sql", SQL / "15-interlock-fixtures.sql"]
INTERLOCK_ROLES = ["p_alice", "p_bob", "loop_alice", "a_school", "tutor_kim", "tutor_lee",
                   "web_anon", "authenticator", "participant", "authority", "loop_runner",
                   "human_seat", "membrane_app", "store_owner"]
