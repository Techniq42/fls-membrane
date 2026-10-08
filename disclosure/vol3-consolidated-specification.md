# Coordination Integration Architecture — Consolidated Specification v8

> Specification as prepared in 2026, in the inventor's voice, published as a defensive publication under CC BY 4.0 instead of being filed. Where it says "this application," read "this specification." Not legal advice.

---

## TITLE

**Coordination Integration Architecture: A Fractal, Governed Shared-Memory Methodology for Heterogeneous Human and Machine Agents, with Sovereign Dual-Context Composition, Capability-Scoped Participation, and Recursive Goal-Directed Operation.**

## CROSS-REFERENCE TO RELATED APPLICATIONS

This application claims the benefit of the following United States applications, each incorporated by reference in its entirety: Application 19/409,604, filed December 4, 2025 ("Fractal Coordination Architecture"); Application 19/411,766, filed December 8, 2025 ("Recursive Adaptive Learning Protocol"); Provisional Application 63/935,543, filed December 10, 2025 ("Autonomous Coordination Node"); Provisional Application 63/935,743, filed December 10, 2025 ("Adaptive Bioregional Food Infrastructure"); and Provisional Application 63/940,998, filed December 15, 2025 ("Bioregional Nexus Systems").

Each claim element takes the earliest of these dates at which that element was both disclosed and enabled. The interlock of claim 1, and the per-record governance mechanism, are matter first reduced to practice in 2026 and take this application's filing date; the individual legs have earlier support in the applications listed above.


## FIELD OF THE INVENTION

The invention relates to distributed coordination methodologies; the orchestration of heterogeneous software agents together with human participants; access governance enforced at the data layer rather than by instruction; capability-scoped participation that does not require host-level access; adaptive, goal-directed computer-assisted instruction; and the delivery of coordinated services to resource-constrained and intermittently-connected devices.

## BACKGROUND OF THE INVENTION

I did not set out to build a computer system. People I knew needed help that was not there, and the same shape kept showing up in every system I ever stood in.

An Army unit that could not get parts, while three blocks away on the same post another unit sat on them, stockpiled in a conex, invisible because of the way priority ran at the post level. A refugee camp with one shared tablet, a hundred and twenty kids, and no lesson plans. A church with a fundraising hall and a mission, and a young nonprofit a few neighborhoods over that could have been its hands, neither one able to see the other. Farming collectives on different islands of the same archipelago, each reinventing a technique the next island already proved, because nobody could see across the water. A food-rescue network where everyone knows where the loading dock is and nobody can get a straight answer about when the pickup comes. A practitioner with forty years of clinical work and no way to hand it forward while he still could. Ground-level agencies left stranded the day the agency upstream of them got gutted. Researchers watching their own work become someone else's to control or erase, finding out what it means to own the result but not the ground it sits on.

Every one of those started as a person standing in front of a gap, and the gap was almost never a missing resource. It was missing coordination. The pieces existed. The connection did not.

Existing systems fail that person in several structural ways. First, they put one coordinator in the middle of every exchange, so the coordinator becomes the wall. A teacher can individualize for five students and not for a hundred, and a hub that must touch every transaction cannot grow past the hours in its day.

Second, when the coordinator is a machine agent, existing systems tell it its rules in plain words, so anyone who can talk to the agent can talk it out of its rules. The instruction and the permission travel the same channel, which means the permission is only ever as strong as the last thing someone typed.

Third, when people try to coordinate value directly, existing systems reach for a money-like token and a heavy shared ledger to keep everyone honest. That works where money is scarce, but it locks out everyone who never wanted to run a currency, and it drags in wallets, keys, and volatility as the price of admission.

Fourth, coordination at this level has been getting priced out of reach. The cost of the models and the data-center capacity that good coordination now leans on is climbing past what under-resourced groups can touch at all, which quietly rebuilds the same wall the whole system was supposed to remove: the people who most need to coordinate are the ones who can least afford the toll.

Fifth, and this is the one that decides the security of everything above it, coordinating across separate systems has meant handing over access. To let another party's software join your board, you have given it a login to your machine, which is a standing door into everything on that machine, not only the part you meant to share. This is the sovereignty-versus-connectivity dilemma in one line: with the tools most groups have, you cannot coordinate effectively without handing someone a way to hurt you. Every act of connection has been an act of exposure.

What changed is that the parts finally got cheap and good enough at the same time to route around all of this. Storage that can enforce its own access rules, and language models small enough to run on a handset, now make it possible to build a shared board that people and machines read and write together, where the rules live in the wiring instead of in a paragraph somebody can argue with, and where a participant joins by being handed exactly the records it is assigned, for exactly the reason assigned, through exactly the operations it is permitted, and can be removed the instant it acts badly, without ever having been given the keys to the machine.

