#!/usr/bin/env bash
# add-caged-seat.sh - provision a CAGED, SCOPED seat: how one sovereign lets another in
# without opening a hole. Apache-2.0 (see LICENSE + NOTICE).
#
# A caged seat is a valve, not a door. Identity runs unforgeable all the way down:
#     OS user  ->  peer-auth DB role (same name, NOT the owner)  ->  holon (holon_roles)
# The seat's SSH key is a FORCED-COMMAND key whose only command is the membrane MCP server.
# So the key can do exactly one thing - speak the capability tools over stdio - and nothing
# else: no shell, no sudo, no other command, no port-forwarding (restrict). Postgres RLS then
# scopes every read/write to that seat's holon + the commons. The hands are capped by the SSH
# cage; the eyes are capped by RLS. Each edge is its own scope; revoking the key shuts the valve.
#
# Run as an admin OS user with sudo. Requires: the membrane MCP server staged at $MCP_CMD,
# a Postgres role that grants the lane capabilities (here: membrane_app), and current_holon()
# from 03-hardening.sql (SECURITY DEFINER, keyed on session_user).
#
# Usage:
#   ./add-caged-seat.sh add    <seat> <holon> "<ssh-ed25519 AAAA... [comment]>"
#   ./add-caged-seat.sh list
#   ./add-caged-seat.sh revoke <seat>          # shut this valve; role/holon left intact
set -euo pipefail

# The one command a caged key may run = launch the MCP server. Override for your layout.
MCP_CMD="${MEMBRANE_MCP_CMD:-/opt/membrane-mcp/venv/bin/python /opt/membrane-mcp/membrane-mcp.py}"
DB="${MEMBRANE_DB:-membrane}"
GRANT_ROLE="${MEMBRANE_APP_ROLE:-membrane_app}"   # role carrying the lane grants; seat inherits it
SAFE='^[a-z][a-z0-9_-]{1,30}$'

psql_su() { sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 "$@"; }

case "${1:-}" in
  add)
    seat="${2:?need a seat name, e.g. ark}"; holon="${3:?need a holon, e.g. ark}"
    keyin="${4:?need the seat public key, e.g. \"ssh-ed25519 AAAA...\"}"
    [[ "$seat"  =~ $SAFE ]] || { echo "ERROR: seat must match $SAFE" >&2; exit 2; }
    [[ "$holon" =~ $SAFE ]] || { echo "ERROR: holon must match $SAFE" >&2; exit 2; }
    ktype="$(awk '{print $1}' <<<"$keyin")"; kdata="$(awk '{print $2}' <<<"$keyin")"
    [[ "$ktype" == ssh-* && -n "$kdata" ]] || { echo "ERROR: not an SSH public key" >&2; exit 2; }

    echo "[1/3] OS user '$seat' (locked password, no sudo)"
    id "$seat" >/dev/null 2>&1 || sudo useradd -m -s /bin/bash "$seat"
    sudo passwd -l "$seat" >/dev/null 2>&1 || true
    sudo mkdir -p "/home/$seat/.ssh" && sudo chmod 700 "/home/$seat/.ssh"

    echo "[2/3] DB role '$seat' -> holon '$holon' (inherits $GRANT_ROLE, NOT owner)"
    psql_su -tAc "SELECT 1 FROM pg_roles WHERE rolname='$seat'" | grep -q 1 \
      || psql_su -c "CREATE ROLE \"$seat\" LOGIN INHERIT;"
    psql_su -c "GRANT \"$GRANT_ROLE\" TO \"$seat\";"
    psql_su -c "INSERT INTO holon_roles(rolename,holon) VALUES('$seat','$holon') ON CONFLICT(rolename) DO UPDATE SET holon=EXCLUDED.holon;"

    echo "[3/3] caged key -> ~$seat/.ssh/authorized_keys (MCP-tools-only)"
    printf 'command="%s",restrict %s %s caged:%s\n' "$MCP_CMD" "$ktype" "$kdata" "$seat" \
      | sudo tee "/home/$seat/.ssh/authorized_keys" >/dev/null
    sudo chown -R "$seat:$seat" "/home/$seat/.ssh"; sudo chmod 600 "/home/$seat/.ssh/authorized_keys"
    echo "done. '$seat' reaches the membrane tools (holon '$holon') and nothing else."
    ;;
  list)
    echo "=== caged seats (valves) ==="
    for ak in /home/*/.ssh/authorized_keys; do
      [[ -f "$ak" ]] || continue
      if sudo grep -q "command=.*,restrict.*caged:" "$ak" 2>/dev/null; then
        seat="$(basename "$(dirname "$(dirname "$ak")")")"
        holon="$(psql_su -tAc "SELECT holon FROM holon_roles WHERE rolename='$seat'" 2>/dev/null | tr -d '[:space:]')"
        echo "  $seat  (holon: ${holon:-?})"
      fi
    done
    ;;
  revoke)
    seat="${2:?need the seat to revoke}"
    [[ "$seat" =~ $SAFE ]] || { echo "ERROR: bad seat name" >&2; exit 2; }
    [[ -f "/home/$seat/.ssh/authorized_keys" ]] || { echo "no such seat key" >&2; exit 5; }
    sudo truncate -s 0 "/home/$seat/.ssh/authorized_keys"
    echo "valve shut for '$seat' (now keyless). Role/holon left intact; drop them manually to fully retire."
    ;;
  *)
    grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
