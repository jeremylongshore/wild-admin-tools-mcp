# Safety-Driven Architecture Decisions — wild-admin-tools-mcp

**Document type:** Architecture decision record
**Filed as:** `006-AT-ADEC-safety-architecture-decisions.md`
**Status:** Active
**Last updated:** 2026-03-18

---

## Purpose

The safety model implies specific architecture decisions. This document captures those decisions so they are explicit and reviewable rather than implicit in code. Because admin-tools-mcp is a mutation-capable server — unlike its read-only companion, wild-rails-safe-introspection-mcp — these decisions carry higher stakes and enforce stricter controls.

---

## Decision 1: Dry-Run as a First-Class Primitive

**Context:** Every action in admin-tools-mcp can mutate production state. Operators need a way to preview what an action will do before committing to it. Without a reliable preview mechanism, operators are forced to trust tool descriptions and hope for the best.

**Options considered:**
- Optional dry-run flag — caller passes `dry_run: true` to get a preview
- Dry-run as separate endpoint — a dedicated preview tool per action (e.g., `preview_retry_jobs` alongside `retry_jobs`)
- Dry-run as mandatory first phase — every action handler implements both preview and execute paths; the execute path requires a nonce from a prior preview

**Decision:** Dry-run is a mandatory first phase. Every action handler implements both preview and execute paths. No action can be executed without a preceding dry-run that produced a valid confirmation nonce.

**Dry-run response includes:**
- What will change (human-readable description of affected resources)
- Estimated count of affected resources
- Confirmation nonce (see Decision 2)
- Parameter echo (the exact parameters that will be used on execute)

**Rationale:** An optional dry-run flag means it gets skipped — especially under pressure, which is exactly when preview matters most. Separate endpoints double the tool surface without guaranteeing usage. Mandatory dry-run means preview is always available and always used. The nonce binding between preview and execute ensures the operator confirms what they actually previewed.

**Trade-off:** Two code paths per action (preview + execute), which increases implementation and testing surface. Both paths are independently testable, and the pattern is consistent across all actions, so the overhead is mechanical rather than cognitive.

---

## Decision 2: Confirmation Nonce Pattern

**Context:** Destructive actions need explicit confirmation. A simple "are you sure?" boolean is insufficient because it doesn't bind the confirmation to what was previewed. An operator could preview one set of parameters and confirm with a different set — accidentally or through a confused client.

**Options considered:**
- Simple boolean confirm flag — `confirm: true` on the execute call
- Server-generated nonce — server issues a one-time token during dry-run, client returns it to execute
- Client-provided idempotency key — client generates a key, server deduplicates

**Decision:** Server-generated, single-use, time-limited nonce tied to action + parameters + caller.

**Nonce properties:**
- **Format:** `wnc_` prefix + 32 hex characters (128 bits of entropy). The `wnc_` prefix stands for "wild nonce confirmation" and enables pattern matching in logs.
- **TTL:** Configurable per action, default 30 seconds, hard ceiling 120 seconds, hard floor 10 seconds
- **Storage:** In-memory hash with TTL-based expiry (no database dependency)
- **Binding:** Nonce is bound to `(action_name, parameter_hash, caller_id)` — if any component changes between preview and execute, the nonce is invalid
- **Single-use:** Consumed on first execute attempt, regardless of outcome
- **Validation on execute:** Server verifies nonce exists, has not expired, and the bound tuple matches the execute request exactly

**Rationale:** Nonces prevent replay attacks — a captured confirmation cannot be reused. Parameter binding prevents bait-and-switch — you cannot preview a safe action and then confirm a dangerous one. Caller binding prevents one operator from confirming another operator's preview. Time-limiting prevents stale confirmations from being used after the system state has changed.

**Trade-off:** Requires server-side state for pending confirmations. The in-memory store means pending confirmations are lost on server restart, which is acceptable — an operator simply re-runs the dry-run. The TTL hard ceiling of 120 seconds prevents indefinitely hanging confirmations while keeping the default (30s) tight enough to minimize the replay window.