A person with a cracked cell phone can post a request for help into that shared memory, and whatever engine is watching and big enough to answer picks it up and writes the answer back into the same place, on the same machine or a different one. The request and the answer are notes passed across one shared state, so a data center is touched only when a question genuinely needs one, in single sips rather than in bulk, and the engine that answers can as easily be a spare local machine on someone's home solar. An operator nineteen thousand miles away, on a cracked phone and borrowed cycles, gets what I get. That is the invention, and I have watched it run.

This was not obvious, and the proof is who did not build it. The best-resourced builders in the world were standing next to these same tools, with every incentive to use them, and they shipped adjacent things instead: document generators, file assistants, chat windows. None of them built a sovereign coordination membrane where governance lives in the data layer. If it were obvious from where they sat, with the resources they hold and the incentives they carry, it would already exist. It does not. It took an operator with a particular set of lived constraints, moving real resources and real people without a central authority anyone still trusted, to need this badly enough to see it and build it.

I will name two of those constraints, because each produced a load-bearing part of the design. The first is that I am documented neurodivergent, inattentive-type ADHD. The thing that does not work for a brain like mine is being asked to hold an entire context in my head and re-explain the same background to a system over and over before it can help. So I built the opposite: a context authored once, kept by the person it describes, and composed into the work at run time, so the tool arrives already knowing who it is serving. I built it to second-brain myself, and a mechanism built to accommodate one specific executive-function profile turned out to generalize cleanly, because the structural problem underneath it, a person whose capacity is variable being asked to perform as if it were fixed, is shared across a very wide range of disabilities.

The second constraint is that the security posture of this design is not academic. It comes from an inventor with an intelligence-security and arms-room background, awarded for securing an arms room, who has also spent years on the receiving end of professionals whose entire aim was to do harm, and who defended businesses, property, and an organization through it. The system hands a stranger only the exact records assigned, for the assigned reason, and can eject them instantly, because it was built by someone who has met the people it is defending against. It assumes bad actors by default because assuming otherwise has a cost I have personally paid.

## SUMMARY OF THE INVENTION

The invention is a coordination methodology, not a device. It is one self-similar pattern that shows up the same way in a server coordinating research, in a food-rescue network coordinating pickups, in a waste-to-value stream coordinating feedstock, and in a neighborhood store coordinating access. In each, the pieces already exist and only the connection is missing, and in each the connection is made the same way, by a governed shared memory that heterogeneous agents, machine and human, read and write together. Because the pattern is self-similar across these scales and domains, understanding it in one transfers to the others, and the device on which it happens to run is only ever the body the pattern landed in.

The invention is a combination of three legs, and its whole weight rests on the narrow point where they meet. Taken alone, none of the three is new. Recursive goal-directed tutoring exists. Learner profiles exist. Record-level access control is decades old. What did not exist, and what is claimed here, is the single interlock that fuses them: **one per-record access rule, evaluated by the store that holds the state, that at the same time (a) withholds the participant's own context from the authority, so sovereignty is enforced by the data layer and not by a promise, (b) governs the records the recursive learning loop reads and writes, and (c) cannot be altered by anything a machine agent reads.** Sovereignty, governance, and recursion do not sit side by side; they are enforced by one rule at one layer. That is the invention, and everything else in this document is the context that rule operates in.

The first leg is recursive, goal-directed adaptation: a protocol given a goal that works backward from it, deriving the steps, generating output, checking it against a completion criterion, and regenerating until the criterion is met, which applied to instruction means it persists until the learner generates the specified mastery result rather than until a clock runs out.

The second leg is sovereign dual-context composition: an authority-authored context composed at run time with a sovereign, participant-held context the participant continues to hold, so operation is individualized without the authority ever taking custody of the participant's context, pushing information sovereignty down to the family and the terms of service.

The third leg is governance enforced at the storage layer and immune to instruction: access decided by a per-record rule the store evaluates, not modifiable by anything a machine agent reads, so the prompt was never the gate.

Around that interlock the methodology adds coordination without coupling. A participant joins the shared state through a capability-scoped connection, granted the ability to invoke a defined set of permitted operations on exactly its assigned records and nothing more, never holding host-level or datastore-level access to the machine that carries the state. It can therefore be admitted without being trusted and revoked the instant it misbehaves, without disturbing any other participant, and the same capability-scoped connection holds wherever the shared state lives, whether on a server, on a single handset with no server at all, or spanning two sovereign boards, letting a participant join or two boards federate without either reaching into the other. This is how the system resolves the sovereignty-versus-connectivity dilemma: connectivity without exposure. A dispatcher that routes but does not reason lets a small local model, a large paid model, and a human all attach to the same board, and a party that hits its ceiling writes a record asking for help that a higher tier answers into the same record, asynchronously, on spare or off-grid cycles.

