# Threat Model — wild-admin-tools-mcp

**Document type:** Architecture decision / security analysis
**Filed as:** `005-AT-ADEC-threat-model.md`
**Status:** Active
**Last updated:** 2026-03-18

---

## Purpose

This document identifies the anticipated attack surfaces for the admin tools MCP server and describes how the architecture mitigates each one. Unlike the introspection server, this server performs **mutations** — retries, cache invalidations, feature flag toggles, and other state-changing operations. Every threat listed here must have a corresponding adversarial test in Epic 8 that proves the mitigation works.

Mutations raise the stakes. A read-only server that fails safely leaks data; a mutation server that fails unsafely corrupts state, causes outages, or enables privilege escalation. The threats below are specific to this mutation surface.

---

## Threat 1: Unintended Mutation

### Attack

An attacker or buggy agent triggers a mutation they did not intend. Examples:

- The agent means to retry a single failed job but passes parameters that match `retry_all`, causing thousands of jobs to re-enqueue
- A typo in a job ID parameter causes a different job to be retried
- An ambiguous tool name or parameter set causes the server to execute a broader operation than the caller expected

### Impact if unmitigated

Mass unintended side effects — jobs retried that should not be, caches invalidated across an entire application, feature flags toggled for all users instead of a cohort. The system performs real work based on an incorrect instruction.

### Mitigation

- **Parameter validation** — every mutation tool enforces strict parameter schemas with explicit types, required fields, and no wildcard or glob-style matching. A `job_id` parameter accepts exactly one ID unless the tool is explicitly designed for batch operations
- **Blast radius caps** — batch mutations are capped at a configurable maximum (e.g., max 50 jobs per retry call). Requests exceeding the cap are rejected, not silently truncated
- **Two-phase confirmation** — every mutation requires a confirmation step. The first call returns a preview of what will happen (action, parameters, affected scope). The caller must then present a valid confirmation nonce to execute. No single call can both describe and perform a mutation
- **Dry-run preview** — the preview phase shows exactly what the mutation will affect, including counts and identifiers, so the caller can verify before confirming

### Verification

Epic 8 must include tests that submit ambiguous, overly broad, and mistyped parameters and confirm they are rejected or scoped correctly. Tests must confirm that no mutation executes without a valid confirmation nonce.

---

## Threat 2: State Corruption

### Attack

A mutation leaves the target system in an inconsistent state. Examples:

- A batch job retry partially completes — some jobs are re-enqueued, others fail, and the system has no record of which succeeded
- A cache invalidation occurs mid-request in the host application, causing the application to serve a mix of stale and fresh data within a single user interaction
- A feature flag toggle takes effect for some processes but not others due to caching or propagation delays

### Impact if unmitigated

The target system enters a state that is neither the old state nor the intended new state. Debugging is difficult because the corruption is partial and may not surface immediately.

### Mitigation

- **Before/after snapshots** — every mutation records the state before execution and the state after execution as structured data in the audit trail. If a mutation partially fails, the snapshot shows exactly what changed and what did not
- **Atomic operations where possible** — mutations are designed to use atomic primitives when the underlying system supports them (e.g., single Redis DEL for cache keys, single Sidekiq API call per job). When atomicity is not possible, the operation is documented as non-atomic and the blast radius cap limits exposure
- **Blast radius caps** — by limiting batch sizes, partial failures affect a bounded number of items. The before/after snapshot makes the partial state inspectable
- **No silent partial success** — if a batch mutation partially fails, the response explicitly reports which items succeeded and which failed, rather than returning a generic success

### Verification

Epic 8 must include tests that simulate partial failures (e.g., some jobs in a batch are not retryable) and confirm that before/after snapshots are accurate, that partial results are explicitly reported, and that no silent data loss occurs.

---

## Threat 3: Cascading Failures

### Attack

A mutation triggers downstream failures that amplify the impact beyond the mutation itself. Examples:

- A mass job retry re-enqueues thousands of jobs simultaneously, overwhelming worker pools and causing timeouts across unrelated queues
- A cache invalidation for a hot key causes a thundering herd — every concurrent request hits the database simultaneously to rebuild the cache
- A feature flag toggle enables a code path that has a latent bug, causing errors across the application

### Impact if unmitigated

The mutation itself may be "correct" in isolation, but the downstream effects cause an outage or degradation that is disproportionate to the intended change.

### Mitigation

