# 05 - The coordination game: accept -> deliver -> (opt-in) check -> credit

Once sovereigns can hinge (`04-caged-seats.md`, `SYNAPSE-HANDSHAKE.md`), they need a way to hand work
back and forth that stays honest **without anyone in charge**. This is that game. It runs on a ticket
lane (open/claim/deliver/critique) plus a tag ledger.

## The lifecycle
1. **open** - a request lands as a ticket.
2. **accept** - a holder *chooses* to claim it (a switch flips: open -> claimed). Capacity is theirs;
   accepting is a sovereign act, not an obligation.
3. **deliver** - the result is returned to the requester **immediately**. The check does **not** gate
   the result - you get your answer and can move.
4. **check (opt-in only)** - on receipt the requester is offered a menu:
   - **Take it** (default - done)
   - **Get another opinion** (one cross-holon check)
   - **Swarm it** (several holons weigh in)
   - **Peanut gallery** (open critique)

   A check spawns only if the requester asks for one. If a strong hand took the ticket, take the answer
   and go - nobody unqualified gets to armchair-quarterback your work unless you invite them.

## Two rules that keep the check honest
- **No authority.** A critique is **append-only** - the checker can flag, question, or endorse, but
  **cannot override** the deliverable. Enforce it in RLS, not in etiquette.
- **Cross-holon only.** A check task is claimable only by a holon *other than* the deliverer's - you
  can't grade your own homework. Enforce it in the claim policy.

## Credit: bragging rights that can't be gamed
Helping and checking earn credit via the **tag ledger** - a running tally per holon. The one rule that
makes it real: the credit tag is **system-applied on a completed cross-holon event** (a delivery, a
check), never self-declared. You earn it by doing the work; you can't award it to yourself. Visible
credit is the auto-incentive: it pulls people to contribute *and* to check each other, with no boss
handing out gold stars.

Net: a self-verifying, self-incentivizing, permissionless mesh. Honesty and contribution become the
path of least resistance.

---
**Status (be honest about what's built):** the ticket **states** (open/claim/deliver/critique) and a
`tags` table exist and work. The **choreography** - the opt-in menu, the cross-holon + append-only
enforcement, and the system-applied credit ledger - is the pattern described here and is the next
layer to wire. Fork it, build it, carry the attribution.