The methodology is domain-independent. It applies wherever parties that already hold complementary pieces are kept from acting together only by the absence of a shared, legible state that each can read and write under its own sovereignty. That condition, siloed holders of complementary capacity, recurs across teaching, food, waste, materials, labor, and research, which is why the same pattern lands in each, and why the claims are drawn to the pattern rather than to any one domain.

## BRIEF DESCRIPTION OF THE DRAWINGS

FIG. 1 is a diagram of the architecture, showing the agents, the shared state, and the single per-record rule that enforces sovereignty, governs the recursion, and resists instruction. FIG. 2 shows the governance boundary, with the authorization channel held separate from the instruction channel. FIG. 3 shows the composition of an authority context with a sovereign participant-held context that the participant retains, the per-record rule withholding it from the authority. FIG. 4 shows the escalation sequence, in which a help request written by a lower tier is claimed and answered by a higher tier in the same record. FIG. 5 shows the recursive loop of reverse-navigation from a goal, generation, assessment, and regeneration, with achievement and guidance written back to both the participant context and the authority record. FIG. 6 is a fractal map, showing one coordination pattern expressed at many scales and in many bodies and domains. FIG. 7 shows two sovereign boards on separate servers coordinating through capability-scoped connections, neither holding host access to the other. FIG. 8 shows the capability-scoped connection and its revocation, contrasted with host-level access.

## REFERENCE NUMERALS

| # | Element |
|---|---|
| 100 | coordination system |
| 110 | shared coordination state (datastore) |
| 112 | records (rows) |
| 114 | per-record access rule (the interlock) |
| 120 | machine language-model agent |
| 122 | human agent |
| 130 | authority-authored context |
| 132 | sovereign, participant-held context |
| 134 | composition |
| 140 | recursive goal-directed loop |
| 150 | dispatcher |
| 160 | higher answering tier (162 small local model, 164 frontier model, 166 human) |
| 170 | capability-scoped connection |
| 180 | unauthenticated public seat / public (common) corpus |
| 182 | authenticated seat / owner-scoped records |
| 184 | edge authorization layer |
| 190 | help record |
| 200 | revocation |
| 210 | synapse connector |
| 230 | instruction inputs |
| 240 | metered third-party subscription service (answering capacity) |

## DETAILED DESCRIPTION

### Definitions

As used herein, sovereign means control vested in, and enforced at, the layer held by the party the artifact serves; sovereignty is a structural condition, not a policy promise.

A SOUL is a narrative context artifact, read as a story rather than a configuration, that tells its reader who it is and who it serves. An agent's sovereignty does not live in its SOUL, which is why a SOUL is safe to share; sovereignty lives one layer down, in what each call is wired to do and allowed to see.

An owner-scope is a named scope, referred to in the running embodiment as a holon, that the access rule uses to decide which records a given connection may see. A seat is a participant in the shared state, human or machine, that reads and writes records under an owner-scope. The blackboard, or membrane, is the shared, legible state that seats read and write, together with the storage-layer rules that govern it. A tier is a class of answering capacity, for example a small local model, a large paid model, or a human. A capability-scoped connection is an interface through which a seat may invoke a defined set of permitted operations on assigned records without holding host-level or datastore-level access to the machine carrying the state. A synapse is such a connection between two sovereign membranes on separate servers.

### The interlock

The substrate is a datastore (110) holding shared coordination state as records (112), read and written by a plurality of seats, at least one of which is a machine language-model agent (120), and one or more of which may be a human agent (122). Access to those records is decided by a single per-record access rule (114) evaluated by the store itself.

That one rule (114) does three things at once, and the doing of all three by one rule at one layer is the invention. It withholds the participant's own context (132) from the authority (which contributes its own context, 130), so the sovereignty of that context (132) is a fact of the data layer and not a policy anyone can quietly change. It governs which records (112) each seat, including the recursive loop (140), may read and write. And it is evaluated by the store, so nothing a machine agent (120) reads in its instruction inputs (230) can alter it, because the instruction channel and the authorization channel are different channels. Sovereignty, governance of the recursion, and immunity to instruction are therefore not three features to be separately maintained; they are three consequences of the one rule (114). Weaken the rule and all three fail together; enforce it and all three hold together.

In the running instance the rule (114) is straightforward: a seat may see a record (112) if the record is marked common, or if the record's owner-scope matches the scope set for that seat's own connection. The store may be a relational database enforcing the rule as a row-level security policy, as in the reduction to practice below, or any other store that can enforce a per-record rule, and it runs equally on a single device holding its own local store with no server present.

### Participation, composition, and coordination

