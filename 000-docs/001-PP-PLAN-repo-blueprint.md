# wild-admin-tools-mcp — Repo Blueprint

**Document type:** Canonical repo blueprint
**Filed as:** `001-PP-PLAN-repo-blueprint.md`
**Repo:** `wild-admin-tools-mcp`
**Status:** Active — Phase 0 planning
**Last updated:** 2026-03-18

---

## 1. Purpose

This is the canonical blueprint for `wild-admin-tools-mcp`.

It defines the repo mission, product vision, non-goals, architecture direction, safety model, and planning expectations before any implementation begins. It is the source of truth for what this repo is, what it will do, and what it will not do.

This document is written for future Claude Code sessions and for the operator. It is not an implementation spec. It is not the epic breakdown. It is the authoritative pre-implementation reference that all later planning and execution must align with.

This repo builds on patterns established by `wild-rails-safe-introspection-mcp` but introduces a fundamentally different safety challenge: governed mutation. Where the introspection server's safety model rests on the structural impossibility of writes, this repo's safety model must make writes possible while keeping them bounded, confirmed, auditable, and reversible.

---

## 2. Repo Mission

`wild-admin-tools-mcp` provides **governed, mutation-aware administrative operations for live Rails applications via MCP**.

It gives AI agents and authorized operators a structured, auditable way to perform common administrative actions — retrying failed background jobs, invalidating cache entries, toggling feature flags — without granting raw console access or unrestricted mutation capability. Every action is bounded by an allowlist, validated against blast radius caps, confirmed through a two-phase protocol for destructive operations, and recorded with before/after state snapshots.

The repo is the write-side companion to `wild-rails-safe-introspection-mcp`. Where that repo answers "what is happening in production?", this repo answers "how do I safely fix it?" Together they form the governed operational surface of the `wild` ecosystem. The introspection server reads; this server acts.

Because mutation is inherently more dangerous than observation, this repo requires a stricter safety posture in some dimensions: mandatory capability gate integration (not stubbed), two-phase confirmation for destructive operations, before/after state snapshots for every mutation, per-action blast radius caps, rate limiting, and an explicit action allowlist that controls what operations are even possible. Safe by default means: if the safety infrastructure is not configured, no mutations execute.

---

## 3. Problem Statement

Operators routinely need to perform administrative actions on production Rails applications: retry a stuck Sidekiq job, clear a corrupted cache entry, enable a feature flag for a canary cohort, or discard a batch of poisoned background jobs. They do this today through methods that are powerful but ungoverned:

- **Rails console access is unrestricted.** An operator with console access can execute any Ruby code. There is no allowlist, no confirmation step, no audit trail, and no blast radius cap. A typo in a console command can destroy data.
- **Direct database access is unmediated.** Operators writing raw SQL against production databases bypass every application-level safety check. There is no undo.
- **Admin dashboards vary wildly.** Some teams have Sidekiq Web, some have custom admin panels, some have nothing. Coverage is inconsistent. Audit quality is inconsistent. Access control is inconsistent.
- **AI agents cannot safely perform admin operations.** An agent that needs to retry a failed job or toggle a feature flag has no governed interface. Either it gets raw console access (unacceptable risk) or it cannot help (useless). There is no middle ground.
- **Usage is rarely audited in a structured, replayable way.** When an operator retries 50 jobs from the Sidekiq dashboard, there is typically no structured record of what was retried, what state those jobs were in before the retry, or what happened afterward. Post-incident forensics rely on memory and grep.

`wild-admin-tools-mcp` solves this by providing a governed mutation interface: the agent or operator gets a curated set of administrative tools instead of a raw console. Each tool declares what it does, validates its parameters, enforces blast radius caps, requires confirmation for destructive actions, captures before/after state, and logs everything. The operator can fix production problems without the ability to cause unbounded new ones.

---

## 4. Core Product Vision

The intended product is a mutation-aware, safety-governed MCP server that authorized AI agents and operators can use to perform common administrative operations on live Rails applications.

**What this means in practice:**

**Mutation-bounded by design.**
Every administrative action is drawn from an explicit allowlist. The server cannot execute arbitrary operations. If an action is not on the allowlist, it does not exist. New actions must be explicitly defined, reviewed, and added. The allowlist is the outermost boundary of what is possible.

