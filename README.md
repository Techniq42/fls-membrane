# Membrane Kit - the commons your oracle should stand on

An agent with a file corpus + memory + skills is a good **oracle**: you ask, it
answers from its *private* store. What it's missing is **shared, queryable,
multi-writer state** - the thing that turns an oracle into a **workspace**.

This kit is that missing layer: a few Postgres lanes + the pattern to wire any
agent to them. It's the blackboard architecture (Hearsay-II,
1970s) done cleanly for LLM agent seats.

## Fork quickstart (stand up your OWN on your OWN VPS)
Your data stays behind your wall. One file does setup + the whole capability layer.
```bash
# on your VPS (needs postgresql):
git clone <this> && cd fls-membrane
bash membrane.sh mydb setup                                  # fresh membrane, from nothing
bash membrane.sh mydb register "ACME" org me approver https://acme.org   # one legible row
bash membrane.sh mydb board                                  # everyone reads the same row
ID=$(bash membrane.sh mydb escalate me topic "a hard question")   # hand it up
bash membrane.sh mydb answer $ID a-frontier "the answer"     # frontier writes back
bash membrane.sh mydb read $ID                               # round-trip closed

# see the whole frozen-small -> frontier handoff end to end:
bash escalate-demo.sh mydemo

# (optional) the pure router: recognize + route pending escalations by tier:
MEMBRANE_DB_URL=postgresql://$(whoami)@localhost/mydb python3 router.py
```
Each participant runs their own. To interoperate *between* forks without opening your
wall, add the **MCP layer** (capability, not access) - that's the reason it exists:
N sovereign boxes that need to talk, none of them trusting a central one.

## What's here
| File | License | What it is |
|---|---|---|
| `WHY.md` | CC BY 4.0 | **Start here** - what it does and why it exists |
| `01-schema.sql` | Apache-2.0 | The five lanes (coordination, registry, escalations, tickets, handoffs) + the credit-ledger `tags` table + the RLS "eyes" |
| `02-demos.sql` | Apache-2.0 | Demo A: the four-times-ACME fix. Demo B: escalate-to-frontier |
| `03-hardening.sql` | Apache-2.0 | Optional multi-party hardening: RLS on every lane, unforgeable per-holon identity, writes narrowed to legal moves |
| `membrane.sh` | Apache-2.0 | One-file stand-up + the whole capability layer (setup/register/board/escalate/pending/answer/read) |
| `router.py` | Apache-2.0 | The pure router: recognizes + routes by tier, never reasons, model-agnostic |
| `membrane-mcp.py` | Apache-2.0 | **The MCP layer** - serves the lanes as capability TOOLS (bus/registry/escalations/tickets/handoffs); capability-not-access, peer-auth, stdio |
| `escalate-demo.sh` | Apache-2.0 | The money demo: frozen-small → frontier handoff, end to end |
| `add-caged-seat.sh` | Apache-2.0 | **The valve** - provision a caged, scoped seat so another sovereign can reach your tools without opening a hole (forced-command SSH → peer role → holon → RLS) |
| `04-caged-seats.md` | CC BY 4.0 | How the valve works, and why it's capability-not-access at the SSH layer |
| `SYNAPSE-HANDSHAKE.md` | CC BY 4.0 | How two boxes **hinge** (bidirectional caged seats) into a mesh - no hub; commons vs. capacity |
| `05-coordination-game.md` | CC BY 4.0 | accept → deliver → **opt-in** check → credit: honest coordination with no boss (tickets + a tag ledger) |
| `SOUL.md` | CC BY 4.0 | Pointer to a narrative agent constitution (livingsys.org) |

## The two "doorbells" (this is the handshake)
- **MCP call** = an agent *synchronously calls a capability* (a tool). Use this
  when the agent needs an answer *now*. The server that serves these tools is
  `membrane-mcp.py` - wire it into any MCP client (`pip install fastmcp "psycopg[binary]"`,
  then e.g. `hermes mcp add membrane --command <venv>/bin/python --args membrane-mcp.py`,
  or a VS Code `.mcp.json` stdio entry, optionally launched over SSH). The server holds
  the DB connection; the client gets tools, never credentials.
- **DB note-passing** = *asynchronous handoff* through the lanes. Post a row; another
  seat (or a bigger model, or a human) reads and answers it. Use this for work that
  hands off across seats/time.