A seat connects to the shared state (110) through a capability-scoped connection (170) rather than a login to the host. The connection exposes a fixed set of permitted operations, and the seat invokes those and nothing else, never receiving host-level or datastore-level credentials, so joining the board is not a foothold in the machine that carries it. Because the grant is a capability rather than an account, it can be revoked (200) at the layer at any moment, ending that seat's participation immediately while every other seat continues undisturbed.

A composition step (134) combines an authority-authored context (130), which sets the goal, with the sovereign participant-held context (132), which carries the parameters that fit operation to the individual, producing individualized operation while the per-record rule (114) keeps the participant's context (132) out of the authority's reach.

A dispatcher (150) recognizes a task and forwards it to a tier (160) by matching an attribute of the task to that tier, without generating a substantive answer during routing, so the system behaves the same whether the answer comes from a small local model (162), a large paid model (164), or a human (166). Work moves asynchronously: a task written to the board is a ticket a seat volunteers to pick up when able, and the board records that a ticket was picked up, delivered, and critiqued by a different seat, so capacity is offered when free rather than rented on a meter. A seat that reaches its ceiling writes a help record (190), and a higher tier claims and answers it into the same record (190), the asker and answerer decoupled in time and identity, neither holding the other's keys.

### Public and private participation on one rule

The same per-record rule (114) serves both public and private interaction without a second gatekeeping system in front of it. A seat may join unauthenticated, as a public seat (180), whose connection carries no owner-scope, so the rule (114) permits it to read only records (112) marked common, that is, the public corpus; or a seat may join authenticated (182), its connection carrying an owner-scope, so the same rule (114) additionally permits it the records within that scope, for example deeper data and operational strategy. One rule decides both cases; the public surface and the private board are two readings of the one governance boundary, not two systems. In one embodiment the authenticated-or-not decision and the capability-scoped connection (170) are enforced at an edge authorization layer (184) placed in front of the datastore, which admits or refuses a seat before any request reaches the host, so the machine carrying the state (110) is never exposed to a public seat, and an entire public site can be governed by the same rule that governs the private board. This removes the need for a separate platform to gate access, because the gate is the rule.

The answering tiers (160) need not be owned. In one embodiment one or more tiers are metered third-party subscription services (240) invoked a task at a time, so the coordination stands up on rented commodity capacity. Sovereignty is unaffected, because it is enforced by the rule (114) at the store (110) and not by ownership of the compute that answers: a rented model sees only what the rule hands the seat it serves, for exactly the task assigned. Capability, not capacity, is what each subscription is admitted to exercise, which is how a party holding only subscriptions and a low-cost store can stand up sovereign coordination it fully governs.

### The recursive loop

The recursive protocol (140) begins from a defined goal and reverse-navigates, deriving the steps toward that goal rather than executing a predetermined sequence, then generating output, evaluating it against the completion criterion, and regenerating output aimed at what the evaluation surfaces, repeating until the criterion is met. Applied to instruction, the loop reads how a given learner is doing and adjusts its approach in response, and it persists until the learner generates the specified mastery result, whether that takes three passes or five hundred. The specific techniques by which a learner's difficulty is diagnosed and a presentation is adjusted are well developed in the art and are not the point of novelty here; the point is that the loop runs over state governed by the one rule above, and that on completion it writes achievement, guidance, and a score back into both the participant's sovereign context and the authority-facing monitoring record, so the system's understanding of everyone involved improves from the same result, not only the learner's.

### Compounding across agents, bounded by the one rule

Because the loop (140) runs over a shared state (110) that many seats read and write at once, the recursion does not stay confined to one path. A plurality of agents pursuing goals over the same governed state compound one another's progress: each result written back improves the state the next agent reads, so coordination accelerates as the board fills. The acceleration deepens when the agents recursively decompose a larger goal into sub-goals, each sub-goal pursued by the loop (140) and its result composed back toward the parent, so a single large objective is carried by many agents at once over one legible state. Goal decomposition by agents is, by itself, known; what is claimed is its running over the per-record-governed shared state among capability-scoped sovereign seats, so the compounding is inseparable from the governance. The same rule (114) that enables the compounding also bounds it: an agent reads and writes only the records its scope permits, cannot be argued out of that boundary by anything it reads, and a step that requires a person is escalated to a human seat (122). The brake and the accelerator are the one rule, which is what makes rapid multi-agent goal-pursuit a governed capability rather than an ungoverned one.

### Reduction to practice

Of the three legs, the governance leg is reduced to practice on low-cost hardware, together with the escalation and routing coordination and the capability-scoped connection. The recursion and the sovereign-composition legs, and therefore the interlock that fuses all three, are set out in constructive form: described in enough detail to be made and used, which is legally sufficient.