- **Blast radius caps** — batch sizes are capped to prevent a single mutation from overwhelming downstream systems. The cap is set conservatively by default and can be tuned by operators who understand their system's capacity
- **Rate limiting** — mutations are rate-limited per caller and globally. Even if an agent makes rapid successive calls, the server enforces a maximum mutation rate
- **Dry-run preview showing estimated impact** — the confirmation preview includes the estimated scope (e.g., "this will retry 47 jobs in the `email` queue, which currently has 12 active workers"). The caller can assess whether the system can absorb the load before confirming
- **No implicit fan-out** — the server does not trigger cascading operations. A cache invalidation invalidates the specified keys; it does not preemptively rebuild them. A job retry enqueues jobs; it does not wait for them to complete

### Residual risk

The server cannot predict all downstream effects of a mutation in the host application. A feature flag toggle may enable code with latent bugs that the server has no visibility into. The mitigation is transparency: the audit trail records exactly what was changed, and the dry-run preview gives the caller information to make an informed decision.

### Verification

Epic 8 must include tests that submit mutations at the blast radius cap and confirm the server enforces the cap. Tests must confirm that rate limiting rejects excess requests. Tests should verify that dry-run previews include scope estimates.

---

## Threat 4: Privilege Escalation

### Attack

An attacker with limited gate permissions attempts to perform operations beyond their authorized scope. Examples:

- A caller authorized only for job inspection attempts to retry a job
- A caller authorized for cache reads attempts a cache invalidation
- A caller authorized for a specific queue attempts to operate on a different queue
- A caller chains multiple low-privilege operations to achieve a high-privilege outcome

### Impact if unmitigated

A caller executes mutations they are not authorized to perform, bypassing the intended permission model.

### Mitigation

- **Mandatory capability gate check per-action, not per-session** — every individual tool invocation checks the caller's permissions against the capability gate. A valid session does not imply authorization for all tools. Each mutation tool declares its required capability, and the gate is consulted on every call
- **No capability inference** — having permission for `job.inspect` does not imply permission for `job.retry`. Capabilities are explicitly enumerated, not hierarchical
- **Gate check before any work** — the capability check occurs before parameter validation, before preview generation, before any interaction with the target system. An unauthorized caller learns nothing about the system from a denied request
- **Uniform denial responses** — denied requests return the same response regardless of whether the capability exists, the caller lacks it, or the resource does not exist. No information leakage through error differentiation

### Verification

Epic 8 must include tests that attempt every mutation tool with insufficient permissions and confirm denial. Tests must confirm that capability checks happen per-invocation, not cached from a previous successful call. Tests must confirm that denial responses are uniform across different denial reasons.

---

## Threat 5: Parameter Injection

### Attack

Malicious parameter values escape their intended context and are interpreted as code or commands. Examples:

- A cache key containing shell metacharacters: `user:*; rm -rf /`
- A job ID containing SQL injection: `123 OR 1=1`
- A feature flag name containing Ruby method dispatch: `__send__(:system, 'whoami')`
- A queue name with newline injection that corrupts log entries

### Impact if unmitigated

Arbitrary code execution, data destruction, or log corruption through parameter values that are treated as executable rather than as inert data.

### Mitigation

- **Strict parameter typing** — every parameter has a declared type (string, integer, enum) with validation. Job IDs must be integers or match a strict format regex. Cache keys must match an allowlist pattern. Feature flag names must match `[a-zA-Z0-9_.-]+`
- **Allowlist-based resolution** — names (queues, flag names, cache key prefixes) are resolved by exact match against a configured allowlist, not by dynamic lookup. A value that is not on the allowlist is rejected before it reaches any system
- **No interpolation** — parameter values are never interpolated into strings that are evaluated as code, SQL, shell commands, or templates. Values are passed as data to API calls (e.g., `Sidekiq::Queue.new(validated_name)`, not `eval("Sidekiq::Queue.new('#{name}')")`)
- **No eval, send, or constantize** — no user-provided value is ever used with `eval`, `instance_eval`, `send`, `public_send`, `constantize`, `const_get`, or any reflective dispatch mechanism

### Verification

Epic 8 must include tests that pass shell metacharacters, SQL injection strings, Ruby method dispatch payloads, and newline injections as parameter values and confirm they are rejected or treated as inert data in every case.

---

## Threat 6: Audit Bypass

### Attack

A code path executes a mutation without recording the before/after state in the audit trail. Examples:

- An error during the mutation causes the code to exit before writing the audit record
- A new tool is added without wiring it through the audit middleware
- The confirmation nonce validation path records the confirmation but not the subsequent execution
- Before-state capture fails silently, so the audit record has an after-state but no before-state

