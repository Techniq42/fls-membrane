#!/usr/bin/env bash
# ============================================================================
# Sovereign Membrane — one file, agent-agnostic capability layer + setup. Apache-2.0 (see LICENSE+NOTICE).
# Fork this onto YOUR OWN VPS. Your data stays behind YOUR wall.
# Interoperate with other forks later via the MCP layer (capability, not access).
#
# Usage:  membrane.sh <db> <command> [args...]
#   setup                                   create the db + load the schema
#   register <entity> <kind> <by> <appr> <src>   add one legible row (the ACME fix)
#   board                                    read the registry (what everyone sees)
#   escalate <from> <topic> <prompt>         hand a hard question up; prints the id
#   pending                                  list open escalations (for a frontier)
#   answer <id> <by> <text>                  frontier writes the answer back
#   read <id>                                read an escalation + its answer
# ============================================================================
set -euo pipefail
DB="${1:?usage: membrane.sh <db> <command> [args]}"; CMD="${2:?see header for commands}"; shift 2 || true
here="$(cd "$(dirname "$0")" && pwd)"

case "$CMD" in
  setup)
    command -v psql >/dev/null || { echo "install postgres first: sudo apt install -y postgresql"; exit 1; }
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 \
      || sudo -u postgres createdb -O "$(whoami)" "$DB"
    psql -d "$DB" -q -f "$here/01-schema.sql"
    echo "sovereign membrane '$DB' is up. wire your agent's skills to these commands." ;;
  register)
    psql -d "$DB" -q -c "insert into registry(entity,kind,added_by,approved_by,source_url) \
      values (\$\$${1}\$\$,\$\$${2}\$\$,\$\$${3}\$\$,\$\$${4}\$\$,\$\$${5}\$\$) on conflict(entity) do nothing;"
    echo "registered: $1" ;;
  board)
    psql -d "$DB" -c "select entity,kind,added_by,approved_by,created_at from registry order by created_at;" ;;
  escalate)
    psql -d "$DB" -qtA -c "insert into escalations(from_agent,topic,prompt) \
      values (\$\$${1}\$\$,\$\$${2}\$\$,\$\$${3}\$\$) returning id;" ;;
  pending)
    psql -d "$DB" -c "select id,from_agent,topic,left(prompt,60) as prompt from escalations where status='needs_help' order by id;" ;;
  answer)
    psql -d "$DB" -q -c "update escalations set status='answered',answered_by=\$\$${2}\$\$,answer=\$\$${3}\$\$,answered_at=now() where id=${1};"
    echo "answered #$1" ;;
  read)
    psql -d "$DB" -x -c "select from_agent,status,answered_by,answer from escalations where id=${1};" ;;
  *) echo "commands: setup register board escalate pending answer read"; exit 1 ;;
esac