The running instance is a Postgres database named membrane on a single low-cost virtual server, roughly eleven gigabytes of memory, no graphics processor. Row-level security is live: the per-record rule governs the escalation and tag lanes as a row-level security policy, and the same pattern applies to any lane that needs it. The owner-scope registry is privilege-separated at the database level, owned by the database superuser and not readable by the application role at all, so sovereignty here is enforced by ownership and not merely by policy.

The capability-scoped connection is built and proven, and proven across separate machines: a connection layer exposes the board as a fixed set of permitted operations, and a seat running on one server has joined and coordinated on a board carried by another server, invoking only those operations, holding no login to the other machine and no credentials to its database. A further sovereign box stood up its own instance of the kit and connected the same way. This is the strongest evidence that the invention is not a single device: the coordination provably crosses sovereign machines, none of which can reach into another.

The governance leg is demonstrated by 494 research findings produced across five countries and stored under owner-scope-private visibility with a source identifier on each (145 Trinidad and Tobago, 184 Jamaica, 76 Belize, 49 Guyana, 40 Bahamas), held under per-owner scope and carrying provenance by construction. The escalation and routing coordination is demonstrated directly: a small local model that reached its ceiling wrote a help record and a larger local frontier model claimed and answered it into the same record, and external requests through a front door were triaged and answered the same way. The board has passed work between machines under different model subscriptions and between paid and local non-subscription models. A forkable reference implementation of the governance leg, code under Apache 2.0 and prose under CC BY 4.0, is published, and has passed an end-to-end setup and escalation round trip on a throwaway database.

### Embodiments across bodies and domains

The methodology is self-similar, so its embodiments are the same pattern in different bodies and domains rather than different inventions. Except where the reduction to practice states otherwise, the following are constructive.

The flagship embodiment is education. An instructor authors a course context; a participant is guided to author their own sovereign context, carrying their neurodivergence, study habits, and needs, which stays on the participant's own account or device. A questionnaire in the course context helps the participant build that sovereign context, checking for it on the first session, initiating one if absent, and prompting its evolution across courses, so it is authored, owned, and carried by the participant. The two contexts compose at run time, the recursive loop runs over the governed state, and on mastery the system writes achievement and guidance back to both the participant's context and the instructor's record. One coordinator monitors many paths while the system handles each. Because the per-record rule keeps the participant's context out of the institution's reach, accommodation happens without the institution holding the sensitive profile. Where an expert's documented knowledge is the subject, generated instruction is grounded in that corpus through retrieval-augmented generation.

A second embodiment is community memory, recording who gave and who received rather than who owes whom, letting a gift economy remember itself past one person's memory without a circulating medium and without a ledger referee, holding relationships rather than debts, a record of contribution serving as a priority signal.

A third embodiment is a tribute or memorial use, in which each honored subject becomes a sovereign node with its own page and its own links to its story, one sovereign subject per generated node; for example, a veteran song-sharing project in which veterans and songwriters hand each other songs and the stories beneath them.

A fourth embodiment is an end-to-end coordinated traversal, in which a single request is fulfilled not by one delivery but by a sequence of discrete, capability-scoped hops across heterogeneous nodes, tiers, geographies, and modalities, every hop reading from and writing to the one shared state (110) under the one rule (114), no node holding another's keys. In a worked instance, an operator with a handheld device posts a request into a messaging channel; a machine seat (120) on one server reads it and writes it as a record (112) into the shared state; a routing pass classifies the record and, finding it needs a higher tier, writes an escalation into a help record (190); a higher tier (160), a frontier model or a human (122), claims and answers it, and the answer is itself a new goal, for example to produce a video; that sub-goal is dispatched to a further node, for example a generation seat on a separate machine, which renders the media and routes it to a host, so a reference to the result flows back onto the shared state; and a dispatching seat delivers that reference to the original operator on the original channel for onward distribution. The deliverable output of such a traversal may take any form, including generated image or video to a cracked or intermittently-connected handset, an on-demand competency module overlaid on the participant's environment, or a heads-up or augmented-reality display. The delivery is one hop of many: a single coordinated act can span a dozen discrete actions and as many directions, several machines in different places, several tiers from a small local model to a human, and more than one modality, and remain one act because all of it happens over the one governed shared state. Because no single machine carries the whole traversal, this embodiment is also direct evidence that the invention is a methodology and not any one device.

A fifth embodiment is an on-device filter, the whole architecture on a single handset with no server, its store local, parsing distracting sound before it reaches the listener's earpiece; the same nervous system in its thinnest body.

A sixth embodiment is a cognitive prosthetic for a single operator coordinating many machine agents at once, giving many separate agent conversations one shared state to write into and read from, so the operator is not the only memory connecting them; the accommodation of the background generalized to any operator carrying more threads than a mind holds at once.

A seventh embodiment federates two sovereign boards through a synapse connection, each sharing offered state through capability-scoped operations without sharing host access, so many sovereign boxes coordinate while none can reach into another.