**Dry-run as a first-class primitive.**
Every action supports a dry-run mode that previews the effect without executing it. Dry-run is not a debugging feature — it is a core safety mechanism. Agents and operators use dry-run to verify they are about to do what they intend before committing. Dry-run responses include the same structured data as real executions (affected records, predicted state changes) but apply no mutations.

**Two-phase confirmation for destructive operations.**
Actions classified as destructive — those that discard data, clear caches broadly, or affect multiple records — require a two-phase confirmation protocol. Phase one returns a confirmation token (nonce) and a human-readable summary of what will happen. Phase two requires the nonce to execute. The nonce is single-use and time-bounded. This prevents accidental execution and gives agents and operators a structural pause point.

**Before/after state snapshots.**
Every mutation that executes captures the state of affected resources before and after the action. The audit trail includes both snapshots. This enables post-incident analysis ("what did that retry actually change?") and supports future undo capabilities. Snapshot depth is bounded — not every field of every record, but enough to reconstruct what happened.

**Mandatory capability gate integration.**
Unlike the introspection server, which stubs the capability gate in v1, this repo requires real capability gate integration from day one. Administrative actions are too powerful to ship without external access control. If the capability gate is unavailable, administrative operations fail closed — they do not execute.

**Per-action blast radius caps.**
Each action defines a maximum blast radius: the maximum number of records it can affect in a single invocation. A job retry tool might cap at 100 jobs per call. A cache invalidation tool might cap at 1000 keys per pattern. These caps are not configurable upward beyond hard limits — they are structural safety boundaries.

**Rate limiting.**
Each action is rate-limited per caller and globally. An agent that calls `manage_background_jobs` 500 times in a minute hits a rate limit before it can cause runaway damage. Rate limits are conservative by default and configurable within hard bounds.

**Action allowlist — not open-ended.**
The server does not accept "execute this admin operation." It accepts "retry this specific job" or "invalidate this cache key" or "toggle this feature flag." The operations are named, parameterized, and bounded. There is no generic "do thing" escape hatch.

**Audited invocations with before/after state.**
Every action — whether it succeeds, is denied, dry-runs, or errors — produces an audit record. The record captures: caller identity, action name, parameters, dry-run flag, confirmation nonce (if applicable), before-state snapshot, after-state snapshot (if executed), outcome, and timestamp. This is not optional.

**Operational administration, not analytics or reporting.**
The tools answer "can you retry that failed job?" and "can you toggle this flag for testing?" — not "how many jobs failed last month?" or "what percentage of users have this flag enabled?" Analytics questions belong elsewhere.

---

## 5. Non-Goals and Boundaries

These boundaries exist to keep the repo focused. Scope creep in the direction of any of these will dilute the repo's safety model and delay a useful v1.

