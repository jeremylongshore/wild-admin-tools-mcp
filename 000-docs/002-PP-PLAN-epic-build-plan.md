# wild-admin-tools-mcp — 10-Epic Build Plan

**Document type:** Canonical repo build plan
**Filed as:** `002-PP-PLAN-epic-build-plan.md`
**Repo:** `wild-admin-tools-mcp`
**Status:** Active — Phase 0 planning
**Last updated:** 2026-03-18
**Blueprint reference:** `001-PP-PLAN-repo-blueprint.md`

---

## 1. Purpose

This is the canonical 10-epic build plan for `wild-admin-tools-mcp`.

It translates the repo blueprint into an implementation-ready execution story. This document is not Beads. It is not code. It is the structured, narrative planning layer between the blueprint (what we are building and why) and Beads (how we track doing it). When Beads are created, they must be faithful to this plan.

---

## 2. Planning Intent

The blueprint defines what this server is and what it must not become. This plan defines the order in which it gets built, why that order is correct, and what each phase must produce before the next phase starts.

The plan is written for two audiences:

**Future Claude Code sessions** — who need to understand the build narrative before touching code, and who must resist the temptation to skip ahead.

**The operator (Jeremy)** — who needs to be able to open this document at any point and understand exactly where the repo is in its story.

Every epic here earns the right to exist. The ordering is not arbitrary.

---

## 3. Sequencing Logic

The build sequence follows the same principle as the introspection repo — **earn the right to expose power before you expose it** — but with mutation-specific ordering that reflects the higher stakes of a server that changes production state.

The stack is built from the ground up:

1. **Foundation first** — repo structure, CLAUDE.md, README. Nothing else can happen without a clean working environment.

2. **Safety posture before code** — the safety model, mutation policy, threat model, and architecture decisions are written as documents before a single line of implementation is produced. The rules come before the engine. For admin-tools, these Phase 0 documents (003–006) are already drafted and this epic validates and finalizes them.

3. **Action executor before mutation guard** — the raw action capabilities (job operations, cache operations, flag operations) need to exist before the guard wraps them. But unlike introspection's read-only adapter, the executor is inherently dangerous — it performs mutations. That means the executor is built with dry-run and state capture baked in from the start, not added later.

4. **Mutation guard before audit** — the guard wraps every executor call with access policy enforcement: allowlist check, parameter validation, blast radius cap enforcement, rate limit enforcement, and the two-phase confirmation nonce protocol. Guard outcomes (denied, allowed, capped, rate-limited) feed directly into audit records.

5. **Audit trail with before/after snapshots before identity/gate** — the audit trail's shape must be defined before gate integration, so the identity system knows what it must produce for the trail. Admin-tools audit records are richer than introspection's: they include before/after state snapshots for every executed mutation.

6. **Identity and MANDATORY gate integration** — unlike introspection v1 which stubbed the capability gate, admin-tools requires the gate at runtime. Mutations are too dangerous for stub-gated access. If the gate is unavailable, all actions fail closed. No exceptions.

7. **MCP surface after full stack** — when tools are exposed to agents, they sit on top of a complete pipeline: identity → gate → guard → executor → audit → response.

8. **Adversarial testing for mutations** — prove dry-run doesn't mutate, confirmation can't be bypassed, blast radius caps hold, rate limits enforce, nonce replay fails, gate denial works. Every safety claim is tested, not assumed.

9. **Operator packaging** — deployment guide, configuration reference, operator workflow guide. A Rails platform engineer who has never seen this codebase should be able to deploy, configure, and use the server.

10. **Expansion readiness** — document v2 tools (console proxying, user management), architecture extension points, and the confirmed out-of-scope list. The v1 story is closed and the future story is written.

---

## 4. The 10 Epics

---

### Epic 1 — Lay the Repo Foundation So All Future Work Has a Clean Home

**Epic mission:**
Establish the development-ready structure for this repo: directory layout, finalized CLAUDE.md with repo-specific operating rules, README, and any planning scaffolding needed before implementation begins. When this epic is done, a Claude Code session can open the repo and know exactly what it is, where things go, and what rules apply. The session should be able to read CLAUDE.md and immediately understand: this is a mutation server for Rails admin operations, it has seven non-negotiable safety rules, and the work must follow the epic plan.

**Why this epic comes first:**
Nothing else works well without it. If the CLAUDE.md doesn't reflect the repo's actual conventions, future sessions will make wrong assumptions. If the directory structure isn't established, docs and code end up in random places. The cost of doing this first is low. The cost of not doing it is paid repeatedly.

**Scope of this epic:**
- Finalize the production-grade `CLAUDE.md` for this repo with specific conventions: language/runtime, directory layout, testing approach, safety rules, what not to touch
- Finalize the `README.md` with a clear one-paragraph mission, status indicator, and pointer to canonical docs
- Establish the top-level directory structure: `lib/`, `spec/`, `config/`, `000-docs/`, `planning/`
- Update `planning/epics.md` to point to this canonical plan (it is currently a stub)
- Confirm all existing planning docs are correctly indexed in `000-docs/`

**Out of scope for now:**
Any application code. Any gem/dependency management. Any CI/CD configuration.

**Likely child-task themes:**
- Finalize the repo-specific CLAUDE.md (language choices, test framework, file layout, safety rules for mutations)
- Update the README to reflect the current planning state
- Create top-level directory structure (`lib/wild_admin_tools_mcp/executor/`, `guard/`, `confirmation/`, `audit/`, `identity/`, `server/`)
- Update `planning/epics.md` to reference this doc
- Verify `000-docs/` index is current and all existing docs (003, 005, 006) are correctly filed