An eighth embodiment is a coordination game, in which the assign-the-records, assign-the-reason, and eject-on-bad-behavior controls are the control surface of a multiplayer world, players are seats, and the coordination the game rewards is the coordination the methodology performs, so play produces real coordinated outcomes.

A ninth set of embodiments carries the pattern into physical domains, and this one is grounded in already-proven parts. In a bioregional waste-to-value system the methodology coordinates three independently proven components into a loop none of them closes alone: institutional food rescue by blast-chiller preservation, proven at scale in a Fortune 500 food operation in Las Vegas; neighborhood retail on the pre-supermarket store model that supplied the American Southwest for generations; and organic-waste transmutation into soil amendment by microbial methods, for example effective-microorganism or bacterial-photosynthesis approaches, as proven over decades in instances such as VRM Biologik's HumiSoil. Each component works; what did not exist was the shared board that lets the party holding a food-rescue surplus, the party holding a waste liability, and the neighborhood that needs both see the same state and act on it. The components are prior and belong to those who proved them and are not claimed; the invention is the coordination that fuses them.

A tenth embodiment draws the physical pattern to a single named place with deliberate specificity, so that it is not a diagram but a thing a reader could stand up. In this embodiment a rural-to-urban and urban-to-rural circularity hub, sited for example at Fort Lupton, Colorado, operates as a makerspace and educational pathway for post-automation workforce development, coordinating agricultural-circularity feedstock, food rescue, waste transmutation, and the training of the people who run them, on one governed shared board. The specificity is the enablement: naming the place, the function, and the flows describes the embodiment in enough detail to be made and used, and it is offered so that if the named party does not carry it forward, any other party in any other place can.

An eleventh embodiment extends the waste-to-value coordination to seasonal-event and mixed municipal streams. Where a large seasonal gathering externalizes its waste onto a nearby metropolitan area, or where mixed high-rise residential waste resists sorting, the methodology coordinates the parties holding the waste, the parties holding recovery capacity, and the receiving uses around a shared board, so that an organics-clearing pre-sort stage removes the organic fraction and thereby unlocks the downstream recovery of the inert recyclable fractions. The organics-removal and recovery processes are prior, belong to those who proved them, and are named, not claimed; what is claimed is the coordination that lets the holder of the liability, the holder of the capacity, and the receiving use act on the same state. The pattern is replicable wherever an externalizing source and an available recovery capacity are kept apart only by the absence of shared coordination.

A twelfth embodiment carries the pattern into dissemination, so that the method of delivery is itself an instance of the method. A trunk record composes a set of leaf artifacts; each leaf is a self-complete unit that delivers its own value alone and also carries a reference back to the greater whole the trunk indexes, so a recipient who receives only one leaf still receives a complete gift and a legible path to the rest. Disseminated across heterogeneous channels, the leaves and the trunk are the same governed shared state read at different depths, and the outreach is therefore not a description of the coordination pattern but a running instance of it.

Further embodiments of the same pattern include an autonomous coordination node, a permeable regulatory membrane, a sensory-augmented competency interface, and a watershed-scale underwriting application, as set out in the incorporated applications.

### Prior art, acknowledged and distinguished

I want to give the people whose work this stands on their due, and to be plain about what is mine.

The base idea of several knowledge sources reading and writing a shared structure belongs to the blackboard architecture of the middle 1970s, and to the tuple-space coordination that accompanied it, and both are good ideas. More recently, an LLM-based multi-agent blackboard system posts requests to a shared board that autonomous agents volunteer to answer by capability, without a central coordinator. That teaches the volunteer-coordination pattern, and it teaches only that: it has no per-record governance, no sovereign participant-held context, and no recursion to mastery, and it does not fuse any of them. A goal-oriented tutoring framework maps a learner's goal to skills, identifies gaps, and schedules a path. That teaches the learning loop, and only that: it composes no sovereign context held out of institutional custody, and it governs nothing at the data layer. Capability-scoped remote interfaces are likewise known in general; the point of novelty is not the interface but its use as the means by which heterogeneous seats coordinate on governed shared state without host access.

None of these, alone or in any combination an examiner would be motivated to make, teaches the interlock claimed here: one per-record rule that enforces a participant's sovereignty, governs a recursive learning loop, and resists instruction, all at once. I do not claim the blackboard, the tuple space, the learning loop, the learner profile, or the scoped interface. I claim the single rule that makes the three legs one thing, and the coordination that rides on it.

Reputation and commitment pooling on a distributed ledger, as developed over a decade by Grassroots Economics (the work of Will Ruddick), was aimed at a circulating medium that needs a tamper-proof ledger because it circulates; this methodology records non-circulating cooperation, which removes the reason for the ledger and leaves a relational memory in its place. Record-level access control is old and standard, used here as the coordination-governance boundary rather than as tenant isolation, and as one leg of a combination rather than alone.

