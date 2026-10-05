#!/usr/bin/env bash
# ============================================================================
# test-identity.sh - can one seat write as another? Apache-2.0 (see LICENSE+NOTICE).
# Stands up a THROWAWAY Postgres cluster (no sudo, nothing touches your real db),
# loads 01-schema.sql + 03-hardening.sql, provisions two seats (alice, bob), then
# has bob try to act in alice's name through the same SQL the MCP tools run.
#
# RLS already caps the EYES (bob can't see alice's private rows). This checks the
# HANDS: every name a row records (opened_by, claimed_by, agent, from_agent,
# answered_by, added_by) must be the seat that actually wrote it, and credit must
# not be self-declarable. Then it checks the honest round trips still work.
#
# Usage:  bash test-identity.sh            (exit 0 = all pass)
# Needs:  postgres server binaries (apt install postgresql); finds them itself.
# ============================================================================
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

BIN="$(pg_config --bindir 2>/dev/null || true)"
[[ -x "$BIN/initdb" ]] || BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"
[[ -x "$BIN/initdb" ]] || { echo "need postgres server binaries (initdb)"; exit 1; }

TMP="$(mktemp -d /tmp/membrane-test.XXXXXX)"
PORT=$(( 20000 + RANDOM % 20000 ))
cleanup() { "$BIN/pg_ctl" -D "$TMP/db" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

"$BIN/initdb" -D "$TMP/db" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$TMP/db" -o "-k $TMP -c listen_addresses='' -p $PORT" -l "$TMP/log" -w start >/dev/null

as()  { psql -h "$TMP" -p "$PORT" -d m -U "$1" -tA -v ON_ERROR_STOP=1 -q -c "$2" 2>&1; }
val() { as postgres "$1"; }
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1  -> $2"; fail=$((fail+1)); }
# expect_stored <label> <seat> <sql> <check-query> <expected>: the write may be refused
# or may succeed - either way, what's stored must be the expected (true) value.
expect_stored() { as "$2" "$3" >/dev/null || true; local got; got="$(val "$4")"
                  [[ "$got" == "$5" ]] && ok "$1" || bad "$1" "stored '$got', want '$5'"; }
expect_denied() { if out="$(as "$2" "$3")"; then bad "$1" "allowed: ${out//$'\n'/ }"; else ok "$1"; fi; }
expect_works()  { if out="$(as "$2" "$3")"; then ok "$1"; else bad "$1" "${out//$'\n'/ }"; fi; }

psql -h "$TMP" -p "$PORT" -U postgres -q -c "CREATE DATABASE m"
for f in 01-schema.sql 03-hardening.sql; do
  psql -h "$TMP" -p "$PORT" -U postgres -d m -q -v ON_ERROR_STOP=1 -f "$here/$f" >/dev/null 2>&1 \
    || { echo "loading $f failed"; exit 1; }
done
val "CREATE ROLE alice LOGIN INHERIT; CREATE ROLE bob LOGIN INHERIT;
     GRANT membrane_app TO alice, bob;
     INSERT INTO holon_roles VALUES ('alice','alice'),('bob','bob');" >/dev/null

# alice's honest rows to aim at
as alice "INSERT INTO escalations(from_agent,topic,prompt,visibility,holon) VALUES('alice','t','private q','private','alice')" >/dev/null
as alice "INSERT INTO tickets(title,opened_by) VALUES('t1','alice')" >/dev/null                       # id 1: open
as alice "INSERT INTO tickets(title,opened_by) VALUES('t2','alice');
          UPDATE tickets SET status='claimed',claimed_by='alice' WHERE id=2" >/dev/null               # id 2: alice claimed
as alice "INSERT INTO tickets(title,opened_by) VALUES('t3','alice');
          UPDATE tickets SET status='claimed',claimed_by='alice' WHERE id=3;
          UPDATE tickets SET status='delivered',deliverable='alice work' WHERE id=3" >/dev/null       # id 3: alice delivered
as alice "INSERT INTO escalations(from_agent,topic,prompt) VALUES('alice','t','q2')" >/dev/null       # id 2: open escalation

echo "eyes (already held before this change):"
got="$(as bob "SELECT count(*) FROM escalations WHERE holon='alice'")"
[[ "$got" == 0 ]] && ok "bob cannot read alice's private escalation" || bad "bob reads alice's private row" "$got"
expect_denied "bob cannot forge a handoff FROM alice" bob \
  "INSERT INTO handoffs(task,from_seat,to_seat) VALUES('x','alice','bob')"

echo "hands (bob tries to write in alice's name):"
expect_stored "ticket_open as alice is recorded as bob" bob \
  "INSERT INTO tickets(title,opened_by) VALUES('forged','alice')" \
  "SELECT opened_by FROM tickets WHERE title='forged'" bob
expect_stored "ticket_claim as alice is recorded as bob" bob \
  "UPDATE tickets SET status='claimed',claimed_by='alice' WHERE id=1 AND status='open'" \
  "SELECT claimed_by FROM tickets WHERE id=1" bob
expect_stored "bob cannot deliver on alice's claimed ticket" bob \
  "UPDATE tickets SET status='delivered',deliverable='bob work' WHERE id=2 AND status='claimed'" \
  "SELECT status||'/'||coalesce(deliverable,'-') FROM tickets WHERE id=2" "claimed/-"
expect_stored "bob cannot rewrite alice's delivered work" bob \
  "UPDATE tickets SET deliverable='rewritten', claimed_by='bob' WHERE id=3" \
  "SELECT claimed_by||'/'||deliverable FROM tickets WHERE id=3" "alice/alice work"
as bob "INSERT INTO tickets(title,opened_by) VALUES('skip','bob')" >/dev/null
expect_stored "bob cannot skip ticket states (open -> closed)" bob \
  "UPDATE tickets SET status='closed' WHERE title='skip'" \
  "SELECT status FROM tickets WHERE title='skip'" open
expect_stored "bus_post as alice is recorded as bob" bob \
  "INSERT INTO coordination(agent,focus) VALUES('alice','forged')" \
  "SELECT agent FROM coordination WHERE focus='forged'" bob
expect_stored "escalate as alice is recorded as bob" bob \
  "INSERT INTO escalations(from_agent,topic,prompt) VALUES('alice','t','forged q')" \
  "SELECT from_agent FROM escalations WHERE prompt='forged q'" bob
expect_stored "answer as alice is recorded as bob" bob \
  "UPDATE escalations SET status='answered',answered_by='alice',answer='a' WHERE id=2" \
  "SELECT answered_by FROM escalations WHERE id=2" bob
expect_stored "register as alice is recorded as bob" bob \
  "INSERT INTO registry(entity,added_by) VALUES('FORGED','alice')" \
  "SELECT added_by FROM registry WHERE entity='FORGED'" bob
expect_denied "bob cannot award himself credit" bob \
  "INSERT INTO tags(holon,tag,ref) VALUES('bob','delivered','ticket:3')"
expect_denied "bob cannot write credit in alice's name" bob \
  "INSERT INTO tags(holon,tag,ref) VALUES('alice','checked','x')"

echo "honest round trips still work:"
expect_works "alice opens a ticket" alice "INSERT INTO tickets(title,opened_by) VALUES('rt','alice')"
expect_works "bob claims it"        bob   "UPDATE tickets SET status='claimed',claimed_by='bob' WHERE title='rt'"
expect_works "bob delivers it"      bob   "UPDATE tickets SET status='delivered',deliverable='done' WHERE title='rt'"
expect_works "alice critiques it"   alice "UPDATE tickets SET status='critiqued',critique='nice' WHERE title='rt'"
got="$(val "SELECT opened_by||'/'||claimed_by||'/'||status FROM tickets WHERE title='rt'")"
[[ "$got" == "alice/bob/critiqued" ]] && ok "round trip recorded alice/bob/critiqued" || bad "round trip" "$got"
expect_works "a seat may label its own sub-agents (bob:researcher)" bob \
  "INSERT INTO coordination(agent,focus) VALUES('bob:researcher','sub')"
got="$(val "SELECT agent FROM coordination WHERE focus='sub'")"
[[ "$got" == "bob:researcher" ]] && ok "sub-agent label kept" || bad "sub-agent label" "$got"
expect_works "handoff alice -> bob"  alice "INSERT INTO handoffs(task,from_seat,to_seat) VALUES('h','alice','bob')"
expect_works "bob accepts + finishes" bob  "UPDATE handoffs SET status='accepted' WHERE task='h'; UPDATE handoffs SET status='done' WHERE task='h'"
expect_works "admin (no holon) still writes freely" postgres \
  "INSERT INTO coordination(agent,focus) VALUES('coordinator','admin row')"

echo; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