- *(Telegram is neither - it's just the human buzzer: "come look.")*

## The move that fixes "add ACME" (four times)
State lived in the bot's private memory, so a teammate couldn't *see* it and re-poked.
Put the fact in `registry` **once** → the bot, a worker, and a human all read the
same row. Poke-and-hope → look-at-the-board. (`02-demos.sql`, Demo A.)

## The move that makes answers stop sucking
The commons alone doesn't make a frozen model smarter - but it's the conduit for
the two things that do:
1. **Better inputs** - retrieve from a *real* corpus, not just the orgs' own
   about-pages (that's the echo chamber). Cite sources; store verified facts as rows.
2. **Escalation to a bigger tier** - hand hard questions to a frontier model via
   the `escalations` lane; the answer returns into the row. (`02-demos.sql`, Demo B;
   run `escalate-demo.sh` to watch it.)

## Escalate-to-frontier: honest wiring
- **Today (in-loop):** a frontier seat (a bigger model, or a human, or an automated watcher) watches the `escalations` lane, claims a `needs_help` row, writes the
  `answer` back, flips status to `answered`. The small agent then reads the answer.
  Works right now; needs a seat to be watching. `router.py` can pre-sort what's
  pending by tier so the right watcher grabs the right rows.
- **Push-button (next layer):** wrap it as an **MCP tool** the agent calls
  (`escalate(prompt) -> answer`) backed by a tiny poller that invokes the frontier
  when a row appears. That removes the "someone has to be watching" step.
  *(Don't claim autonomy you haven't wired - the lane works async regardless.)*

## MCP tool surface (sketch - capability, not raw DB access)
Expose the commons as one tool with actions, so agents call *capabilities* and
never touch credentials or see rows they shouldn't (RLS enforces the eyes):
```
commons.post_note(agent, focus, status, note)
commons.read_board()                 -> recent coordination rows
commons.register_entity(entity, kind, approved_by, source_url)
commons.escalate(from_agent, topic, prompt)   -> escalation_id
commons.read_answer(escalation_id)            -> answer | null
commons.ticket_open(title, opened_by)         -> ticket_id   (a unit of work)
commons.handoff_send(task, from_seat, to_seat) -> handoff_id  (the seat-addressed baton)
```

## RLS = the eyes (why this is sovereign, not just a shared table)
Each seat connects as a scoped role and `SET app.holon = '<its id>'`. It then sees
`commons` rows + only its own holon's rows. Sovereignty isn't in the agent's SOUL;
it's here, in what each call is allowed to see. Two systems can share a commons and
still each keep private lanes - **membrane, not membership.** The same pattern scopes
a household as easily as an org: a kid's seat sees kid-safe commons + its own lane;
the escalation path to a frontier model is gated and adult-approved. One mechanism,
many shapes.

## Trust model & hardening
Out of the box this kit runs a **demo trust model**: RLS guards the escalations lane, seats declare their own holon, and one shared role writes everywhere - fine for a single trusted box. For a **multi-party deployment**, apply `03-hardening.sql`: it scopes every lane, makes holon identity something a seat connects *as* rather than *claims* (per-holon roles, or a capability layer that sets it server-side), and narrows writes to legal moves only. Stating your own attack surface is itself a feature - so pick the model your deployment needs, and say which one you're running.

## From the Fellowship of Living Systems
This kit is published by the **Fellowship of Living Systems (FLS)** - a
public-benefit effort building open coordination infrastructure so communities can
run their own sovereign AI without renting it from anyone. The pattern here is the
foundational, forkable *ground*; we give it away on purpose. More at
**[livingsys.org](https://livingsys.org)**.

## Provenance
The invention in this kit is mine - conceived, lived, and directed over years of
running real operations where the constraints did the teaching. I built it with a
language model the way a lathe is a tool: it shaped the work, it did not author it.
The conception, and the responsibility for it, are mine.

It is put here on purpose. This is the foundational ground, given away so the next
operator does not have to walk years to find the path. Take it, build on it, carry
the attribution, and pass the ground forward.

Dual-licensed by file type: code (`.sql`, `.sh`, `.py`) under **Apache-2.0** (see
`LICENSE`, `NOTICE`); prose (`README.md`, `WHY.md`, `SOUL.md`) under **CC BY 4.0**.
The SOUL is canonical at [livingsys.org](https://livingsys.org/resources/agent-constitution) -
link it, don't fork it. Share the how, hold the what.

- Shannon Dobbs, Fellowship of Living Systems · [shannondobbs.com](https://shannondobbs.com) · [livingsys.org](https://livingsys.org)