Independent creation is not a defense to prior art, and I make no such claim; I built the running system before I knew the name of the blackboard architecture, and I name it, and the nearer recent art above, as the prior art of record. A combination is judged as a whole, and publishing one leg does not teach the combination. Prior art defeats only what it teaches, and the teaching stops short of the interlock.

## CLAIMS

**1.** A coordination system comprising one or more processors and memory storing instructions that, when executed, cause the system to: maintain, in a datastore, shared coordination state as records accessible to a plurality of agents, at least one of the agents being a machine language-model agent; compose an authority-authored context defining a goal with a sovereign, participant-held context to produce individualized operation; and iterate over the shared coordination state a recursive cycle that derives steps toward the goal, generates output, evaluates a response against a completion criterion, and regenerates targeted output until the completion criterion is met; wherein access to the records of the shared coordination state is decided by a single per-record access rule evaluated at the datastore, and that same per-record access rule (i) withholds the participant-held context from the authority, thereby enforcing the sovereignty of that context at the datastore rather than by policy, (ii) governs which records the recursive cycle may read and write, and (iii) is evaluated independently of, and is not modifiable by, any instruction contained in inputs the machine language-model agent processes; such that the sovereignty of the participant-held context, the governance of the recursive operation, and immunity to instruction are enforced together by the one rule at the data layer.

**2.** A method comprising: maintaining, in a datastore, shared coordination state as records read and written by a plurality of agents including at least one machine language-model agent; composing an authority-authored context defining a goal with a sovereign participant-held context to individualize operation; iterating a recursive cycle that derives steps from the goal, generates output, evaluates it against a completion criterion, and regenerates targeted output until the criterion is met; and deciding access to the records by a single per-record rule evaluated by the datastore that at once withholds the participant-held context from the authority, governs the records the recursive cycle reads and writes, and is not alterable by any instruction contained in inputs processed by the machine language-model agent.

**3.** The system of claim 1, wherein the plurality of agents further includes at least one human agent, the human and machine agents coordinating through the same shared coordination state on equal footing.

**4.** The system of claim 1, wherein at least one machine language-model agent operates autonomously and escalates to a human agent only upon a defined condition.

**5.** The system of claim 1, further comprising a dispatcher that forwards a task among the agents to an agent tier by matching a task attribute to the tier without generating a substantive answer during routing, wherein an agent that reaches a capability ceiling writes a help record into the shared coordination state and a higher tier claims and answers that help record into the same record, the two decoupled in time and identity and neither holding the other's credentials.

**6.** The system of claim 1, wherein a seat connects to the shared coordination state through a capability-scoped connection that exposes a defined set of permitted operations on records assigned to the seat, such that the seat reads and writes the shared coordination state through those operations without being granted host-level or datastore-level access to the machine carrying the state.

**7.** The system of claim 6, wherein the capability-scoped connection is revocable at the connection layer such that the seat's participation is terminated immediately upon revocation without affecting any other seat.

**8.** The system of claim 6, further comprising a connection by which a second system on a separate server participates in the shared coordination state through capability-scoped operations, without either system holding host-level or datastore-level access to the other.

**9.** The system of claim 5, wherein a task written to the shared coordination state is asynchronously picked up by a volunteering seat, delivered, and independently critiqued by a different seat, each status being recorded to the shared coordination state.

**10.** The system of claim 1, wherein the datastore comprises a relational database and the per-record access rule comprises a row-level security policy evaluated by the database.

**11.** The system of claim 1, wherein the datastore is held locally on a single participant device with no server present, such that the combination operates without a server.

**12.** The system of claim 1, wherein a registry of owner-scopes is privilege-separated at the datastore such that an application role is denied read access to the registry.

**13.** The system of claim 1, wherein a record lacking a provenance identifier cannot be committed to the shared coordination state.

**14.** The system of claim 1, wherein the participant-held context is a self-authored artifact resident on the participant's own device or account.

**15.** The system of claim 1, wherein an authority-issued questionnaire bootstraps the participant-held context by checking for the artifact on a first session, initiating its creation if absent, and prompting its evolution as the participant progresses across sessions, such that the participant authors, owns, and evolves the artifact.

**16.** The system of claim 1, wherein the completion criterion is the learner generating a demonstration of a specified mastery objective, and the cycle persists until that demonstration is produced, independent of the number of iterations.

**17.** The system of claim 1, wherein, upon the completion criterion being met, the system writes achievement information, guidance information, and a score to both the participant-held context and an authority-facing monitoring record, such that both are updated from the same result.