---

## Decision 3: Before/After Audit Snapshots

**Context:** Every mutation needs accountability. When something goes wrong after an action, operators need to know exactly what changed — not just what was requested, but what the state was before and after.

**Options considered:**
- Log action only — record that the action was invoked
- Log parameters + outcome — record what was requested and whether it succeeded
- Full before/after state capture — snapshot affected resources before mutation, snapshot again after, store both in the audit record

**Decision:** Full before/after state capture for every executed action.

**Snapshot structure:**
- **Before:** State of affected resources captured immediately before mutation begins
- **After:** State of affected resources captured immediately after mutation completes
- **Both stored in the audit record** as structured data, not just log messages

**Audit record shape:**
```json
{
  "event": "action_executed",
  "action": "retry_failed_jobs",
  "caller_id": "operator-key-abc",
  "timestamp": "2026-03-18T14:30:00Z",
  "parameters": {
    "queue": "default",
    "max_count": 50
  },
  "nonce": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
  "before_snapshot": {
    "resource_type": "background_jobs",
    "count": 47,
    "sample": ["job_id_1: failed at 2026-03-18T12:00:00Z", "..."]
  },
  "after_snapshot": {
    "resource_type": "background_jobs",
    "count": 47,
    "sample": ["job_id_1: enqueued at 2026-03-18T14:30:01Z", "..."]
  },
  "result": "success",
  "affected_count": 47
}
```

**Rationale:** Parameters + outcome tells you what was attempted and whether it worked, but not what actually changed. Before/after snapshots answer the question "what did this action do to the system?" without requiring the operator to reconstruct state from logs. This is essential for incident response, rollback decisions, and trust.

**Trade-off:** More storage per audit record and slightly more latency for state capture (two extra queries per action — one before, one after). The storage cost is acceptable because the volume of admin actions is low relative to read operations. The latency cost is acceptable because admin actions are not latency-sensitive — operators are already in a deliberate, two-phase flow.

---

## Decision 4: Shared MCP Patterns with Introspection

**Context:** wild-admin-tools-mcp and wild-rails-safe-introspection-mcp are companion MCP servers in the same ecosystem. They will often be deployed alongside each other and used by the same AI agents. Consistency matters for operator experience and agent behavior.

**Options considered:**
- Fully independent implementations — each repo makes its own choices with no coordination
- Shared gem for common patterns — extract common code (audit format, response shapes, identity handling) into a shared Ruby gem
- Convention-based alignment — same MCP SDK, same response format conventions, same audit record shape, but no shared code dependency

**Decision:** Convention-based alignment. Both repos use the same MCP SDK, follow the same response format conventions, use the same audit record shape, and apply the same identity extraction patterns — but share no code dependency.

**Aligned conventions:**
- Response envelope format (status, data, metadata)
- Audit record structure (event, caller_id, timestamp, tool, parameters, result)
- Identity extraction from MCP request context
- Error response codes and categories
- Configuration file format (YAML, same key naming patterns)

**Rationale:** A shared gem creates coupling that slows both repos. When introspection needs to change its audit format, it shouldn't need to coordinate a gem release with admin-tools. Convention alignment lets them feel like one product to operators and agents without introducing code-level dependency. The conventions are documented, not enforced by code — which means each repo can pragmatically diverge when its domain requires it.

**Trade-off:** Some code duplication between repos. Conventions can drift if not actively maintained. The mitigation is documentation (this document and its introspection counterpart) and periodic review. The cost of duplication is lower than the cost of cross-repo coupling for two repos at this stage.

---

## Decision 5: Mandatory Capability Gate (Not Stubbed)

**Context:** wild-rails-safe-introspection-mcp v1 stubbed the capability gate — it defined the interface but used an always-allow stub in v1, with plans to integrate the real gate later. Admin-tools-mcp needs to make the same decision: stub or require.