### Impact if unmitigated

Loss of accountability and forensic capability. The system cannot prove what was changed, by whom, or what the previous state was. For a mutation server, this is catastrophic — unaudited mutations are invisible mutations.

### Mitigation

- **Audit middleware wraps all execution** — the audit layer is not called by individual tools; it wraps the entire tool invocation pipeline. Entry to the pipeline guarantees an audit record will be written, regardless of success, failure, or error
- **Before/after snapshots are mandatory** — the middleware captures the before-state before invoking the mutation and the after-state after it completes. If before-state capture fails, the mutation does not proceed
- **Error paths are audited** — exceptions, timeouts, and partial failures all produce audit records that include the error details and any partial state changes
- **Audit write is not deferrable** — the audit record is written synchronously as part of the mutation pipeline, not queued for later processing. If the audit write fails, the mutation result is still recorded as an error condition

### Verification

Epic 8 must include tests that exercise every code path — success, denial, error, timeout, partial failure, confirmation without execution, execution without confirmation attempt — and confirm each produces a complete audit record with all required fields including before/after snapshots.

---

## Threat 7: Replay Attacks

### Attack

An attacker captures a confirmed mutation action (including its confirmation nonce) and replays it to execute the mutation again. Examples:

- A network proxy logs the confirmation request and replays it to retry the same batch of jobs a second time
- A compromised agent stores confirmation nonces and resubmits them to repeat flag toggles
- An attacker replays a stale confirmation after the system state has changed, causing the mutation to execute in a context where it is no longer appropriate

### Impact if unmitigated

Mutations execute multiple times when they were intended to execute once. For idempotent operations this may be benign; for non-idempotent operations (job retries, flag toggles) this causes real damage — duplicate work, state oscillation, or resource exhaustion.

### Mitigation

- **Single-use nonces** — each confirmation nonce can be used exactly once. After successful execution, the nonce is consumed and cannot be reused. A replayed request with a consumed nonce is rejected
- **Nonce expiry** — nonces have a short time-to-live (configurable, default 30 seconds). A nonce that has expired cannot be used, even if it has never been consumed. This limits the replay window
- **Nonce bound to action+parameters+caller** — a nonce is cryptographically bound to the specific action, the exact parameters, and the caller identity. A nonce generated for `retry_job(id: 42)` by caller A cannot be used for `retry_job(id: 43)` or by caller B
- **Server-side nonce storage** — nonces are tracked server-side. The client cannot forge, extend, or reuse them

### Verification

Epic 8 must include tests that attempt to reuse a consumed nonce, use an expired nonce, use a nonce with different parameters than it was issued for, and use a nonce from a different caller — and confirm all are rejected.

---

## Threat 8: Confirmation Bypass

### Attack

An attacker skips the two-phase confirmation step and executes a mutation directly. Examples:

- An attacker calls the execution endpoint directly without obtaining a confirmation nonce first
- An attacker crafts a request that includes a fabricated nonce
- A bug in the client library omits the confirmation step, allowing direct execution
- An attacker discovers a tool endpoint that was not wired through the confirmation middleware

### Impact if unmitigated

Mutations execute without the caller seeing the preview or confirming the action. The two-phase safety model is bypassed entirely, removing the human-in-the-loop (or agent-in-the-loop) verification step.

### Mitigation

- **Server-side enforcement** — the confirmation requirement is enforced by the server, not by the client. The execution path requires a valid nonce as a mandatory parameter. There is no "skip confirmation" flag, no force mode, no override
- **Confirmed actions must present a valid nonce** — the nonce is validated against the server-side nonce store. Fabricated nonces do not match any stored entry and are rejected
- **No tool endpoint bypasses confirmation middleware** — every mutation tool is registered through the same pipeline that enforces confirmation. A new tool cannot be added without going through this pipeline
- **Preview and execute are separate operations** — there is no single API call that combines preview and execution. The protocol requires two distinct round-trips

### Verification

Epic 8 must include tests that attempt to execute without a nonce, with a fabricated nonce, with a nonce for a different action, and through any code path that might bypass the confirmation middleware. All must be rejected.

---

## Threat 9: Rate Limit Bypass

### Attack

An attacker circumvents rate limits to execute rapid-fire mutations. Examples:

- An attacker rotates caller identities to avoid per-caller rate limits
- An attacker exploits a race condition to submit multiple requests within the same rate limit window
- A compromised client library disables client-side rate limiting (if any exists)
- An attacker discovers that certain endpoints or error paths are not rate-limited

### Impact if unmitigated

