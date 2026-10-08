# Related work

*A companion to* Solid Ground. *Shannon Dobbs. Text CC BY 4.0.*

This is the longer version of the section in *Solid Ground* called "The work this stands on." While I was preparing patent filings in August and September 2026, I searched the public record (papers, standards drafts, and patents) for the work closest to each part of this methodology. I am publishing what I found so that credit lands where it belongs, and so that anyone reading this can see the neighborhood it lives in. This was my own search, not a professional one, and it is not complete.

The short version: every individual part of this methodology already exists somewhere, often in excellent work by other people. I found nothing that combines them the way described here, with one per-record rule, evaluated by the data store, that at the same time keeps a participant's own context away from the authority, governs what a goal-directed loop reads and writes, and cannot be changed by anything a machine agent reads.

## Shared workspaces for many agents

The idea of many knowledge sources reading and writing one shared structure goes back to the blackboard architecture of the 1970s (Hearsay-II) and to tuple-space coordination (Linda). Recent work brings it to language-model agents:

- **LLM-Based Multi-Agent Blackboard System for Information Discovery** (arXiv 2510.01285, September 2025). A central agent posts requests to a shared board and other agents volunteer to answer by capability, with no central coordinator. It does not include per-record governance, participant-held context, or a loop that runs to mastery.
- **Governed Shared Memory for Multi-Agent LLM Systems** (arXiv 2606.24535). Role- and attribute-based policies over shared agent memory, enforced in the application.
- **PatchBoard** (arXiv 2605.29313). Agents propose schema-checked edits, and each worker may only edit the paths it has been granted.
- **Terrarium** (arXiv 2510.14312), a test bed for safety, privacy, and security on blackboard-style agent systems, and **Decentralized Multi-Agent Systems with Shared Context** (arXiv 2606.10662), where agents coordinate as equals over shared context.

## Goal-directed learning loops

- **GenMentor** (arXiv 2501.15749, January 2025). Maps a learner's goal to skills, finds the gaps, and schedules a learning path.
- **EduLoop-Agent** (arXiv 2510.22559), a closed diagnosis, recommendation, and feedback loop toward mastery of each knowledge point; **DeepTutor** (arXiv 2604.26962); **PACE** (arXiv 2603.05361); **AgentCAT** (arXiv 2606.21832); and work on tutoring agents augmented with pedagogical knowledge (Expert Systems with Applications, S0957417426023237).

Goal-directed tutoring that persists until the learner gets there is a well-developed field. What I add is not the loop.

## Learner-held context

- **Principles of a Trusted Portable Learning Context** (1EdTech, RFC v2, 2026). A standards body working on the same problem in education. In its design, the institution holds the learner's context and decides, through a consent filter on its own systems, what each agent may see. The approach in *Solid Ground* runs the other way: the participant holds their own context, and the data layer keeps it from the authority.
- **Portable Records and Learner Profiles** (Cognia), and the wider literature on learner agency.
- **Solid** and its personal data pods: user-held data stores with access control at the data layer. The right idea, and the nearest in spirit.

## Governing what agents can do

- **Authorization Propagation in Multi-Agent AI Systems** (arXiv 2605.05440), **ProGent** (programmable privilege control for LLM agents), and **OpenKedge** (arXiv 2604.08601), on authorizing agents and governing their actions over shared resources.
- **Non-Malleable Origin-Bound Memory Authority** (arXiv 2606.24322), which binds memory records to their origin so they resist tampering, and studies of memory poisoning and out-of-band defenses (arXiv 2606.04329, 2606.04425, 2607.05120, 2606.26479).

## Scoped connections for agents

The Model Context Protocol and its scoped-access practice, **SkillScope** (arXiv 2605.05868), and **A Formal Security Framework for MCP-Based AI Agents** (arXiv 2604.05969). Giving an agent access to specific tools without giving it the host is now standard practice. *Solid Ground* uses it as the way separate participants join one governed board.

## Routing work between small and large models

Local-first routing, cascading model gateways, and **SWARM-LLM** (arXiv 2606.14711), which handles simple work on small local models and escalates hard work to larger ones.

## Patents in the neighborhood

- **US20250259042A1 and US20250259044A1**, a platform for orchestrating a privacy-enabled network of collaborating agents, run by a central orchestration engine.
- **US11282005B2**, selecting people and AI agents to accomplish a task.
- **US12412138B1**, agentic orchestration.
- **US6848109B1**, an earlier coordination system.

## Community economics

Will Ruddick and **Grassroots Economics** have spent more than a decade building commitment pooling with communities in Kenya. In their words, commitment pooling lets communities create, manage, and connect their own economic systems. Their work answers a different question from this one. Where a community needs what they build, that is where I would send them.

## Sources

- arXiv 2510.01285: https://arxiv.org/abs/2510.01285
- arXiv 2501.15749: https://arxiv.org/abs/2501.15749
- arXiv 2605.05440: https://arxiv.org/abs/2605.05440
- arXiv 2604.08601: https://arxiv.org/abs/2604.08601
- US20250259042A1: https://patents.google.com/patent/US20250259042A1/en
- US20250259044A1: https://patents.google.com/patent/US20250259044A1/en
- US11282005B2: https://patents.google.com/patent/US11282005B2/en
- US12412138B1: https://patents.google.com/patent/US12412138B1/en
- Cognia, Portable Records and Learner Profiles: https://source.cognia.org/issue-article/portable-records-and-learner-profiles/
- arXiv 2606.14711: https://arxiv.org/abs/2606.14711
- Other arXiv numbers above resolve at https://arxiv.org/abs/<number>.
