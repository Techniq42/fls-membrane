"""
membrane-mcp.py - the MCP layer for the membrane kit. Apache-2.0 (see LICENSE+NOTICE).

Exposes the kit's FIVE lanes (coordination, registry, escalations, tickets, handoffs) as MCP TOOLS,
never as database access. The server holds the DB connection (peer auth via unix
socket as the box's OS user), so no DB password ever leaves the box - clients get
capabilities, not credentials. This is the "capability, not access" layer that lets
sovereign forks interoperate without opening their walls.

GENERIC: no fork-specific tables or data model. Pairs with 01-schema.sql.

Requires:  pip install fastmcp "psycopg[binary]"
Run (stdio):  MEMBRANE_DSN="dbname=membrane" python membrane-mcp.py
Wire a client, e.g. Hermes:
    hermes mcp add membrane --command /path/to/venv/bin/python --args /path/to/membrane-mcp.py
Or a VS Code .mcp.json stdio entry that launches it (optionally over SSH).
"""
from __future__ import annotations
import os
import psycopg
from psycopg.rows import dict_row
from fastmcp import FastMCP

DSN = os.environ.get("MEMBRANE_DSN", "dbname=membrane")   # peer auth as the box OS user
ALLOWED_STATUS = {"active", "blocked", "done", "fyi"}
mcp = FastMCP("membrane")


def _q(sql: str, args: tuple = ()) -> list[dict]:
    with psycopg.connect(DSN, row_factory=dict_row) as c, c.cursor() as cur:
        cur.execute(sql, args)
        out = cur.fetchall() if cur.description else []
        c.commit()
    for r in out:
        for k, v in list(r.items()):
            if hasattr(v, "isoformat"):
                r[k] = str(v)
    return out


# ---- coordination lane: seat-to-seat status board ----
@mcp.tool
def bus_read(limit: int = 15, since_id: int = 0) -> list[dict]:
    """Read recent coordination-bus rows (who's doing what), newest first. since_id = only rows past that id."""
    limit = max(1, min(int(limit), 100))
    return _q("SELECT id,agent,focus,status,note,ref,created_at FROM coordination WHERE id > %s ORDER BY id DESC LIMIT %s",
              (int(since_id), limit))

@mcp.tool
def bus_post(agent: str, focus: str, status: str = "active", note: str = "", ref: str = "") -> list[dict]:
    """Append one working-state row to the coordination bus. status: active|blocked|done|fyi."""
    if status not in ALLOWED_STATUS:
        status = "active"
    return _q("INSERT INTO coordination (agent,focus,status,note,ref) VALUES (%s,%s,%s,%s,%s) RETURNING id,created_at",
              (agent, focus, status, note, ref))


# ---- registry lane: legible shared facts (the "add ACME once" fix) ----
@mcp.tool
def registry_read() -> list[dict]:
    """Read the shared registry - the facts everyone sees (orgs, etc.). Poke-and-hope becomes look-at-the-board."""
    return _q("SELECT id,entity,kind,added_by,approved_by,source_url,created_at FROM registry ORDER BY created_at")

@mcp.tool
def register(entity: str, kind: str = "organisation", added_by: str = "", approved_by: str = "", source_url: str = "") -> list[dict]:
    """Add ONE legible fact to the registry (idempotent on entity). approved_by = who authorised it; source_url = provenance."""
    return _q("INSERT INTO registry (entity,kind,added_by,approved_by,source_url) VALUES (%s,%s,%s,%s,%s) "
              "ON CONFLICT (entity) DO NOTHING RETURNING id,entity", (entity, kind, added_by, approved_by, source_url))


# ---- escalations lane: hand a hard question up; the answer returns here ----
@mcp.tool
def escalate(from_agent: str, topic: str, prompt: str) -> list[dict]:
    """Post a hard question to the escalations lane; returns the new id. A bigger tier or a human answers it back."""
    return _q("INSERT INTO escalations (from_agent,topic,prompt) VALUES (%s,%s,%s) RETURNING id", (from_agent, topic, prompt))

@mcp.tool
def pending() -> list[dict]:
    """List open escalations (status=needs_help) awaiting an answer."""
    return _q("SELECT id,from_agent,topic,left(prompt,120) AS prompt,created_at FROM escalations WHERE status='needs_help' ORDER BY id")

@mcp.tool
def answer(id: int, answered_by: str, text: str) -> list[dict]:
    """Write an answer back to an escalation and mark it answered."""
    return _q("UPDATE escalations SET status='answered',answered_by=%s,answer=%s,answered_at=now() WHERE id=%s RETURNING id,status",
              (answered_by, text, int(id)))

@mcp.tool
def read_escalation(id: int) -> list[dict]:
    """Read one escalation and its answer."""
    return _q("SELECT id,from_agent,topic,status,answer,answered_by FROM escalations WHERE id=%s", (int(id),))


# ---- ticket lane: a unit of work. open -> claim -> deliver -> critique -> close ----
_TCOLS = "id,title,status,opened_by,claimed_by,left(body,200) AS body,deliverable,critique,visibility,created_at,updated_at"

