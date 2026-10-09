# Volume 5 reference code and tests

Companion code for *Solid Ground: the complete record*, Volume 5 (Technical Supplement). Code Apache 2.0; text CC BY 4.0.

This folder holds the worked, tested examples that Volume 5 describes. It is a reference, not a product: read it, run it, fork it.

| Path | What it is |
|---|---|
| `sql/00-identity.sql` | Sealed seat-to-holon mapping, `current_holon()` that also works behind a `SET ROLE` web edge, `current_seat()`, a non-login table owner. |
| `sql/10-interlock-schema.sql` | The interlock: the user-held skill file, an optional course context with its concept graph, the learning loop's records, monitoring with learner-granted per-recipient copies, help records, and dashboard views. One read rule on every table, with row-level security forced. |
| `sql/15-...`, `sql/20-...` | Fixtures and tests for the above, including an injected instruction and a learner with no institution. |
| `sql/30-contribution.sql`, `sql/35-...` | Two-tier contribution: light tag records by default, opt-in attribution. No payment machinery. |
| `code/interlock_loop.py` | The learning loop and teaching mechanics: diagnosis, backtracking, approach rotation, help offers. |
| `code/modem_gate.py` | The comprehension gate, level scale and re-derivable extraction. |
| `code/on_device.py` | On-device variant: local store, local loop, only granted monitoring syncs. |
| `code/*.patched.*`, `code/revoke-seat.sql`, `code/diffs/` | The hardened variant of the v1.0 reference code (Volume 5 Part F), with diffs against v1.0. |
| `code/orig/` | Verbatim v1.0 files, used only to reproduce the issues the hardened variant fixes. |
| `code/edge/` | Example web-edge configuration (short-lived tokens, a deny list for revoked seats). Examples only. |
| `redteam/` | Adversarial probes run against the reference. Every attack that once succeeded is now a regression test. |

## Run the tests

```
pip install pixeltable-pgserver "psycopg[binary]"
python run_all_tests.py
```

The harness starts a throwaway Postgres bound to 127.0.0.1, runs every suite including the red-team probes, and deletes it afterward. Nothing remote is contacted.

## Known limits

- A database superuser bypasses row-level security. Never run the store as a superuser on behalf of an institution; Volume 5 section A.7 gives the on-device alternative.
- Role names are visible to other roles in Postgres. Deployments should use opaque, non-personal role names.
- A small covert channel remains in the coarsened numeric fields; Volume 5 section A.7 states its size.
- The full seat script needs Linux, sudo and SSH; its SQL half is tested here, the rest is syntax-checked only. A live PostgREST and Caddy were not exercised; their behavior is reproduced in SQL.
