# 04 - Caged seats: the valve

The MCP layer (`membrane-mcp.py`) turns the lanes into **capabilities, not access**. A caged seat
is how you hand one of those capability sets to *someone else's box* without opening a hole in yours.

It's a **valve, not a door.**

## The mechanism (unforgeable, top to bottom)
```
OS user  ->  peer-auth DB role (same name, NOT the owner)  ->  holon (holon_roles)  ->  RLS
```
- The seat gets its own **OS user** (locked password, no sudo) and its own **SSH key**.
- That key is a **forced-command** key: `command="<launch the MCP server>",restrict`. It can do
  exactly one thing - speak the tools over stdio - and nothing else. No shell, no sudo, no other
  command, no PTY, no port-forwarding (`restrict` handles the rest).
- The MCP server connects to Postgres by **peer auth as that OS user**, so it runs as a scoped role
  that is **not the database owner**. The owner bypasses RLS; a scoped role does not. That distinction
  is the whole point: a caged seat can only see what RLS lets its holon see (its own rows + the commons).

So the SSH cage caps the **hands** (one capability, no shell); RLS caps the **eyes** (holon scope).

## Why a valve, not a door
- **No hole is opened.** The only listening service is hardened SSH (pubkey-only). You never expose
  the database port or the MCP port. MCP rides *inside* the SSH channel (stdio-over-SSH).
- **It opens only for the one flow.** The forced command means the key can't be climbed through - it
  only passes the scoped capability call.
- **RLS meters what passes**, not just whether it opens.
- **Each side holds its own handle.** You provision (and revoke) the valve on your box; the peer does
  the same on theirs. Revoking the key shuts the valve - unilateral, no shared lock, no negotiation.

## Use it
Prereqs: `membrane-mcp.py` staged and launchable; a role carrying the lane grants (`membrane_app`);
`current_holon()` from `03-hardening.sql` (SECURITY DEFINER, keyed on `session_user`).

```bash
# give a peer 'ark' a seat scoped to holon 'ark':
./add-caged-seat.sh add ark ark "ssh-ed25519 AAAA... ark@theirbox"
./add-caged-seat.sh list
./add-caged-seat.sh revoke ark      # shut the valve
```

The peer points their MCP client at your box over SSH with the matching private key (see
`SYNAPSE-HANDSHAKE.md`). They get the tools for their holon + the commons, and nothing else.