**Dependency notes:**
Depends on nothing. Everything else depends on this. Do not start any other epic until Epic 1 is closed.

**Supporting docs to create/reference:**
- `001-PP-PLAN-repo-blueprint.md` is the governing reference — CLAUDE.md must be consistent with it

**Narrative annotation:**
This is the scaffolding pass before the interesting work begins. It takes one focused session. The reward is that every subsequent session can start from a known-good state instead of guessing. For admin-tools, this also means confirming that the directory layout accounts for mutation-specific components (executor, confirmation protocol) that don't exist in the introspection repo.

---

### Epic 2 — Write the Safety Rules for Mutation Operations

**Epic mission:**
Produce and validate the canonical safety model, mutation policy, threat model, and architecture decisions documents for this repo. These are the durable, explicit specifications of what the server will and will not do from a safety and trust perspective. Every implementation decision must be evaluable against these documents. Because this is a mutation server — not a read-only one — the stakes are higher and the rules are stricter than introspection's. A misconfigured introspection query leaks data; a misconfigured admin action changes production state.

**Why this epic comes second:**
The repo's entire value proposition is that it performs mutations safely. If the safety rules exist only in prose and intentions, they will drift during implementation. Making the safety model a standalone, reviewable, enforceable document creates accountability. Engineers (or future Claude Code sessions) who encounter a tricky decision can check the safety doc rather than guessing.

Note: docs 003 (`safety-model.md`), 005 (`threat-model.md`), and 006 (`safety-architecture-decisions.md`) are already drafted as part of Phase 0 planning. This epic validates, refines, and finalizes them. It also produces `004-TQ-STND-mutation-policy.md` if not yet written — the action allowlist format, blast radius caps, rate limit definitions, and confirmation protocol specification.

**Scope of this epic:**
- Validate `003-TQ-STND-safety-model.md`: the detailed safety specification covering mutation-bounded operations, two-phase confirmation, blast radius caps, rate limiting, dry-run enforcement, before/after state capture, mandatory capability gate, audit trail, parameter sanitization, and conservative defaults
- Write or validate `004-TQ-STND-mutation-policy.md`: how the action allowlist is defined, what format policy files use, how blast radius caps are expressed, how rate limits are configured, how the confirmation protocol works in practice with concrete examples
- Validate `005-AT-ADEC-threat-model.md`: the anticipated attack surfaces specific to a mutation server (confirmation bypass, blast radius exceed, rate limit circumvention, nonce replay, gate bypass, parameter injection, privilege escalation, dry-run escape, audit tampering, denial of service)
- Validate `006-AT-ADEC-safety-architecture-decisions.md`: the major architecture decisions that mutation safety implies
- Capture and decide any remaining architecture decisions: What is the confirmation nonce lifecycle? What happens when the gate is unreachable? What does a rate-limited denial look like?

**Out of scope for now:**
Implementation of any of these rules. The policies are written but no code enforces them yet.

**Likely child-task themes:**
- Review and finalize the safety model document (003) — confirm all 10 rules are complete, enforceable, and testable
- Write or finalize the mutation policy document (004) — action allowlist YAML format, blast radius cap syntax, rate limit window/count syntax, confirmation protocol flow
- Review and finalize the threat model document (005) — confirm all threats have mitigations and verification requirements
- Review and finalize the architecture decisions document (006) — confirm all decisions are recorded with rationale
- Cross-reference all four docs for consistency — a rule in 003 should appear as a threat mitigation in 005 and an architecture decision in 006

**Dependency notes:**
Depends on Epic 1 (clean repo structure and CLAUDE.md to know where docs go and what standards apply). All implementation epics (3-9) depend on this epic being closed — they implement what this epic specifies.

**Supporting docs to create/reference:**
- `003-TQ-STND-safety-model.md` — validate and finalize
- `004-TQ-STND-mutation-policy.md` — write or finalize
- `005-AT-ADEC-threat-model.md` — validate and finalize
- `006-AT-ADEC-safety-architecture-decisions.md` — validate and finalize

**Narrative annotation:**
This epic is the most important planning work in the repo. It is not glamorous. It does not produce running code. But a system whose safety rules are written down and signed off is a fundamentally different thing from a system whose safety is assumed to be somewhere in the code. For a mutation server, this is doubly true. The introspection repo's worst case is data leakage. This repo's worst case is unintended production state changes. The safety documents must be proportionally stronger. Do not skip or rush this epic.

---

### Epic 3 — Build the Action Executor: Job, Cache, and Flag Operations with Dry-Run and State Capture

**Epic mission:**
Implement the action executor layer — the core that actually performs operations against the Rails application. Three action categories: background jobs (inspect, retry, discard), cache (inspect, invalidate), and feature flags (read, toggle). Every action has two paths: preview (dry-run) and execute. State capture (before/after snapshots) is built into the executor from the start, not bolted on later. The executor is the raw capability layer. It is inherently dangerous — it performs mutations — and it is intentionally built without safety controls, because the mutation guard (Epic 4) wraps it with those controls.

**Why this epic comes third:**
The mutation guard (Epic 4) needs something to wrap. The audit trail (Epic 5) needs before/after snapshots to record. The MCP tools (Epic 7) need something to invoke. The executor is the foundational action layer. Everything above it depends on it. But the executor itself has no dependencies on the layers above it, so it is the right thing to build first in the implementation stack. The key difference from introspection's adapter: this executor performs mutations, so dry-run and state capture are built in from day one, not added as an afterthought.