**18.** The system of claim 1, wherein evaluating the response comprises identifying a cause of a comprehension failure and selecting the regenerated output in dependence on the identified cause.

**19.** The system of claim 1, wherein the generating of output is grounded, through retrieval-augmented generation, in a documented corpus of a designated expert, such that generated instruction transfers the expert's documented approach.

**20.** The system of claim 1, wherein the individualized output comprises generated media, including a rendered image or video, deliverable to a resource-constrained or intermittently-connected device.

**21.** The system of claim 1, wherein the individualized output comprises an on-demand competency module overlaid on a participant's physical environment through a heads-up or augmented-reality display.

**22.** The system of claim 1, wherein a single coordinating agent monitors at least one hundred individualized paths while the system handles operation of each path.

**23.** The system of claim 1, wherein the shared coordination state records relationships and contributions rather than priced transactions, enabling non-circulating cooperative coordination without a distributed-ledger referee, and wherein a record of contribution serves as a priority signal ordering access.

**24.** The system of claim 1, wherein the per-record access rule governs a selective, permissioned flow of specified asset or data classes across sovereign participant boundaries under a shared compliance context, such that a participant contributes or receives specified classes without dissolving the participant's boundary.

**25.** The system of claim 5, wherein the tiers comprise a local sub-frontier model, a paid frontier model, and a human, and at least one tier runs on locally generated or off-grid power.

**26.** The system of claim 1, wherein the same combination is instantiated across a plurality of domains comprising at least an educational domain and a physical-resource-coordination domain, the per-record shared state coordinating instruction in the former and coordinating goods or materials in the latter.

**27.** The system of claim 1, wherein a first subset of the agents are unauthenticated public seats whose connections carry no owner-scope, such that the per-record access rule permits them to read only records marked common, and a second subset are authenticated seats whose connections carry an owner-scope, such that the same per-record access rule additionally permits them records within that owner-scope, whereby one access rule governs both public and private participation without a separate gatekeeping application.

**28.** The system of claim 27, wherein the authenticated-or-unauthenticated determination and the capability-scoped connection are enforced at an edge authorization layer in front of the datastore that admits or refuses a seat before its request reaches the machine carrying the state, such that the machine is not exposed to an unauthenticated seat.

**29.** The system of claim 5, wherein at least one answering tier is a metered third-party subscription service invoked a task at a time, and the sovereignty and governance of the shared coordination state are enforced by the per-record access rule at the datastore independently of the subscription capacity, such that the combination stands up governed sovereign coordination on rented commodity compute.

**30.** The system of claim 26, wherein the physical-resource-coordination domain comprises coordinating a multi-stage waste-recovery flow in which an organics-removal stage clears an organic fraction and thereby enables downstream recovery of inert recyclable fractions, the coordination governing parties holding a waste liability, parties holding recovery capacity, and receiving uses, the removal and recovery processes themselves being prior and unclaimed.

**31.** The system of claim 1, wherein a plurality of the agents recursively decompose a goal into sub-goals, each sub-goal pursued through the recursive cycle over the shared coordination state and its result composed toward the parent goal, such that goal-directed operation compounds across the plurality of agents while no agent holds host-level or datastore-level access to another, and wherein the same per-record access rule that governs the shared coordination state also bounds which records the decomposition may read and write.

## ABSTRACT

A fractal, governed shared-memory coordination methodology lets heterogeneous agents, machine and human, work together through legible shared state, appearing as the same pattern in a server, a classroom, a handset, and a physical resource network. Its novelty is a single interlock: one per-record access rule, evaluated by the store that holds the state, that at once withholds a participant's own context from the authority so sovereignty is enforced at the data layer, governs the records a recursive goal-directed learning loop reads and writes, and cannot be altered by anything a machine agent reads. Recursive tutoring, learner profiles, and record-level access control are each old; fusing all three through one rule is the invention. Participants join through a capability-scoped connection, invoking only permitted operations on assigned records without host or datastore access, and any participant can be revoked instantly, so connectivity no longer requires exposure and two sovereign servers can coordinate without either reaching into the other. A dispatcher forwards tasks to answering tiers without reasoning, and a lower tier that hits its ceiling writes a request a higher tier answers into the same record, asynchronously and on spare or off-grid cycles. The governance leg and the capability-scoped connection are reduced to practice on low-cost hardware, the connection proven across separate sovereign machines; the recursion and sovereign-composition legs, and the interlock that fuses all three, are set out in constructive form.


---

### References of record

Hearsay-II blackboard architecture and tuple spaces; LLM-based multi-agent blackboard system (arXiv 2510.01285); GenMentor (arXiv 2501.15749); agent-authorization and privilege-control literature; MCP capability-scoping practice; US20250259042A1, US20250259044A1, US11282005B2; Grassroots Economics commitment pooling. See also the companion document *Related work*.