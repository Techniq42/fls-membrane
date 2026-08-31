# The synapse handshake: how two sovereign boxes hinge

A single caged seat lets one box reach into another's tools. Point two of them at each other and you
have a **hinge**: a bidirectional link between two sovereigns, each end independently scoped. Wire a
few hinges and you have a **mesh** - no hub, no center, no one box everyone has to trust.

## The client side (stdio-over-SSH)
The peer wires their MCP client to launch your server over SSH with their caged key. Example
`.mcp.json` entry (VS Code / any stdio MCP client):
```json
{
  "membrane-peer": {
    "command": "ssh",
    "args": ["-i", "<path-to-their-caged-key>", "<seat>@<your-host>"]
  }
}
```
The forced-command key means the SSH call can only launch the server - the `args` need no remote
command; your `authorized_keys` supplies it. They get the tools; they never get a shell or a credential.

## The hinge = two valves
```
   box A  --(A gives B a caged seat, scoped to holon b)-->  box B
   box A  <--(B gives A a caged seat, scoped to holon a)--  box B
```
Prove it both directions (each side reads the other's commons + posts through its scoped lane) and the
hinge is real. Either side can shut its own valve at any time.

## The mesh (the "swarm")
Each edge is its own hinge with its own permission scope:
```
A<->ARK    Z<->ARK    Z<->A    V<->I ...
```
`Z<->A` and `Z<->ARK` are entirely separate scopes; neither can see the other. Growth is **pairwise
consent** - you decide each hinge and exactly what it's allowed. Adding a node = they fork this kit,
stand up their own box, and any existing node that wants to hinge to them provisions a scoped seat
(and vice versa). No admission committee; no central board.

## What is - and isn't - "common"
- **The commons is the public corpus.** Knowledge meant to be shared goes on a website under CC BY 4.0
  (attribution preserved) or CC0 - permissionless, gettable by anyone, no host to trust because it's
  simply *published*. If it isn't public, it isn't a commons; it's yours, and the only one you trust
  with it is you.
- **Capacity is not common - it belongs to the box holder.** Each sovereign advertises what it offers
  and decides whether to accept a given query, request, or task. Admission control stays local.
- **Only de-identified relay crosses a hinge.** Private data never leaves its home box; what travels is
  the scoped, cite-linked answer. Interoperation without merging trust - membrane, not membership.