**Scope of this epic:**
- Job executor: inspect job state (queue, status, args, error), retry a failed job, discard a stuck job — with adapter interfaces for Sidekiq and GoodJob
- Cache executor: inspect cache key/value/TTL, invalidate a specific cache key or pattern — with adapter interface for Rails cache stores
- Flag executor: read flag state (enabled, percentage, actors), toggle a flag on/off — with adapter interface for Flipper
- Dry-run path for every action: preview mode returns what would happen without executing — the exact operation, parameters, and affected scope
- Before/after state capture: every execute path captures the relevant state before the action and after the action completes, returning both as structured data
- Adapter interfaces: clean interfaces that isolate the executor from specific gems (Sidekiq, GoodJob, Flipper) so new adapters can be added without changing the executor's public API

**Out of scope for now:**
Mutation guard wrapping (that's Epic 4). Audit logging (that's Epic 5). Auth and gate (that's Epic 6). Batch operations. Multi-target actions. Console proxying. User management.

**Likely child-task themes:**
- Implement job executor: inspect operation (read job metadata)
- Implement job executor: retry operation (re-enqueue a failed job, capture before/after state)
- Implement job executor: discard operation (remove a stuck job, capture before/after state)
- Implement cache executor: inspect operation (read key metadata, value, TTL)
- Implement cache executor: invalidate operation (delete a key or pattern, capture before/after state)
- Implement flag executor: read operation (read flag state including percentage and actors)
- Implement flag executor: toggle operation (enable/disable a flag, capture before/after state)
- Implement dry-run path for each operation (returns preview without side effects)
- Implement before/after state capture as a first-class executor concern
- Define adapter interfaces for Sidekiq, GoodJob, Flipper, Rails cache stores
- Write unit tests for each operation against a real test Rails app

**Dependency notes:**
Depends on Epics 1 (repo structure) and 2 (safety model and mutation policy docs, so the executor knows what operations are in scope and what "dry-run" means contractually). The mutation guard (Epic 4), audit trail (Epic 5), and all later epics depend on this.

**Supporting docs to create/reference:**
- `003-TQ-STND-safety-model.md` (from Epic 2) governs dry-run and state capture requirements
- `004-TQ-STND-mutation-policy.md` (from Epic 2) defines which operations exist and their parameter schemas
- Consider starting `007-AT-ARCH-architecture-overview.md` during this epic to capture component diagrams as they emerge

**Narrative annotation:**
The executor is deliberately bounded. It has three action categories, each with a small set of named operations. It is not a generic command executor. It does not accept arbitrary method names or class references. The bounded nature of the executor is the first layer of safety — even before the guard wraps it, the executor can only do things from a fixed menu. But the executor alone is not safe. It will execute anything on its menu without checking whether the caller should be allowed to. That's the guard's job.

---

### Epic 4 — Build the Mutation Guard: Allowlist, Validation, Blast Radius, Rate Limits, and Confirmation Protocol

**Epic mission:**
Implement the mutation guard — the layer that wraps every executor call with access policy enforcement before it runs. No action reaches the executor without passing through the guard. The guard enforces the action allowlist, validates parameters against per-action schemas, enforces blast radius caps, tracks and enforces rate limits, and manages the two-phase confirmation nonce protocol. When this epic is done, the system has a working, testable mutation control layer.

**Why this epic comes fourth:**
The executor (Epic 3) provides raw action capabilities. Without the guard, those capabilities are uncontrolled: any action could execute, any parameters could pass through, there's no blast radius cap, no rate limit, and no confirmation step. The guard is what makes the executor safe to use. But the guard cannot be built until the executor exists, because the guard wraps the executor's interface.

**Scope of this epic:**
- Allowlist check: given an action name, verify it is in the configured action allowlist; return a clear denial if not
- Parameter validation: given an action name and parameters, validate the parameters against the per-action schema defined in the mutation policy; reject malformed or extra parameters
- Blast radius cap enforcement: enforce per-action blast radius limits (e.g., max jobs retried per invocation, max cache keys invalidated per pattern); refuse operations that would exceed the cap
- Rate limit enforcement: track action invocations per caller in a sliding time window; refuse operations when the rate limit is exceeded; return clear denial with retry-after timing
- Confirmation nonce protocol: implement the two-phase confirmation flow — (1) dry-run preview returns a server-generated nonce with TTL, (2) caller returns the nonce to confirm execution, (3) nonce is validated and consumed (single-use), (4) expired or replayed nonces are rejected
- Guard outcome recording: the guard produces structured outcome records (allowed, denied-allowlist, denied-validation, denied-blast-radius, denied-rate-limit, denied-nonce) that feed directly into the audit trail

**Out of scope for now:**
Audit logging (that's Epic 5). Identity-based policy variations (that's Epic 6). Dynamic policy updates at runtime. Per-caller blast radius caps (v2).

**Likely child-task themes:**
- Implement action allowlist loading from configuration and validation at startup
- Implement parameter schema validation per action
- Implement blast radius cap enforcement with configurable per-action limits
- Implement rate limit tracking with sliding window (in-memory for v1, with interface for external store)
- Implement nonce generation (cryptographically random, with configurable TTL)
- Implement nonce validation and consumption (single-use, reject expired, reject replayed)
- Implement the full confirmation flow: dry-run → nonce → confirmed execute
- Implement structured guard outcome records for all denial types
- Write tests: allowed action passes, unknown action denies, malformed params deny, blast radius cap triggers, rate limit triggers, valid nonce passes, expired nonce denies, replayed nonce denies

**Dependency notes:**
Depends on Epic 3 (the executor to wrap) and Epic 2 (the safety model and mutation policy docs that define what the guard must enforce). The audit trail (Epic 5) depends on this being in place so it can record guard outcomes.

**Supporting docs to create/reference:**
- `004-TQ-STND-mutation-policy.md` (from Epic 2) is the governing spec for policy format, blast radius caps, and rate limits
- `003-TQ-STND-safety-model.md` (from Epic 2) defines the confirmation protocol contract
- Update `007-AT-ARCH-architecture-overview.md` with the guard's position in the stack

**Narrative annotation:**
The mutation guard is where the safety model becomes real code. The safety doc says "actions are allowlisted" — the guard is what actually checks the allowlist. The safety doc says "blast radius caps are enforced" — the guard is what enforces them. The safety doc says "two-phase confirmation is mandatory" — the guard is what generates the nonce and validates the return. The relationship between the safety model doc and this epic is direct and testable: every rule in the safety doc should have a test in this epic that proves the rule is implemented. This is the most safety-critical code in the repo.

---

### Epic 5 — Build the Audit Trail: Before/After Snapshots and Mutation Logging

**Epic mission:**
Implement the audit trail with mutation-specific enhancements — the append-only structured log of every action invocation, regardless of outcome. Successes, denials, rate-limited refusals, nonce failures, and errors all produce audit records. Unlike introspection's audit trail which records what was read, admin-tools audit records include before/after state snapshots for every executed mutation. The audit trail is what makes this server trustworthy: operators can see what was changed, what the state was before the change, what the state was after, and who authorized the action.

**Why this epic comes fifth:**
The audit trail needs to capture outcomes from the mutation guard (denied, allowed, blast-radius-capped, rate-limited, nonce-rejected), which means it wraps the guard. The audit trail also uses the before/after state snapshots produced by the executor (Epic 3). The full identity system comes in Epic 6, but the audit record schema is designed now to accept an identity field. The identity system in Epic 6 will make this richer.

**Scope of this epic:**
- Audit record schema: define the structure of a mutation audit record — timestamp, caller identity (placeholder until Epic 6), action name, action category (job/cache/flag), parameters (sanitized), guard outcome, before-state snapshot, after-state snapshot, result summary, duration, nonce used (if applicable)
- Before/after snapshot recording: capture the state snapshot from the executor and attach it to the audit record; the "before" snapshot is captured during dry-run/confirmation, the "after" snapshot is captured post-execution
- Append-only storage: audit records are written and never modified; define the storage backend (file, DB table, or structured log — decide and document)
- Parameter sanitization: before recording parameters, strip any values that should not appear in logs (e.g., cache values are summarized not logged in full, job args may contain PII)
- Outcome capture: capture whether the call succeeded, was denied by the guard (and which specific rule triggered the denial), was rate-limited, had a nonce failure, or errored
- Guard outcome integration: audit records for denied operations include the specific denial reason from the guard
- Audit record access: a minimal inspection capability to read recent audit records for review

**Out of scope for now:**
The full identity system (that's Epic 6). A UI for audit log review. Analytics on audit data. Export to external SIEM or log aggregation. Telemetry integration. Audit record retention policies.

**Likely child-task themes:**
- Design and implement the mutation audit record schema (extended from introspection with before/after fields, nonce, action category)
- Implement before/after state snapshot attachment to audit records
- Choose and implement the storage backend (log this choice in an ADR)
- Implement parameter sanitization for mutation parameters
- Implement outcome capture from guard results (all denial types, success, error)
- Wire the audit trail into the full call pipeline (executor → guard → audit → response)
- Write tests: every call type produces an audit record; denied calls produce correct denial records; before/after snapshots are present for executed mutations; no call bypasses auditing; sanitized fields do not leak raw values

**Dependency notes:**
Depends on Epics 3 (executor, for before/after snapshots) and 4 (guard, for outcome records). Epic 6 (identity and gate) will enrich the audit records with real caller identity. Epic 7 (MCP server) relies on the audit trail being in place before any tools are exposed.

**Supporting docs to create/reference:**
- Create `008-AT-ADEC-audit-trail-storage-decision.md` to record the storage backend choice and rationale
- `003-TQ-STND-safety-model.md` specifies what audit logging must capture for mutations

**Narrative annotation:**
The audit trail is not a nice-to-have that gets added later. It ships with the first tools. A server that performs mutations without an audit trail is just an ungoverned admin console. The audit trail — with before/after state snapshots — is what transforms this from "a tool that changes things" into "a governed administrative service with a complete change log." There is no v1 without it. The before/after snapshots are the proof that the system does what it says it does. An operator who sees "toggled feature flag X" in the audit log can also see "before: disabled, after: enabled" and know exactly what happened.

---

### Epic 6 — Establish Identity and Capability Gate Integration

**Epic mission:**
Implement identity extraction and MANDATORY capability gate integration. Unlike introspection v1 which stubbed the gate, admin-tools requires the gate at runtime. Mutations are too dangerous for stub-gated access. If the gate is unavailable, all actions fail closed — no fallback, no degraded mode, no override flag. Every action is gate-authorized, every denial is audited, and no anonymous access is permitted under any circumstances.

**Why this epic comes sixth:**
The audit trail (Epic 5) needs an identity to record. The MCP server (Epic 7) needs an auth layer to enforce before routing requests to tools. Identity is the binding layer between the call and the audit record. For admin-tools, the gate is not optional — it is load-bearing. A mutation server without mandatory gate authorization is a liability, not a tool.

**Scope of this epic:**
- Caller identity extraction: given an inbound request (MCP session context), extract the caller's identity — token, service account, or configured credential
- Anonymous rejection: requests without a resolvable identity are rejected before reaching the executor or guard; the rejection is logged
- Identity propagation: the resolved identity flows through the entire call pipeline — it is present when the guard runs, when the audit record is written, and when gate authorization is checked
- Session context: design the session context object that carries identity, capability level, gate authorization result, and request metadata through the call pipeline
- MANDATORY capability gate integration: integrate with `wild-capability-gate` for real authorization. This is not a stub. The gate must be reachable and must authorize the specific action for the specific caller. If the gate is unreachable, the action is denied.
- Fail-closed behavior: if the gate returns an error, times out, or is unreachable, the outcome is denial — not a retry, not a fallback, not a pass-through
- Gate health check: expose a health check that verifies gate connectivity; if the gate is down, the server should report itself as unhealthy
- Auth configuration: how callers are configured (API key, token, service account) is documented and the configuration format is defined

**Out of scope for now:**
Multi-tenant identity management. OAuth flows. Role-based access control beyond capability levels. Per-caller policy customization.

**Likely child-task themes:**
- Design and implement the session context object (identity, capability level, gate result, metadata)
- Implement caller identity extraction and validation
- Implement anonymous request rejection with audit logging
- Implement capability gate client — real integration with `wild-capability-gate` authorization interface
- Implement fail-closed behavior for gate errors, timeouts, and unreachable states
- Implement gate health check endpoint
- Wire identity into the audit trail (Epic 5 audit records now get real identity values)
- Wire gate authorization into the guard pipeline (gate check before guard check)
- Write tests: authenticated call with gate approval succeeds; anonymous call is rejected; gate-denied call is rejected and audited; gate-unreachable call is denied; identity appears correctly in audit record; health check reflects gate status

**Dependency notes:**
Depends on Epics 3, 4, 5 (the full executor → guard → audit stack). Epic 7 (MCP server) depends on this — no client surface ships without auth and gate. Cross-repo dependency: `wild-capability-gate` must expose its authorization interface for this integration.

**Supporting docs to create/reference:**
- `009-AT-ADEC-identity-and-auth-model.md` — document the auth model: what identities look like, how they are validated, what happens on rejection
- `010-AT-ADEC-capability-gate-integration.md` — document the real (not stub) gate integration: endpoint contract, request/response format, timeout behavior, fail-closed implementation

**Narrative annotation:**
This is the epic that draws the sharpest line between admin-tools and introspection. Introspection v1 could ship with a stubbed gate because the worst case was a data read. Admin-tools cannot. The mandatory gate integration is the architectural decision that makes this server trustworthy for mutation operations. After this epic closes, every call to the server has an identity attached to it, every action is gate-authorized, every denial has a caller attributed to it, and the audit trail is complete. The server is now ready for its public face.

---

### Epic 7 — Build the MCP Server and v1 Tool Surface

**Epic mission:**
Build the MCP server — the client-facing layer that implements the MCP protocol, registers the curated v1 tool set, routes incoming requests through the full pipeline (identity → gate → guard → executor → audit), and returns structured responses. When this epic closes, an AI agent can connect to the server and execute governed admin operations against a real Rails application. This is the first moment the repo is demonstrably useful. The v1 tool set is exactly three tools: `manage_background_jobs`, `manage_cache`, `manage_feature_flags`. Each tool supports the full two-phase confirmation flow.

**Why this epic comes seventh:**
The MCP server is the top of the stack. It can only be built after everything below it — the executor (3), the guard (4), the audit trail (5), and the identity/gate layer (6) — are all in place. Building the server earlier would mean building a surface that's not yet safe to expose. Building it now means the first time an agent can reach the server, it already has the full safety stack underneath it. For a mutation server, this is non-negotiable.

**Scope of this epic:**
- MCP protocol implementation: implement the MCP server using the appropriate SDK or library; handle session lifecycle, tool discovery, and request routing
- Tool registry: an explicit, curated list of v1 tools, each with a name, description, parameter schema, and safety classification
- v1 tool set (exactly these, nothing more):
  - `manage_background_jobs`: inspect, retry, or discard background jobs — with dry-run preview, confirmation, and before/after state snapshots
  - `manage_cache`: inspect or invalidate cache entries — with dry-run preview, confirmation, and before/after state snapshots
  - `manage_feature_flags`: read or toggle feature flags — with dry-run preview, confirmation, and before/after state snapshots
- Request pipeline: inbound tool calls are routed through identity check → gate authorization → guard (allowlist, validation, blast radius, rate limit, confirmation) → executor → audit → response
- Response format: consistent, structured response format for all outcomes:
  - Dry-run preview (what would happen, with nonce for confirmation)
  - Confirmation required (nonce pending, action not yet executed)
  - Success with snapshot (action executed, before/after state included)
  - Denied (specific reason: not allowlisted, parameter invalid, blast radius exceeded, rate limited, gate denied, nonce expired/replayed)
  - Error (unexpected failure, sanitized details)
- Connection configuration: how agents configure a connection to this server (host, port, auth token, gate endpoint)

**Out of scope for now:**
Additional tools beyond the v1 set. Console proxying. User management operations. Dynamic tool generation. Plugin system. Multi-tenant routing. Streaming responses.

**Likely child-task themes:**
- Set up MCP server with protocol handling and session lifecycle
- Implement tool registry with the three v1 tools and their parameter schemas
- Wire the full request pipeline (identity → gate → guard → executor → audit → response)
- Implement the two-phase tool call flow: first call returns dry-run preview with nonce, second call with nonce executes
- Implement structured response format for all outcome types
- Write integration tests: an agent can connect, discover tools, call each tool in dry-run mode, receive a nonce, confirm with the nonce, receive success with before/after snapshot, and receive correct denial and error responses

**Dependency notes:**
Depends on all of Epics 1-6. This epic's output (a running server) is what Epic 8 (adversarial testing) will test. The full pipeline must be wired and working — there is no partial server.

**Supporting docs to create/reference:**
- `011-DR-REFF-tool-catalog.md` — write the canonical tool catalog: each tool's name, what it does, parameter schema, safety classification, supported operations, and confirmation protocol details
- Update `007-AT-ARCH-architecture-overview.md` with the complete system diagram now that all layers exist

**Narrative annotation:**
Epic 7 is the payoff of Epics 1-6. The work done in those epics has been invisible to any external observer. This epic is where the server becomes real. When it closes, an AI agent can ask to retry a failed Sidekiq job, receive a dry-run preview of what would happen, confirm the action with a nonce, and receive the result with before/after state — all policy-enforced, gate-authorized, and audit-logged. That's the product. Keep the v1 tool set narrow. Three tools, done correctly, are better than ten tools built on a wobbly foundation.

---

### Epic 8 — Prove the Safety Model: Adversarial Testing for Mutations

**Epic mission:**
Before calling anything "ready," prove that the safety model actually works as specified. This is not routine testing — it is adversarial validation targeted specifically at mutation safety. The goal is to actively try to break the safety claims: try to bypass dry-run to trigger mutations, try to skip confirmation, try to exceed blast radius caps, try to circumvent rate limits, try to replay nonces, try to bypass the gate, try to inject parameters. If any safety claim fails a test, that is a defect, not a surprising edge case.

**Why this epic comes eighth:**
The server is built. The safety model is documented. Before any real operator tries to run this against production Rails, the safety claims need to be proven. For a mutation server, this is higher stakes than introspection — a failed safety test here means uncontrolled production changes. The evaluation strategy doc written here becomes the ongoing standard for proving new releases are still safe.

**Scope of this epic:**
- Dry-run side-effect tests: confirm that dry-run mode never triggers any mutation, state change, or side effect — test every executor path in preview mode and verify the system state is unchanged
- Confirmation bypass tests: confirm that no code path allows an action to execute without a valid confirmation nonce — test direct execution attempts, missing nonce, empty nonce, malformed nonce
- Blast radius overflow tests: confirm that crafted requests cannot exceed blast radius caps — test operations that target more items than the cap allows, verify the cap is enforced and the excess items are untouched
- Rate limit circumvention tests: confirm that rate limits cannot be bypassed through parameter variation, rapid succession, or multiple sessions — test exact-limit and over-limit scenarios
- Nonce replay tests: confirm that a consumed nonce cannot be reused — test immediate replay, delayed replay, and nonce from a different action
- Gate bypass tests: confirm that all actions fail when the gate is unreachable, returns denial, or returns an error — test gate timeout, gate 500, gate explicit deny, gate response tampering
- Parameter injection tests: confirm that tool parameters are treated as data, not code — test parameters containing Ruby expressions, SQL fragments, shell commands, and class names
- Anonymous access tests: confirm that all unauthenticated calls are rejected and logged
- Policy violation logging tests: confirm that every safety violation produces the correct audit record with the correct denial reason
- Evaluation strategy document: produce the document that describes how to run these checks against new releases or new Rails apps

**Out of scope for now:**
Performance benchmarking. Load testing. Penetration testing by external parties. SIEM integration.

**Likely child-task themes:**
- Write the adversarial test suite (one test per safety claim, organized by threat category)
- Test dry-run isolation: every executor operation in preview mode, verify zero state changes
- Test confirmation enforcement: direct execute without nonce, with invalid nonce, with expired nonce
- Test blast radius caps: operations targeting more items than cap allows
- Test rate limit enforcement: exact-limit passes, one-over-limit denies, rapid burst denied
- Test nonce replay prevention: immediate replay, cross-action replay, expired replay
- Test gate failure modes: unreachable, timeout, explicit deny, error response
- Test parameter injection: Ruby eval attempts, SQL injection, shell injection, constantize attempts
- Test anonymous access rejection across all tools
- Write and file `012-TQ-SECU-evaluation-strategy.md`

**Dependency notes:**
Depends on Epic 7 (the full server). All safety claims are tested against the complete, integrated system, not individual components. Epic 9 (MVP packaging) cannot close until this epic confirms no safety defects are outstanding.

**Supporting docs to create/reference:**
- `012-TQ-SECU-evaluation-strategy.md` — the evaluation protocol: what is tested, how to run the tests, what a passing result looks like, what constitutes a safety defect

**Narrative annotation:**
This is the checkpoint that determines whether the server is actually safe or just claims to be safe. For a mutation server, this epic is existential. An introspection server that fails a safety test leaks data — bad, but recoverable. A mutation server that fails a safety test changes production state without authorization — potentially catastrophic. Every time a new version is released, a new Rails application is connected, or a new action is added, the evaluation strategy from this epic is the playbook for re-proving safety. Run the adversarial tests as aggressively as you can design them. A defect found here is a defect caught before it reaches production.

---

### Epic 9 — Package the MVP: Operator Docs and Validation

**Epic mission:**
Make the server usable by a real operator. The code may work, but without deployment instructions, an operator workflow guide, and an end-to-end validation path, the server is still a lab experiment. This epic produces the documentation and configuration story that transforms a working codebase into a deployable, operable product. When this epic closes, a Rails platform engineer who has never seen this codebase should be able to set up, configure, connect to, and use the server in a reasonable amount of time — including configuring the gate, the action allowlist, blast radius caps, and rate limits.

**Why this epic comes ninth:**
Shipping something useful requires more than working code. An operator who deploys the server incorrectly, connects to the wrong gate endpoint, misconfigures blast radius caps, or sets rate limits too high will not have a safe or useful experience. This epic makes the gap between "the code works" and "an operator can use it" as small as possible. For a mutation server, this gap is especially dangerous — a misconfigured mutation server is worse than no mutation server.

**Scope of this epic:**
- Operator deployment guide: how to add this server to a Rails application — dependencies, gate configuration, action allowlist setup, startup, connection testing
- Configuration reference: every configurable parameter (action allowlist, blast radius caps, rate limits, nonce TTL, gate endpoint, auth tokens, adapter selection) with its type, default, hard ceiling, and behavior when set incorrectly
- Operator workflow guide: the day-to-day operations story — how to add a new allowed action, how to adjust blast radius caps, how to change rate limits, how to inspect audit logs with before/after snapshots, how to revoke access
- End-to-end validation: a working demo or test fixture that connects a test Rails app to the server and exercises all three v1 tools through the full confirmation flow, producing verifiable output including before/after snapshots
- `README.md` update: the README should now reflect the current state of the server — it is a working v1, not a planning placeholder

**Out of scope for now:**
Multi-application deployment. Cloud deployment guides (e.g., Heroku, Fly, Railway). Managed hosting. Monitoring dashboards. Automated alerting.

**Likely child-task themes:**
- Write the operator deployment guide (dependencies, gate config, allowlist config, startup, connection test)
- Write the full configuration reference (every parameter, its type, default, hard ceiling, failure behavior)
- Write the operator workflow guide (add action, adjust caps, adjust rate limits, inspect audit, revoke access)
- Produce the end-to-end validation demo/fixture with full confirmation flow
- Update the README to reflect v1 status, tool list, and quick-start instructions

**Dependency notes:**
Depends on Epics 7 (the server exists) and 8 (the server is validated as safe). Cannot close until the operator docs are tested by actually following them — docs that only work in theory are not done.

**Supporting docs to create/reference:**
- `013-OD-OPNS-operator-deployment-guide.md`
- `014-DR-REFF-configuration-reference.md`
- `015-OD-GUID-operator-workflow-guide.md`

**Narrative annotation:**
The temptation at this stage is to cut corners on docs because the code is working and the interesting problems feel solved. Resist it. The operator docs are the final gate before real Rails engineers point this at production systems. An undocumented mutation server is an unsafe mutation server — not because the code is wrong, but because operators will misconfigure it when they can't find the answers they need. The configuration reference is especially critical: blast radius caps, rate limits, and nonce TTL settings are safety-load-bearing. An operator who sets the wrong values may not realize it until something bad happens.

---

### Epic 10 — Expansion Readiness: Console Proxying and Future Tools

**Epic mission:**
Document the controlled expansion roadmap: what the server is ready to support after v1, what architectural extension points exist, and what the clear boundary is between v1 and future versions. The headline v2 candidates are console proxying (the highest-risk feature in the ecosystem — governed, audited, sandboxed Rails console access) and user management operations. When this epic closes, the repo has a written commitment to where it can go without scope explosion, and anyone picking up the repo in the future knows which extensions are planned, which are possible, and which are permanently out of scope.

**Why this epic comes last:**
Expansion only makes sense after the foundation is proven. Documenting the expansion roadmap now — while the architecture is fresh and the trade-offs are understood — prevents future sessions from either expanding recklessly or refusing to evolve. Console proxying in particular requires its own safety analysis before any code is written, and that analysis is best done while the v1 safety model is still fresh in memory.

**Scope of this epic:**
- Console proxying safety requirements: document the safety model implications of governed console access — what sandboxing is required, what audit enhancements are needed, what gate escalation would be required, what the blast radius concept means for arbitrary console commands
- v2 tool candidates: specify which additional tools are in scope for a v2 (user management operations, audit log lifecycle management, deployment status inspection) and what safety review each requires
- Architecture extension points: document where the system is designed to accept new tools, new action categories, new adapter backends, or new identity providers without breaking the existing safety model
- Telemetry emission hooks: define the interface for emitting usage events to `wild-session-telemetry` when that repo is ready
- Explicit out-of-scope list: confirm what is permanently out of scope for this repo (arbitrary Ruby execution without sandbox, database migrations, schema changes, analytics queries, compliance dashboards) so future sessions don't relitigate these decisions
- Cross-repo dependency updates: document what admin-tools needs from other wild repos (capability gate improvements, telemetry interface) and what it provides to them (mutation audit format, tool catalog for registry)

**Out of scope for now:**
Actually implementing any of the v2 features. Building console proxying. Building user management. Building telemetry emission (until `wild-session-telemetry` ships its interface).

**Likely child-task themes:**
- Write console proxying safety requirements document (the highest-risk v2 analysis)
- Document v2 tool candidates with per-tool safety review requirements
- Document architecture extension points (new tools, new categories, new adapters, new identity providers)
- Document the telemetry emission hook interface
- Write and file the confirmed out-of-scope list
- Document cross-repo dependency updates and what admin-tools provides/needs

**Dependency notes:**
Depends on all prior epics. Informs the planning of `wild-capability-gate` (cross-repo dependency — gate may need escalation tiers for console proxying), `wild-session-telemetry` (future integration), and `wild-skillops-registry` (tool catalog export). Should be shared with the ecosystem-level planning context when complete.

**Supporting docs to create/reference:**
- `016-PP-PLAN-v2-expansion-roadmap.md` — controlled expansion roadmap including console proxying safety analysis
- `017-AT-ADEC-architecture-extension-points.md` — extension point documentation
- `018-AT-ADEC-telemetry-emission-hook-interface.md` — telemetry hook interface
- `019-PP-PLAN-confirmed-out-of-scope.md` — canonical out-of-scope list
- Update `001-PP-PLAN-repo-blueprint.md` if the v1 experience has surfaced any blueprint corrections

**Narrative annotation:**
The final epic is not about building — it is about preserving clarity. When this closes, the v1 story is done and the future story is written. Console proxying is called out specifically because it is the most dangerous feature in the wild ecosystem — arbitrary console access, even governed and sandboxed, requires a fundamentally different safety analysis than the bounded operations in v1. Documenting those requirements now, while the team has just finished building and proving the v1 safety model, ensures that the hardest safety thinking is done at the right time. A future session picking up this repo should be able to understand immediately: what is built, what is proven, what is next, and what will never be in scope. That is what makes a repo maintainable over time rather than just complete at a moment in time.

---

## 5. Cross-Epic Dependency Summary

The dependency flow through this repo has a primary chain with two notable cross-cutting dependencies:

```
Epic 1 (Foundation)
  └── Epic 2 (Safety Model Docs)
        ├── Epic 3 (Action Executor)
        │     └── Epic 4 (Mutation Guard)
        │           ├── Epic 5 (Audit Trail) ←── also depends on Epic 3 (state snapshots)
        │           │     └── Epic 6 (Identity & Gate) ←── also depends on Epics 3, 4
        │           │           └── Epic 7 (MCP Server) ←── depends on all of 1-6
        │           │                 └── Epic 8 (Adversarial Testing)
        │           │                       └── Epic 9 (MVP Packaging)
        │           │                             └── Epic 10 (Expansion Readiness)
        │           │
        │           └── (guard outcomes feed into audit — Epic 5)
        │
        └── (safety model governs all implementation epics 3-9)
```

The notable cross-cutting dependencies beyond the primary chain:

**Epic 3 → Epic 5 (state snapshots):** The audit trail captures before/after state snapshots that are produced by the executor. This means the executor's state capture interface must be designed with the audit trail's needs in mind, even though the audit trail is built two epics later.

**Epic 6 → cross-repo (capability gate):** Unlike introspection which stubbed the gate, admin-tools requires a real gate integration. This creates a cross-repo dependency on `wild-capability-gate` exposing a stable authorization interface. If the gate repo is not ready when Epic 6 begins, Epic 6 must coordinate with gate development or define the integration contract and validate against a test gate implementation.

**Epic 2 → Epics 3-9 (safety model governance):** Every implementation epic must be evaluable against the safety model documents from Epic 2. This is not a blocking dependency in the chain sense — it is a cross-cutting governance relationship. If an implementation decision contradicts the safety model, the implementation is wrong, not the safety model.

**Cross-repo dependency:** Epic 6's gate integration depends on `wild-capability-gate` shipping a stable public interface. Epic 10's console proxying analysis may require gate escalation tiers that don't yet exist in the gate repo.

---

## 6. Document-Backed Execution Notes

The following documents need to exist alongside the implementation work. They are not optional appendages — they are what makes the work trustworthy and maintainable.

| When | Document | Epic | Why it matters |
|------|----------|------|----------------|
| Before any code | Safety model (003) | Epic 2 | Governs every implementation decision — 10 enforceable rules for mutations |
| Before any code | Mutation policy (004) | Epic 2 | Defines the action allowlist format, blast radius caps, rate limits, confirmation protocol |
| Before any code | Threat model (005) | Epic 2 | Identifies the 10 mutation-specific threats the system must defend against |
| Before any code | Architecture decisions (006) | Epic 2 | Records the 7 safety-driven architecture decisions with rationale |
| During executor build | Architecture overview (007) | Epic 3+ | Captures component shape as it emerges — executor, guard, audit, gate, MCP |
| During guard build | Policy format examples | Epic 4 | Makes the mutation policy format real with working examples |
| During audit build | Audit storage ADR (008) | Epic 5 | Records the storage backend decision and why |
| During identity build | Auth model doc (009) | Epic 6 | Defines identity contract and gate integration requirements |
| During identity build | Gate integration doc (010) | Epic 6 | Defines the real (not stub) gate integration contract |
| With the MCP surface | Tool catalog (011) | Epic 7 | External reference for agents using the server — three tools, full schema |
| Before MVP | Evaluation strategy (012) | Epic 8 | The playbook for proving mutation safety on every release |
| With the MVP | Operator deployment guide (013) | Epic 9 | Required for any operator to deploy and connect |
| With the MVP | Configuration reference (014) | Epic 9 | Required for safe operator configuration — blast radius, rate limits, gate |
| With the MVP | Operator workflow guide (015) | Epic 9 | Required for ongoing operation — add actions, adjust limits, inspect audit |
| Closing v1 | v2 expansion roadmap (016) | Epic 10 | Defines what comes next — console proxying safety, v2 tools |
| Closing v1 | Architecture extension points (017) | Epic 10 | Where and how to add tools, categories, adapters |
| Closing v1 | Telemetry hook interface (018) | Epic 10 | Interface for wild-session-telemetry integration |
| Closing v1 | Confirmed out-of-scope (019) | Epic 10 | Canonical list of what this repo will never do |

---

## 7. Readiness for Beads

This plan is complete. The next step is to convert it into Beads.

When Beads are created:

1. **Create one epic-level Beads entry per epic** — using the epic title and mission as the Beads description
2. **Create child tasks under each epic** — drawn from the "likely child-task themes" sections, written in natural human language that explains the purpose of each task
3. **Attach dependency blocks** — between tasks where the ordering matters, with prose rationale explaining why
4. **Write annotations** — operator-grade notes that give context, state assumptions, and set evidence expectations for task closure
5. **Do not collapse planning detail** — the richness of this plan should be preserved in the Beads, not summarized away
6. **Flag the cross-repo dependency** — Epic 6's gate integration requires coordination with `wild-capability-gate`. This should be surfaced as a blocked dependency until the gate's authorization interface is available.

The Beads creation prompt for this repo should reference this document as the governing planning source. Any task that contradicts this plan is wrong and should be corrected before execution begins.