An attacker can execute mutations at an unlimited rate, potentially exhausting system resources, overwhelming downstream services, or causing cascading failures that the rate limits were designed to prevent.

### Mitigation

- **Server-side rate enforcement** — rate limits are enforced by the server, never by the client. Client-side rate limiting is not relied upon for safety
- **Per-caller tracking** — rate limits are tracked per authenticated caller identity. Each caller has an independent budget
- **Global rate limit** — in addition to per-caller limits, a global rate limit caps the total mutation throughput across all callers (configured via `global_rate_limits` in `config/action_policy.yml`; see 004). This protects against distributed attacks using multiple valid identities
- **All paths rate-limited** — rate limiting applies to all tool invocations, including previews, confirmations, and error paths. There is no unmetered endpoint
- **No client-side rate limiting** — the server does not expose rate limit configuration to clients. The server enforces its own limits regardless of what the client claims or requests

### Residual risk

An attacker with access to many valid caller identities can achieve higher aggregate throughput by rotating between them. The global rate limit bounds this, but a sufficiently distributed attack may approach the global cap. Monitoring and anomaly detection on the audit trail can flag unusual multi-identity patterns.

### Verification

Epic 8 must include tests that submit mutations in rapid succession and confirm they are rejected after exceeding the rate limit. Tests must confirm that both per-caller and global limits are enforced. Tests should verify that previews and confirmations are also rate-limited.

---

## Threat 10: Rollback Abuse

### Attack

If rollback capabilities exist, an attacker uses them to revert legitimate changes or to mask malicious activity. Examples:

- An attacker toggles a feature flag, performs malicious actions while the flag is active, then rolls back the flag to hide evidence
- An attacker rolls back a legitimate cache invalidation, restoring stale data that benefits them
- An attacker uses rollback to oscillate system state rapidly, causing instability

### Impact if unmitigated

Rollback becomes an attack vector rather than a recovery tool. Legitimate changes are reverted without authorization, malicious changes are hidden by restoring previous state, and system stability is compromised by state oscillation.

### Mitigation

- **v1 does not include rollback** — before/after snapshots in the audit trail are informational only. They record what changed but do not provide a mechanism to reverse the change. No tool in the v1 surface area accepts a "rollback" or "undo" parameter
- **Snapshots are not executable** — the before-state snapshot is a data record, not a restore point. It cannot be "applied" through any API call
- **Rollback is a v2 concern** — if rollback is added in a future version, it will undergo its own safety review, threat modeling, and confirmation protocol. It will not be silently added to existing tools
- **Audit trail is immutable** — even if a mutation's effect is manually reversed by an operator, the original audit record persists. The audit trail cannot be "cleaned up" by rolling back

### Residual risk

Operators with direct system access (e.g., Rails console, Redis CLI) can manually reverse changes outside the MCP server. This is an infrastructure concern, not an application concern. The audit trail records what the MCP server did; out-of-band changes are outside its visibility.

### Verification

Epic 8 must include tests that confirm no tool accepts rollback-related parameters, that before/after snapshots are recorded as data only (not executable), and that the audit trail is append-only with no deletion or modification capability.

---

## Summary: Threat-to-Mitigation Map

| Threat | Primary mitigation | Secondary mitigation | Test coverage |
|--------|-------------------|---------------------|---------------|
| Unintended mutation | Two-phase confirmation, parameter validation | Blast radius caps, dry-run preview | Epic 8 |
| State corruption | Before/after snapshots, atomic operations | Blast radius caps, explicit partial failure reporting | Epic 8 |
| Cascading failures | Blast radius caps, rate limiting | Dry-run preview with scope estimates | Epic 8 |
| Privilege escalation | Per-action capability gate check | Uniform denial responses, no capability inference | Epic 8 |
| Parameter injection | Strict parameter typing, allowlist resolution | No interpolation, no eval/send/constantize | Epic 8 |
| Audit bypass | Mandatory audit middleware, synchronous writes | Before-state gate (no snapshot = no mutation) | Epic 8 |
| Replay attacks | Single-use nonces, nonce expiry | Nonce bound to action+parameters+caller | Epic 8 |
| Confirmation bypass | Server-side enforcement, mandatory nonce | No skip-confirmation flag, separate preview/execute | Epic 8 |
| Rate limit bypass | Server-side rate enforcement, global limit | Per-caller tracking, all paths rate-limited | Epic 8 |
| Rollback abuse | v1 excludes rollback, snapshots are informational | Immutable audit trail, v2 safety review required | Epic 8 |