**Options considered:**
- Stub like introspection did — define the interface, use an always-allow stub, integrate the real gate later
- Make gate mandatory — if the gate is unavailable, all actions fail closed (denied)
- Make gate optional with degraded mode — without the gate, allow a reduced set of safe actions

**Decision:** Gate is mandatory. If the gate is unavailable, all actions fail closed (denied). No stub mode. No bypass. No degraded mode.

**Behavior when gate is unavailable:**
```json
{
  "status": "denied",
  "reason": "gate_unavailable",
  "message": "Capability gate is not reachable. All actions are denied until gate connectivity is restored.",
  "tool": "requested_tool_name",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

**Rationale:** Admin-tools can mutate production state. The risk profile is categorically different from read-only introspection. Introspection's stub was acceptable because the worst case of an ungated read is information exposure — serious but recoverable. The worst case of an ungated mutation is data corruption, mass job retry storms, or cache invalidation cascades — potentially unrecoverable. The gate is the safety layer that prevents unauthorized writes. Stubbing it means running without the safety layer, which defeats the purpose of having one.

**Trade-off:** Admin-tools cannot operate without the capability gate running. This creates a hard runtime dependency on wild-capability-gate. If the gate goes down, admin-tools goes dark. This is the correct failure mode — it is better to lose admin tooling temporarily than to allow ungated mutations. Operators who need emergency access during a gate outage must use direct Rails console access with its own audit trail.

---

## Decision 6: Blast Radius Caps as Architecture

**Context:** Admin actions can affect many resources at once. "Retry all failed jobs" might mean 10 jobs or 10,000 jobs. "Invalidate cache by pattern" might match 5 keys or 50,000 keys. Without limits, a well-intentioned action can become a self-inflicted incident.

**Options considered:**
- No limits (operator responsibility) — trust the operator to scope their actions appropriately
- Advisory limits (warn but allow) — show a warning when the affected count is high, but allow the action to proceed
- Enforced caps (hard limits) — reject actions that would affect more resources than the configured ceiling

**Decision:** Enforced caps with configurable defaults and non-overridable hard ceilings.

**Cap structure per action category:**

| Category | Default cap | Hard ceiling | Unit |
|----------|------------|--------------|------|
| Job operations | 100 | 1,000 | jobs per invocation |
| Cache operations | 50 | 500 | keys per invocation |
| Feature flags | 1 | 10 | flags per invocation |

**Behavior when cap is exceeded:**
```json
{
  "status": "denied",
  "reason": "blast_radius_exceeded",
  "requested_count": 2500,
  "cap": 1000,
  "message": "Action would affect 2500 jobs, which exceeds the hard ceiling of 1000. Narrow your scope or execute in batches.",
  "tool": "retry_failed_jobs",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

**Rationale:** Advisory limits get ignored under pressure — the exact moment when limits matter most. "Are you sure you want to retry 15,000 jobs?" gets a "yes" from an operator at 3 AM during an incident. Hard ceilings prevent catastrophic mistakes by making them structurally impossible. The configurable default lets operators tune for their environment (a small app might set job cap to 20; a large one might set it to 500). The hard ceiling is non-overridable — it cannot be changed by configuration alone, only by a code change and release.

**Trade-off:** Operators who legitimately need to affect more resources than the hard ceiling must do it in batches. This is deliberate friction — batching is safer than bulk operations because each batch gets its own dry-run, confirmation, and audit record. The batching cost is operator time; the benefit is that no single invocation can cause outsized damage.

---

## Decision 7: Rate Limiting Strategy

**Context:** Even with blast radius caps, rapid-fire mutations can overwhelm target systems. An operator (or a misbehaving AI agent) could invoke "retry 100 jobs" ten times in rapid succession, effectively retrying 1,000 jobs without triggering the per-invocation cap. The target Rails application, job queue, or cache layer may not handle this burst gracefully.

**Options considered:**
- No rate limits — trust callers to self-throttle
- Client-side throttling — document recommended intervals, let clients enforce
- Server-side per-caller rate limits — the server tracks invocation rates and rejects excess requests

**Decision:** Server-side per-caller rate limits with a sliding window algorithm, plus a global rate ceiling across all callers.

**Rate limit properties:**
- **Tracked per:** `(caller_id, action_category)` tuple for per-caller limits
- **Global ceiling:** Separate global rate limits (`all_mutations: 120/minute`, `all_reads: 600/minute`) cap total throughput across all callers, defending against distributed attacks using multiple valid identities (see 005 Threat 9)
- **Algorithm:** Sliding window counter
- **Configurable per category** with hard ceiling maximums that cannot be exceeded by configuration

| Category | Default limit | Hard ceiling | Window |
|----------|--------------|--------------|--------|
| Job operations | 10 invocations | 30 invocations | 1 minute |
| Cache operations | 5 invocations | 15 invocations | 1 minute |
| Feature flags | 3 invocations | 10 invocations | 1 minute |

**Behavior when rate limit is exceeded:**
```json
{
  "status": "denied",
  "reason": "rate_limit_exceeded",
  "category": "job_operations",
  "limit": 10,
  "window_seconds": 60,
  "retry_after_seconds": 23,
  "message": "Rate limit exceeded for job operations. Try again in 23 seconds.",
  "tool": "retry_failed_jobs",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

**Rationale:** Client-side throttling is bypassable — whether intentionally or through buggy client code. Server-side enforcement is the only reliable approach. Per-caller tracking prevents one caller from consuming the rate budget of others. The sliding window algorithm provides smooth rate enforcement without the burst-at-boundary problem of fixed windows. Hard ceilings on rate configuration prevent an operator from setting limits so high that they are effectively meaningless.

**Trade-off:** Requires server-side state for rate tracking (in-memory counters per caller per category). Adds slight latency for the rate check on every request. The state is small (a few integers per active caller per category) and ephemeral (lost on restart, which is acceptable — rate limits reset). The latency is negligible relative to the cost of the admin action itself.

---

## Decision 8: Nonce Error Response Design — Granular Internal, Generic External

**Context:** When a confirmation nonce fails validation, the server knows the specific reason — not found, expired, already used, parameter mismatch, caller mismatch, action mismatch. The question is whether to expose this granularity to the client.

**Options considered:**
- Granular errors to client — return the specific failure reason (`nonce_expired`, `nonce_already_used`, etc.) so clients can present helpful error messages
- Generic error to client — return a single `nonce_invalid` code regardless of the underlying reason
- Split approach — granular in audit logs, generic in client responses

**Decision:** Split approach. The client always receives `nonce_invalid`. The audit trail and server logs record the specific error code (`nonce_not_found`, `nonce_expired`, `nonce_already_used`, `nonce_parameter_mismatch`, `nonce_identity_mismatch`, `nonce_action_mismatch`).

**Client response (always generic):**
```json
{
  "status": "error",
  "error_code": "nonce_invalid",
  "message": "Confirmation nonce is invalid, expired, or already used. Request a new confirmation."
}
```

**Audit record (specific):**
```json
{
  "outcome": "nonce_rejected",
  "denial_reason": "nonce_expired",
  "nonce_id": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
  "ttl_exceeded_by_seconds": 14
}
```

**Rationale:** Distinguishing between "not found," "expired," and "already used" in client responses enables probing attacks. An attacker can determine whether a nonce existed (found vs. not found), whether it was recently valid (expired vs. not found), and whether it has been consumed (already used vs. expired). The generic response eliminates this information channel. Meanwhile, server operators need the granular detail for incident investigation and replay detection — so the audit trail retains it.

**Trade-off:** Clients cannot provide specific guidance to users ("your nonce expired, please re-request" vs. "nonce was already used"). This is acceptable because the recovery path is identical in all cases: request a new confirmation. The slight UX cost is worth the security benefit.