**Not a read-only introspection server.**
This repo does not duplicate the read-only tools provided by `wild-rails-safe-introspection-mcp`. Record lookup, schema inspection, and read-only queries belong in that repo. This repo acts on state; that repo observes state. Some read operations exist here (inspecting a job's status before retrying it) but only as components of administrative workflows, not as standalone introspection tools.

**Not arbitrary Ruby/Rails console execution.**
The server does not provide a general-purpose Rails console interface. It does not accept Ruby code as input. It does not support `eval` or dynamic method dispatch on user-supplied strings. A tool that accepts arbitrary Ruby defeats the entire safety model. Rails console proxying is explicitly a v2 consideration at the earliest, classified as the highest-risk feature this repo could ever ship, and would require its own dedicated safety analysis.

**Not an analytics or reporting platform.**
Aggregation queries, time-series analysis, job failure rate dashboards, and cache hit-rate reports are out of scope. The tools answer operational questions about specific resources, not statistical questions about populations.

**Not full database migration execution.**
Running ActiveRecord migrations, modifying schema, or executing DDL is not in scope. Migrations have their own tooling and review workflows. Exposing migration execution through an MCP server creates unbounded risk with minimal incremental value.

**Not user management operations (v2).**
Creating, modifying, suspending, or deleting user accounts is a high-sensitivity domain with legal, compliance, and privacy implications that exceed what v1 should tackle. User management is explicitly deferred to v2, where it will require its own safety analysis and likely its own capability gate policy class.

**Not Rails console proxying (v2).**
A governed, bounded, auditable Rails console proxy is a legitimate future feature and the single highest-risk tool this ecosystem could ship. It is not a v1 feature. It requires: sandboxed execution, output sanitization, timeout enforcement, write detection, and a capability gate policy class that treats it as a privileged escalation. This is the "nuclear option" of admin tooling and must be treated as such.

**Not audit log lifecycle management (v2).**
This repo produces audit records. It does not manage the lifecycle of those records — retention policies, rotation, export, archival, or deletion. Audit log lifecycle management is a separate operational concern that may live in this repo's v2 scope or in a dedicated operational tooling layer.

**Not a kitchen-sink admin platform.**
Feature requests that sound like "while we're here, can it also manage deployments / run rake tasks / restart services / ..." belong in a separate repo or a later phase. Ship a narrow, trustworthy v1 with three well-governed tool categories.

---

## 6. Primary Users and Use Cases

### Users

**Platform and Rails engineers** — using the server to perform routine administrative operations on production systems during incident response, debugging, or maintenance windows. These users today use Rails console or Sidekiq Web and want a governed alternative that reduces their risk.

**Ops and SRE teams** — performing bulk administrative actions (retry all failed jobs of type X, invalidate cache prefix Y) through a tool that enforces blast radius caps and provides audit trails. These users value the structural safety properties over raw speed.

**AI infrastructure teams** — integrating the server into agent-powered operational workflows where the agent needs to fix production conditions as part of a larger task. The agent needs to retry a failed job, clear a stale cache, or enable a feature flag — and needs to do so without raw console access.

**Security and compliance reviewers** — using audit trail output (with before/after state snapshots) to understand what administrative actions were taken, when, by whom, and what changed. The before/after snapshots are particularly valuable for post-incident forensics.

### High-value early use cases

These are the use cases that define what a credible v1 looks like. If the server handles these well, it is useful:

1. **Retry a specific failed background job safely** — identify a failed Sidekiq/GoodJob job by ID, preview what retrying it would do (dry-run), confirm the retry, and capture before/after state (job status before retry, job status after retry).

2. **Discard a batch of poisoned jobs with blast radius caps** — an operator identifies 200 jobs stuck in a retry loop. They use the tool to discard up to the blast radius cap (e.g., 100 per invocation), with two-phase confirmation, and a clear record of which jobs were discarded and what their state was.

3. **Invalidate a specific cache key or pattern** — a stale cache entry is causing incorrect behavior. The operator invalidates a specific key or a bounded pattern, with a preview of how many keys will be affected, confirmation for broad patterns, and a record of what was invalidated.

4. **Toggle a feature flag for testing or incident response** — a feature flag needs to be enabled for a canary group or disabled during an incident. The operator toggles the flag through a governed tool that captures the previous state, requires confirmation, and logs the change.

5. **Inspect job queue health as part of an admin workflow** — before retrying failed jobs, the operator inspects the queue to understand the scope of the problem. This is a read operation that exists to support the administrative workflow, not as standalone introspection.

6. **Audit what happened during an incident** — after an incident, a security reviewer examines the audit trail to see what administrative actions were taken, what state was changed, and whether the actions were appropriate. The before/after snapshots enable this without requiring separate investigation.

---

## 7. Early Architecture Direction

This section describes the expected shape of the system. It is directional — not a final design. Decisions will be refined during the epic breakdown.

### Major components

**MCP server layer**
The outermost surface. Implements the MCP protocol, exposes tool definitions, handles request routing, and enforces session-level controls. This is what clients (agents, CLI tools) connect to. Shares the MCP server pattern established by `wild-rails-safe-introspection-mcp` but with additional infrastructure for confirmation flows and mutation tracking.

**Tool registry**
A curated, explicit catalog of available administrative tools. Each tool has: a name, a description, a parameter schema, a safety classification (read/preview/mutate/destructive), a blast radius cap, a rate limit, and a handler. No dynamic or generated tools — all tools are explicitly defined and reviewed. The registry enforces that every registered tool has a dry-run implementation, a blast radius declaration, and an audit schema.

**Action executor**
The core component that distinguishes this repo from the introspection server. The action executor is the single code path through which all mutations flow. It enforces: the action is on the allowlist, parameters pass validation, blast radius caps are not exceeded, rate limits are not exceeded, the capability gate approves, the confirmation protocol is satisfied (for destructive actions), before-state is captured, the mutation executes, after-state is captured, and the audit record is written. No mutation bypasses the action executor.

**Mutation guard**
The policy enforcement layer for mutations. Enforces: action allowlist (is this operation permitted at all?), parameter validation (are the arguments well-formed and within bounds?), blast radius caps (how many resources will this affect?), rate limits (how often can this caller invoke this action?), and temporal constraints (is this action permitted at this time?). The mutation guard is the "no" layer — it exists to prevent actions that should not execute.

**Confirmation protocol**
Implements two-phase confirmation for destructive operations. Phase one: accept the action request, validate it, compute the preview (dry-run), generate a single-use nonce, and return the preview with the nonce. Phase two: accept the nonce, verify it is valid (not expired, not already used, matches the original action), and execute the action. The nonce is cryptographically random, time-bounded (configurable, default 5 minutes), and single-use. The protocol prevents: accidental double-execution, stale confirmations, and confirmation of an action different from what was previewed.

**Before/after state capture**
A subsystem that snapshots relevant state before and after each mutation. "Relevant state" is defined per action type — for a job retry, it is the job's status, error message, and retry count. For a cache invalidation, it is the existence and metadata of the affected keys. For a feature flag toggle, it is the flag's previous value and scope. Snapshots are bounded in size and depth to prevent the audit trail from becoming a full database mirror.

**Audit trail**
Every action — whether it succeeds, is denied, dry-runs, times out, or errors — produces an audit record. The record captures: caller identity, action name, parameters (sanitized), dry-run flag, confirmation nonce (if applicable), before-state snapshot, after-state snapshot (if executed), outcome (success/denied/error/timeout), error details (if applicable), and timestamp. Audit records are append-only and structured for later analysis. This is not optional. A mutation without an audit record is a safety defect.

**Capability gate interface**
The integration layer with `wild-capability-gate`. Unlike the introspection server, where the capability gate was stubbed in v1, this repo requires real capability gate integration. Every administrative action checks the gate before executing. The gate provides: caller authorization (is this caller allowed to perform this action?), action-level permissions (is this specific action enabled in the current policy?), and escalation tracking (is this action being performed under elevated privileges?). If the gate is unavailable, all administrative actions fail closed.

**Rails adapter layer**
The bridge between action execution and Rails/ActiveRecord. Handles the specifics of interacting with job backends (Sidekiq, GoodJob, Delayed Job), cache stores (Redis, Memcached, file), and feature flag systems (Flipper, LaunchDarkly, custom). The adapter is designed for extensibility — adding support for a new job backend should require implementing a defined interface, not modifying the core action executor.

### What this is not

Not a general-purpose admin console. Not a task runner. Not a deployment tool. Not a plugin marketplace. Not a multi-tenant SaaS. Build the components above and ship something useful with three tool categories.

---

## 8. Safety Model

Safety is the primary design constraint for this repo. Because this repo performs mutations — unlike the read-only introspection server — the safety model must be more rigorous, not less. The fundamental challenge is: how do you make write operations safe enough to expose to AI agents?

**Mutation-bounded by design.**
The system can only execute actions that are on the explicit allowlist. The allowlist is the outermost safety boundary. If an action is not listed, it cannot be invoked — there is no way to request "execute this arbitrary operation." The allowlist is configuration-driven and reviewed. Adding a new action to the allowlist is a deliberate, auditable decision.

**Dry-run as a first-class safety primitive.**
Every action supports dry-run mode. Dry-run executes all validation, policy checks, and state inspection but applies no mutations. Dry-run responses are structurally identical to execution responses (same fields, same format) but marked as previews. This means the caller can verify what will happen before committing. Dry-run is not optional — it is a required implementation for every action.

**Two-phase confirmation for destructive operations.**
Actions classified as destructive require a two-phase confirmation protocol. Phase one returns a preview and a single-use, time-bounded nonce. Phase two requires the nonce to execute. This provides a structural pause point that prevents accidental execution. The nonce is: cryptographically random (not guessable), time-bounded (expires after a configurable window, default 5 minutes), single-use (cannot be replayed), and action-bound (the nonce is tied to the specific action and parameters from phase one — you cannot use a nonce from one action to confirm a different action).

**Before/after state snapshots.**
Every mutation captures the state of affected resources before and after execution. The snapshots are included in the audit record. This enables: post-incident forensics ("what did that action actually change?"), correctness verification ("did the retry actually change the job status?"), and future undo capabilities (not in v1, but the data foundation is in place). Snapshot depth is bounded per action type to prevent unbounded data capture.

**Mandatory capability gate — fail closed.**
The capability gate is not optional and not stubbed. Every administrative action checks the gate before executing. If the gate denies the action, it does not execute. If the gate is unreachable, the action does not execute. This is fail-closed behavior. The rationale: administrative mutations are too powerful to ship without external access control. An introspection server that falls back to open-access during a gate outage exposes read-only data. An admin server that falls back to open-access during a gate outage exposes mutation capability. The risk profiles are not comparable.

**Per-action blast radius caps.**
Each action defines the maximum number of resources it can affect in a single invocation. Caps are defined per action type and enforced by the mutation guard. Examples: job retry caps at 100 jobs per call; cache invalidation caps at 1000 keys per pattern; feature flag toggle caps at 1 flag per call. Caps have hard upper limits that cannot be configured upward — an operator can lower the cap but not exceed the hard limit. This prevents: runaway bulk operations, accidental "retry all" commands, and agents that loop without awareness of cumulative impact.

**Rate limiting per caller and globally.**
Each action is rate-limited. Rate limits are enforced per caller identity and globally across all callers. This prevents: a single agent from executing hundreds of mutations in rapid succession, coordinated (or accidental) multi-agent storms, and retry loops where an agent keeps retrying a failed action without backoff. Rate limits are conservative by default with configurable windows within hard bounds.

**Action allowlist — not open-ended.**
The action allowlist is the single most important safety control in this repo. It defines the universe of possible operations. Everything not on the list is impossible. The allowlist is: explicit (every action is named and parameterized), reviewed (adding an action requires deliberate configuration), versioned (the allowlist is tracked in configuration, not inferred), and auditable (changes to the allowlist are themselves loggable events).

**Identity and authorization context.**
Every invocation carries an identity: who or what is calling, with what credential or session token. Anonymous invocations are not permitted. The identity is: verified against the capability gate, recorded in the audit trail, used for per-caller rate limiting, and used for per-caller blast radius tracking (cumulative caps, not just per-invocation).

**Conservative defaults — safe until configured otherwise.**
When the server starts with default configuration, no administrative actions are enabled. The operator must explicitly configure the allowlist, the capability gate, and the action parameters before any mutations can execute. This is the inverse of "everything enabled by default." An unconfigured server is a safe server.

**Explicit separation from read operations.**
This repo does not provide general-purpose read tools. Reads that exist (inspecting a job before retrying it) are components of administrative workflows, scoped to the specific action context, and logged as part of the action audit trail. Standalone introspection belongs in `wild-rails-safe-introspection-mcp`.

---

## 9. Relationship to Other Wild Repos

This repo does not exist in isolation. Understanding its ecosystem connections shapes the architecture.

**`wild-rails-safe-introspection-mcp`** — The companion repo for read-only operations. These two repos form the governed operational surface of the wild ecosystem: one reads, the other acts. They are intentionally separated so the safety boundary is architectural, not just policy-based. They share: MCP server patterns (protocol handling, tool registration, session management), Rails adapter conventions (model reflection, backend abstraction), audit trail structure (common record format, compatible log schemas), and capability gate interface contracts. They do not share: safety models (read-only enforcement vs. mutation governance are fundamentally different), tool definitions (no overlap in tool catalogs), or configuration (each repo is independently configured). An operator might deploy both servers side by side, pointed at the same Rails application, with different capability gate policies.

**`wild-capability-gate`** — The access control layer. This repo has a mandatory integration with the capability gate — not optional, not stubbed. The gate provides: caller authorization, action-level permissions, and escalation tracking. The gate's interface contract must be stable before this repo's v1 ships. This is a hard dependency, not a soft one. If the gate is not available, this repo's administrative tools fail closed. Design implication: the capability gate interface must be defined early in this repo's development, even if the gate repo itself is still under development. The interface contract is the critical path, not the full gate implementation.

**`wild-session-telemetry`** — May capture operational usage events from this repo's invocations — action patterns, mutation frequency, denied actions, confirmation abandonment rates, blast radius utilization — as input to the broader observability pipeline. This repo does not depend on the telemetry repo, but can emit events that the telemetry layer picks up. Telemetry emission is a hook interface, not a hard dependency.

**`wild-transcript-pipeline`** and **`wild-gap-miner`** — May later analyze transcripts of agent sessions using this server to identify patterns: "what admin actions do agents attempt most often?", "what actions are denied most often?", "where do agents abandon the confirmation flow?" This is a Wave 2-3 concern, not a design constraint for v1.

**`wild-skillops-registry`** — May eventually register this repo's action catalog as a set of discoverable, versioned capabilities. Not a v1 concern.

---

## 10. Documentation Needs

As implementation proceeds, this repo will need durable supporting documents beyond this blueprint. These should be created as needed — not speculatively in advance — and filed in `000-docs/` per `/doc-filing` conventions.

Anticipated documents:

| Document | Purpose |
|----------|---------|
| Safety model (detailed) | Full spec for the mutation governance model: allowlist format, blast radius cap definitions, rate limit policies, confirmation protocol details, before/after snapshot schemas, fail-closed behavior |
| Architecture overview | Diagrams and descriptions of major components: action executor flow, mutation guard pipeline, confirmation protocol state machine, capability gate integration points |
| Tool catalog | The canonical list of MCP tools this server exposes, with parameter schemas, safety classifications, blast radius caps, rate limits, dry-run behavior, and confirmation requirements |
| Confirmation protocol spec | Detailed specification of the two-phase confirmation flow: nonce generation, expiry, binding, replay prevention, and edge cases (what happens if the system state changes between phase one and phase two?) |
| Threat model | Anticipated attack surfaces and mitigations: prompt injection leading to unauthorized mutations, confirmation bypass, blast radius cap circumvention, rate limit evasion, nonce prediction, stale-state exploitation |
| Capability gate integration spec | Detailed interface contract between this repo and `wild-capability-gate`: request format, response format, failure modes, fallback behavior (fail closed), and testing strategy |
| Blocked operations policy | The policy definition format: what operations are never allowed (even if someone tries to add them to the allowlist), what operations require elevated gate permissions, what operations are restricted to specific caller classes |
| Operator workflow guide | How to deploy, configure, and operate the server in a real Rails production environment: allowlist configuration, blast radius tuning, rate limit adjustment, audit log inspection |
| Evaluation strategy | How to verify the server is behaving safely and correctly: safety property tests, adversarial testing scenarios, confirmation protocol verification, blast radius enforcement verification |
| Adapter interface spec | The interface contract for Rails backend adapters: how to implement a new job backend adapter, cache backend adapter, or feature flag backend adapter |
| Glossary / terminology | Definitions of terms used in this repo: action, mutation guard, allowlist, blast radius, confirmation nonce, dry-run, before/after snapshot, fail-closed |

Create these docs when the work demands them. A doc that does not yet have a home in planned work belongs in `planning/notes.md` as a placeholder reference, not in `000-docs/` until the content is substantive.

---

## 11. Planning and Task Model

Before implementation begins, this repo will receive the following planning artifacts in order:

1. **Repo build plan (10 epics)** — a human-readable breakdown of the full repo scope into 10 outcome-oriented epics, each with clear mission, rationale, and child task breakdown
2. **Child tasks** — written in natural language, explaining the purpose of each unit of work and how it contributes to the epic's outcome
3. **Explicit dependency blocks** — between tasks within this repo and across repos where relevant, with prose rationale for why each dependency must be resolved first
4. **Natural-language annotations** — operator notes that provide context, state assumptions, flag blockers, and set evidence expectations for task closure
5. **Beads creation prompt** — a guided prompt for Claude Code to instantiate the full task structure in Beads
6. **Phased implementation prompts** — a set of guided Claude Code prompts for executing each phase, with room for pragmatic implementation choices within defined constraints

No implementation begins before this planning structure is in place.

### Expected epic shape

While the full epic breakdown is a separate document, the expected shape is roughly:

- **Foundation epics** (1-3): Project scaffold, safety model specification, mutation guard and allowlist framework, confirmation protocol, before/after state capture, audit trail with mutation-specific fields
- **Capability gate epic** (4): Real (not stubbed) capability gate integration — interface contract, request/response handling, fail-closed enforcement, testing against gate stubs
- **Tool implementation epics** (5-7): One epic per tool category — background job management, cache management, feature flag management — each with adapter abstraction, dry-run, confirmation flow, blast radius caps, and full test coverage
- **Integration and hardening epics** (8-9): Cross-tool integration testing, adversarial safety testing, rate limiting, operational deployment guide, evaluation strategy
- **Documentation and release epic** (10): Tool catalog, operator guides, evaluation results, v1 release

This is directional. The actual epic breakdown may adjust these boundaries based on dependency analysis and scope refinement.

---

## 12. Natural-Language Planning Standard

All future epics, Beads, annotations, and dependencies for this repo must be written in natural human language that tells the story of what is being built, why it matters, and how the pieces connect.

**The Beads-docs relationship for this repo:**
- Beads track execution — what is happening, in what order, with what outcome
- Docs preserve meaning — why decisions were made, what the safety model requires, what constraints are non-negotiable, why the confirmation protocol works the way it does
- Annotations connect the two — they link tasks to relevant docs and explain the "why" behind the work

**The narrative test:** a person reading the epics and tasks from top to bottom should understand what this server is, what makes it different from the introspection server (mutation governance, not read-only safety), what must be built first (safety foundation and capability gate, then tools, then integration), what the risky design decisions are (dry-run fidelity, blast radius accuracy, gate dependency), and how the work is expected to unfold.

**The mutation-awareness test:** a person reading any single epic should be able to identify: what mutations does this epic introduce? What safety controls govern those mutations? What happens if those controls fail? What evidence demonstrates the controls work?

**When to create a supporting document instead of relying on Beads:**
When a concept is too important to leave implicit in a task annotation — a safety policy, a confirmation protocol decision, a capability gate interface contract, a non-goal that must be preserved — create a document in `000-docs/` and reference it in the relevant task. Beads are not a substitute for durable explanation.

---

## 13. Risks and Design Tensions

These tensions are real. They will surface during implementation and must be managed consciously, not resolved by defaulting to one extreme.

**Power vs. safety.**
Administrative tools are inherently more dangerous than read-only tools. The introspection server's safety model has a simple foundation: no writes, ever. This repo does not have that luxury. Every feature adds power and adds risk. The safety model must be sophisticated enough to make mutations safe without making them so cumbersome that operators bypass the tool and go back to Rails console. If the safety friction is too high, the tool fails by being unused. If the safety friction is too low, the tool fails by enabling incidents.

**Dry-run fidelity.**
Dry-run must accurately preview what execution will do. But dry-run and execution are necessarily different code paths — dry-run observes while execution mutates. If they diverge, the preview is a lie. Maintaining fidelity between dry-run and execution is a persistent engineering challenge. Options: share as much code as possible between the paths, test that dry-run predictions match execution outcomes, and log discrepancies as safety-relevant events.

**Blast radius accuracy.**
Blast radius caps are only useful if the cap accurately reflects the scope of impact. A job retry cap of 100 is meaningless if each retried job triggers cascading side effects that affect thousands of records. Blast radius caps measure the direct scope of the action, not its transitive effects. This is a known limitation. Documenting it honestly is better than claiming caps provide guarantees they do not.

**Capability gate dependency — what happens during outages?**
The capability gate is mandatory. If the gate is down, admin operations fail closed. This is the safe default. But it means that during a gate outage, operators cannot use the admin tools at all — precisely when they might need them most (during an incident that also affects the gate). This is a real operational tension. Options: emergency bypass with elevated audit logging (dangerous), gate result caching with short TTL (compromises real-time access control), or accepting that gate outages are admin tool outages (operationally painful but safe). This decision must be made explicitly and documented, not defaulted into.

**Confirmation protocol usability.**
Two-phase confirmation adds safety but adds friction. For an AI agent, the two-phase flow is programmatically manageable. For a human operator using CLI tools, it is an extra step that feels slow during an incident. The protocol must be fast enough to not impede incident response while slow enough to prevent accidental execution. The nonce expiry window is the key tuning parameter: too short and it expires before the operator can confirm, too long and stale confirmations become a risk.

**Before/after snapshot scope.**
Capturing before/after state for every mutation is valuable but expensive. Full state snapshots of complex objects can be large, slow to capture, and sensitive (they may contain data that should not appear in logs). Snapshot scope must be tuned per action type: what fields are relevant, what fields are sensitive, how deep should association traversal go? Getting this wrong in either direction — too much data or too little — undermines the audit trail's value.

**Adapter abstraction breadth.**
The Rails ecosystem has multiple job backends (Sidekiq, GoodJob, Delayed Job, Resque), cache stores (Redis, Memcached, file, null), and feature flag systems (Flipper, LaunchDarkly, custom). Supporting all of them in v1 is impractical. Supporting only one of each is limiting. The adapter abstraction must be clean enough that adding a new backend is straightforward, but v1 should ship with the most common backend for each category and defer the rest.

**Product simplicity vs. platform ambition.**
There is a version of this repo that becomes a comprehensive production operations platform. That is not v1. v1 is three tool categories (jobs, cache, flags), each with governed mutation, dry-run, confirmation, blast radius caps, and audit trails. Platform ambitions — user management, deployment triggers, migration execution, console proxying — belong in the backlog, not the v1 scope.

---

## 14. MVP Recommendation

A realistic, credible v1 should do the following and nothing more:

**Background job management (inspect, retry, discard).**
Given a job backend (Sidekiq in v1), the operator can: inspect a job by ID (status, error, retry count), retry a specific failed job with dry-run preview and confirmation, discard a specific job or a bounded batch with two-phase confirmation and blast radius cap, and view queue health summary as context for administrative decisions. Before/after state captured for every mutation.

**Cache management (inspect, invalidate).**
Given a cache backend (Redis in v1), the operator can: inspect a cache key's existence and metadata, invalidate a specific cache key with dry-run preview, invalidate a pattern of keys with two-phase confirmation and blast radius cap (max keys affected), and view cache stats as context for administrative decisions. Before/after state captured for invalidations.

**Feature flag management (inspect, toggle).**
Given a feature flag backend (Flipper in v1), the operator can: read a flag's current state (enabled/disabled, per-actor state), toggle a flag with dry-run preview and two-phase confirmation, and capture before/after state (previous value, new value, scope of change). Feature flag toggles always require confirmation regardless of destructive classification — changing a flag is inherently a high-impact action.

**Mandatory capability gate integration.**
Every administrative action checks the capability gate. If the gate denies the action, it does not execute. If the gate is unreachable, the action does not execute. The gate interface is defined against `wild-capability-gate`'s contract. Testing uses a gate stub that simulates approval, denial, and unavailability.

**Mutation guard with allowlist enforcement.**
No action executes unless it is on the allowlist. The allowlist is configuration-driven. Default configuration has no actions enabled. The mutation guard validates parameters, enforces blast radius caps, enforces rate limits, and checks the capability gate before any mutation reaches the action executor.

**Two-phase confirmation protocol.**
Destructive actions require nonce-based confirmation. Nonces are cryptographically random, time-bounded, single-use, and action-bound. The protocol is tested for: expiry, replay prevention, and nonce-action binding.

**Audit trail with before/after state.**
Every action produces a structured audit record with before/after state snapshots. Records are append-only. The audit trail ships with the first tool, not as a later addition.

**Strong documentation and evaluation posture.**
The safety model doc is written before the code ships. The tool catalog is written concurrently. The operator workflow guide exists before anyone tries to deploy it. The evaluation strategy includes adversarial tests that specifically try to bypass the mutation guard, circumvent blast radius caps, replay confirmation nonces, and invoke actions without gate approval.

**What v1 explicitly does not include:** user management, Rails console proxying, custom action plugins, multi-tenant support, analytics/reporting, audit log lifecycle management, migration execution, deployment triggers, adapter support beyond one backend per category (Sidekiq, Redis, Flipper).

---

## 15. Current Status

This repo is in **blueprint and planning mode only**.

No application code exists. No Beads have been created. The GitHub repo has been initialized but contains only scaffold structure (CLAUDE.md, planning placeholders, license). No CI/CD has been configured.

This blueprint document is the first canonical planning artifact for the repo. The next step is the 10-epic breakdown.

---

## 16. Immediate Next Step

The next planning step for this repo is:

1. **Convert this blueprint into a 10-epic build plan** — each epic covering a major outcome area with human-readable mission, rationale, and child task breakdown. The epic structure must reflect the mutation-aware safety model: safety foundation and capability gate integration come before tool implementation.
2. **Define child tasks and dependency blocks** — in natural language, with prose rationale for ordering. Cross-repo dependencies on `wild-capability-gate` must be explicitly identified and tracked.
3. **Prepare the Beads creation prompt** — a guided Claude Code prompt that instantiates the full task structure in Beads.
4. **Then begin phased repo execution** — one epic at a time, with evidence-backed task closure at each step.

Do not begin implementation until the Beads structure is in place and the operator has reviewed the epic breakdown.