@mcp.tool
def ticket_open(title: str, opened_by: str, body: str = "", visibility: str = "commons") -> list[dict]:
    """Open a ticket (a unit of work) on the board; returns the new id. visibility: commons|private (RLS-scoped)."""
    return _q("INSERT INTO tickets (title,body,opened_by,visibility) VALUES (%s,%s,%s,%s) RETURNING id,status,created_at",
              (title, body, opened_by, visibility))

@mcp.tool
def ticket_list(status: str = "", limit: int = 25) -> list[dict]:
    """List tickets visible to this seat (RLS-scoped), newest first. Optional status filter (open|claimed|delivered|critiqued|closed)."""
    limit = max(1, min(int(limit), 100))
    if status:
        return _q(f"SELECT {_TCOLS} FROM tickets WHERE status=%s ORDER BY id DESC LIMIT %s", (status, limit))
    return _q(f"SELECT {_TCOLS} FROM tickets ORDER BY id DESC LIMIT %s", (limit,))

@mcp.tool
def ticket_read(id: int) -> list[dict]:
    """Read one ticket in full (if visible to this seat)."""
    return _q("SELECT id,title,body,status,opened_by,claimed_by,deliverable,critique,created_at,updated_at FROM tickets WHERE id=%s", (int(id),))

@mcp.tool
def ticket_claim(id: int, claimed_by: str) -> list[dict]:
    """Claim an open ticket (open -> claimed). Legal only from status 'open'; empty result = not open / not visible."""
    return _q("UPDATE tickets SET status='claimed',claimed_by=%s,updated_at=now() WHERE id=%s AND status='open' RETURNING id,status,claimed_by",
              (claimed_by, int(id)))

@mcp.tool
def ticket_deliver(id: int, deliverable: str) -> list[dict]:
    """Attach a deliverable and mark delivered (claimed -> delivered)."""
    return _q("UPDATE tickets SET status='delivered',deliverable=%s,updated_at=now() WHERE id=%s AND status='claimed' RETURNING id,status",
              (deliverable, int(id)))

@mcp.tool
def ticket_critique(id: int, critique: str, close: bool = False) -> list[dict]:
    """Record a critique on a delivered ticket (delivered -> critiqued; -> closed if close=True)."""
    return _q("UPDATE tickets SET status=%s,critique=%s,updated_at=now() WHERE id=%s AND status='delivered' RETURNING id,status",
              ("closed" if close else "critiqued", critique, int(id)))


# ---- handoff lane: the baton. Do your leg, pass the next to a NAMED seat ----
@mcp.tool
def handoff_send(task: str, from_seat: str, to_seat: str, summary: str = "", need: str = "", refs: str = "") -> list[dict]:
    """Pass the next leg of a task to another seat; lands in their inbox as 'pending'. Addressed by SEAT, not session id, so it survives churn."""
    return _q("INSERT INTO handoffs (task,from_seat,to_seat,summary,need,refs) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id,task,to_seat,status,created_at",
              (task, from_seat, to_seat, summary, need, refs))

@mcp.tool
def handoff_inbox(seat: str) -> list[dict]:
    """Your baton inbox: handoffs addressed to <seat> still waiting (pending or accepted). Check at wake and whenever free."""
    return _q("SELECT id,task,from_seat,summary,need,refs,status,created_at FROM handoffs WHERE to_seat=%s AND status = ANY(%s) ORDER BY id",
              (seat, ["pending", "accepted"]))

@mcp.tool
def handoff_accept(id: int, seat: str) -> list[dict]:
    """Take the baton (pending -> accepted) so others see it's being worked. Only the addressed seat."""
    return _q("UPDATE handoffs SET status='accepted',updated_at=now() WHERE id=%s AND to_seat=%s AND status='pending' RETURNING id,task,status",
              (int(id), seat))

@mcp.tool
def handoff_done(id: int) -> list[dict]:
    """Finish your leg of the baton (-> done). To report a result or route onward, use handoff_send / handoff_pass."""
    return _q("UPDATE handoffs SET status='done',updated_at=now() WHERE id=%s AND status IN ('pending','accepted') RETURNING id,task,status", (int(id),))

@mcp.tool
def handoff_pass(id: int, from_seat: str, to_seat: str, summary: str = "", need: str = "", refs: str = "") -> list[dict]:
    """Chain the baton onward: close your leg (-> passed) and open a new handoff to the next seat, carrying the task label. Returns the NEW id."""
    orig = _q("SELECT task FROM handoffs WHERE id=%s", (int(id),))
    task = orig[0].get("task", "task") if orig else "task"
    _q("UPDATE handoffs SET status='passed',updated_at=now() WHERE id=%s AND status IN ('pending','accepted')", (int(id),))
    return _q("INSERT INTO handoffs (task,from_seat,to_seat,summary,need,refs) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id,task,to_seat,status",
              (task, from_seat, to_seat, summary, need, refs))


if __name__ == "__main__":
    mcp.run()
