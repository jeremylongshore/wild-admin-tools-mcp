# Safety Model — wild-admin-tools-mcp

**Document type:** Safety standard
**Filed as:** `003-TQ-STND-safety-model.md`
**Status:** Active — governing spec for all implementation
**Last updated:** 2026-03-18

---

## Purpose

This document is the canonical safety specification for `wild-admin-tools-mcp`. Every implementation decision in this repo must be evaluated against the rules defined here. If the code contradicts this document, the code is wrong.

This is not aspirational guidance. These are enforceable constraints.

Unlike `wild-rails-safe-introspection-mcp`, which is strictly read-only, this repo intentionally performs mutations — retrying jobs, invalidating caches, toggling feature flags. Because mutations carry real consequences, every safety rule here is designed to bound, confirm, audit, and gate those mutations. The safety model assumes that any unguarded mutation path will eventually be triggered by accident or abuse.

---

## 1. Mutation-Bounded Operations

### Rule

Only actions on the action allowlist can execute. No open-ended or dynamic operations. The allowlist is loaded at startup. Unknown actions are refused.

### What this means in practice

- Every executable action is defined in the action allowlist configuration (YAML)
- An action not present in the allowlist is refused before any parameter parsing occurs
- There is no wildcard, catch-all, or "run arbitrary command" action
- Adding a new action requires a configuration change and a server restart — it cannot be done at runtime
- The system does not support dynamic action registration, plugin loading, or user-defined actions

**Prohibited patterns:**
- Accepting an action name as a free-text string and dispatching to it
- Loading action definitions from an untrusted source at runtime
- Supporting a `run_raw` or `execute_command` action that accepts arbitrary operations

**Required patterns:**
- Action names are resolved by exact string match against the allowlist hash
- Unknown actions return a denial response with no information about what actions do exist

### Enforcement mechanism

1. **Startup validation** — the allowlist YAML is parsed and validated at server startup; invalid entries prevent startup
2. **Dispatch guard** — the action dispatcher checks the allowlist before any handler code runs
3. **Code review rule** — any PR that introduces a new action must add it to the allowlist configuration; any PR that introduces a dynamic dispatch path is a safety defect

### Denial response

When an action is not on the allowlist:
```json
{
  "status": "denied",
  "reason": "action_not_allowed",
  "message": "The requested action is not on the action allowlist.",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

The denial response must not reveal information about which actions are available. "Not on the action allowlist" is sufficient.

---

## 2. Dry-Run Enforcement

### Rule

Every action MUST support a dry-run mode that shows exactly what would change without executing. Dry-run responses include: what will be affected, estimated blast radius, and a confirmation nonce. Dry-run mode must NEVER trigger side effects.

### What this means in practice

- Every action handler implements two code paths: `dry_run` and `execute`
- When `dry_run: true` is passed (or when the action requires two-phase confirmation), the handler returns a preview without performing the mutation
- The dry-run response describes the specific resources that would be affected (job IDs, cache key patterns, flag names) and the estimated count
- The dry-run response includes a single-use confirmation nonce that can be used to authorize execution
- Dry-run code paths must be structurally incapable of triggering writes — they query state but never mutate it

**Prohibited patterns:**
- A dry-run path that calls the mutation method with a "don't actually do it" flag — the mutation code must not be reachable from dry-run
- A dry-run that "mostly" works but has edge cases where side effects leak (e.g., enqueuing a callback, touching a timestamp)
- Returning a preview without a nonce for actions that require two-phase confirmation

**Required patterns:**
- Dry-run handlers read current state using read-only queries
- Dry-run handlers compute the preview (affected resources, count, estimated blast radius)
- Dry-run handlers generate and return a confirmation nonce
- Dry-run handlers return without calling any write/mutate/enqueue methods

### Dry-run response format

```json
{
  "status": "preview",
  "action": "retry_failed_jobs",
  "parameters": {
    "queue": "mailers",
    "failed_since": "2026-03-18T00:00:00Z"
  },
  "preview": {
    "affected_resources": ["job-abc123", "job-def456", "job-ghi789"],
    "affected_count": 3,
    "blast_radius": "3 jobs in queue 'mailers'",
    "action_description": "Retry 3 failed jobs in queue 'mailers' that failed since 2026-03-18T00:00:00Z"
  },
  "confirmation": {
    "nonce": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
    "expires_at": "2026-03-18T14:35:00Z",
    "action_hash": "sha256:abc123..."
  },
  "timestamp": "2026-03-18T14:30:00Z"
}
```

### Enforcement mechanism

1. **Handler structure** — every action handler class must implement a `preview` method that is structurally separate from the `execute` method
2. **Test coverage** — every action must have tests that verify dry-run produces no side effects (check state before and after)
3. **Code review rule** — any action handler that lacks a `preview` method, or whose `preview` method calls mutation code, is a safety defect

---

## 3. Two-Phase Confirmation Protocol

### Rule

Destructive actions require two-phase confirmation: first a dry-run/preview, then an explicit confirmation with the nonce from the preview. The nonce is single-use, time-limited (configurable, default 30 seconds), and tied to the specific action+parameters.

### What this means in practice

- Destructive actions are marked in the allowlist with `requires_confirmation: true`
- When a destructive action is invoked without a confirmation nonce, the system automatically runs a dry-run preview and returns the preview response with a nonce
- The caller must then re-invoke the action with the nonce to execute it
- The nonce is validated against: expiration time, action name, parameter hash, and single-use status
- If any validation fails, the action is refused and a new dry-run is required

**Destructive actions include (but are not limited to):**
- `retry_all` — retries multiple jobs at once
- `discard` — permanently discards a job
- `cache_invalidate_pattern` — invalidates cache keys matching a pattern
- `flag_disable` — disables a feature flag

**Non-destructive actions (may skip two-phase):**
- `retry_single` — retries exactly one identified job (still requires dry-run support, but confirmation can be optional per config)
- `flag_read` — reads current flag state (no mutation)
- `job_inspect` — reads job details (no mutation)

### Nonce specification

| Property | Requirement |
|----------|------------|
| Format | `wnc_` prefix + 32 hex characters (128 bits of entropy). Example: `wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` |
| TTL | Configurable, default 30 seconds |
| Hard ceiling TTL | 120 seconds — not configurable beyond this |
| Hard floor TTL | 10 seconds — not configurable below this |
| Scope | Tied to action name + SHA-256 hash of sorted parameters + caller identity |
| Single-use | Consumed on successful execution; cannot be reused |
| Storage | Server-side (in-memory or configured store); never trusted from client alone |

### Nonce validation failures

```json
{
  "status": "denied",
  "reason": "nonce_invalid",
  "message": "Confirmation nonce is expired, already used, or does not match the requested action.",
  "timestamp": "2026-03-18T14:36:00Z"
}
```

The error message does not distinguish between expired, used, or mismatched nonces — this prevents probing.

### Operation types

The mutation policy (004) classifies every action into one of three operation types:

| Type | Confirmation | Description |
|------|-------------|-------------|
| `read` | Not required | Read-only actions (e.g., `inspect_job`, `read_flag`) |
| `mutate` | Required | State-changing actions with recoverable effects (e.g., `retry_job`, `toggle_flag`) |
| `mutate_destructive` | Required | State-changing actions with irreversible effects (e.g., `discard_job`, `delete_flag`) |

`mutate_destructive` actions may also use shorter nonce TTLs and additional confirmation warnings. See 004 for the complete action catalog with operation type assignments.

### Enforcement mechanism

1. **Allowlist annotation** — each action in the allowlist declares whether confirmation is required via `requires_confirmation`
2. **Dispatch guard** — the dispatcher checks confirmation requirements before calling the handler
3. **Nonce store** — a server-side nonce store tracks issued, consumed, and expired nonces
4. **Code review rule** — any PR that removes `requires_confirmation` from a destructive action, or bypasses nonce validation, is a safety defect

---

## 4. Parameter Validation

### Rule

All action parameters are validated against a strict schema before execution. Model names resolved via allowlist hash (not constantize). Values are typed. No arbitrary strings passed to eval/send/constantize.

### What this means in practice

- Every action in the allowlist defines a parameter schema: required parameters, optional parameters, types, and constraints
- Parameters are validated before the action handler is invoked — invalid parameters never reach handler code
- Type coercion is explicit and limited (string-to-integer for IDs, string-to-datetime for timestamps) — no implicit coercion
- Parameters that reference models, queues, or flags are validated against their respective allowlists
- No parameter value is ever used for dynamic dispatch, method resolution, or code evaluation

**Prohibited patterns:**
```ruby
# NEVER do this:
model_name.constantize                        # arbitrary class resolution
Object.const_get(model_name)                 # same problem
system(user_input)                           # shell execution
eval(user_input)                             # arbitrary code execution
record.send(user_provided_method)            # arbitrary method dispatch
connection.execute("DELETE FROM #{table}")   # SQL injection
Kernel.open(user_input)                      # command injection via open
```

**Required patterns:**
```ruby
# Always do this:
ALLOWED_ACTIONS[action_name]                 # lookup in explicit allowlist hash
ALLOWED_QUEUES.include?(queue_name)          # validate against known queues
schema.validate!(params)                     # validate against declared schema
job_class = JOB_CLASS_MAP[class_name]        # map through explicit hash, not constantize
```

### Parameter schema in allowlist

```yaml
actions:
  retry_failed_jobs:
    parameters:
      required:
        - name: queue
          type: string
          validate: allowed_queues
        - name: failed_since
          type: datetime
          validate: not_future
      optional:
        - name: limit
          type: integer
          validate: range(1, 1000)
          default: 50
```

### Enforcement mechanism

1. **Schema validation layer** — a dedicated validation step runs before every handler invocation
2. **Type enforcement** — parameters are cast to declared types; type mismatches are rejected
3. **Referential validation** — parameters that reference queues, flags, or job classes are checked against their respective allowlists
4. **Code review rule** — any handler that reads raw parameters without schema validation, or any parameter used for dynamic dispatch, is a safety defect

---

## 5. Action Allowlist

### Rule

Each action category (jobs, cache, flags) has an explicit allowlist of permitted operations defined in YAML. Operations not on the allowlist are refused. The allowlist defines: action name, required parameters, optional parameters, confirmation requirement, and blast radius cap.

### Allowlist format

```yaml
# config/action_policy.yml (illustrative subset — see 004-TQ-STND-mutation-policy.md for the canonical action catalog)

action_allowlist:
  jobs:
    retry_single:
      description: "Retry a single identified failed job"
      requires_confirmation: false
      blast_radius_cap: 1
      parameters:
        required:
          - name: job_id
            type: string
        optional: []
      rate_limit:
        max_per_minute: 10

    retry_failed_jobs:
      description: "Retry failed jobs in a queue matching criteria"
      requires_confirmation: true
      blast_radius_cap: 100
      parameters:
        required:
          - name: queue
            type: string
            validate: allowed_queues
          - name: failed_since
            type: datetime
        optional:
          - name: limit
            type: integer
            default: 50
            validate: range(1, 100)
      rate_limit:
        max_per_minute: 5

    discard:
      description: "Permanently discard a failed job"
      requires_confirmation: true
      blast_radius_cap: 1
      parameters:
        required:
          - name: job_id
            type: string
        optional: []
      rate_limit:
        max_per_minute: 10

    job_inspect:
      description: "Read job details (no mutation)"
      requires_confirmation: false
      blast_radius_cap: 0
      parameters:
        required:
          - name: job_id
            type: string
        optional: []
      rate_limit:
        max_per_minute: 30

  cache:
    cache_read:
      description: "Read a cache key value"
      requires_confirmation: false
      blast_radius_cap: 0
      parameters:
        required:
          - name: key
            type: string
        optional: []
      rate_limit:
        max_per_minute: 30

    cache_invalidate_key:
      description: "Invalidate a single cache key"
      requires_confirmation: false
      blast_radius_cap: 1
      parameters:
        required:
          - name: key
            type: string
        optional: []
      rate_limit:
        max_per_minute: 10

    cache_invalidate_pattern:
      description: "Invalidate cache keys matching a pattern"
      requires_confirmation: true
      blast_radius_cap: 500
      parameters:
        required:
          - name: pattern
            type: string
            validate: safe_pattern
        optional:
          - name: limit
            type: integer
            default: 100
            validate: range(1, 500)
      rate_limit:
        max_per_minute: 5

  flags:
    flag_read:
      description: "Read current state of a feature flag"
      requires_confirmation: false
      blast_radius_cap: 0
      parameters:
        required:
          - name: flag_name
            type: string
            validate: allowed_flags
        optional: []
      rate_limit:
        max_per_minute: 30

    flag_enable:
      description: "Enable a feature flag"
      requires_confirmation: true
      blast_radius_cap: 1
      parameters:
        required:
          - name: flag_name
            type: string
            validate: allowed_flags
        optional:
          - name: scope
            type: string
            validate: allowed_scopes
      rate_limit:
        max_per_minute: 3

    flag_disable:
      description: "Disable a feature flag"
      requires_confirmation: true
      blast_radius_cap: 1
      parameters:
        required:
          - name: flag_name
            type: string
            validate: allowed_flags
        optional:
          - name: scope
            type: string
            validate: allowed_scopes
      rate_limit:
        max_per_minute: 3
```

### Validation rules

- `allowed_queues` — queue name must appear in a separate `allowed_queues` list
- `allowed_flags` — flag name must appear in a separate `allowed_flags` list
- `allowed_scopes` — scope value must appear in a separate `allowed_scopes` list
- `safe_pattern` — cache pattern must not be `*` alone (blanket invalidation), must contain at least one non-wildcard segment
- `range(min, max)` — integer must be within the specified range
- `not_future` — datetime must not be in the future

### Startup validation

At startup, the server:
1. Parses the allowlist YAML
2. Validates every entry has required fields (description, requires_confirmation, blast_radius_cap, parameters)
3. Validates parameter schemas are well-formed
4. Validates cross-references (allowed_queues, allowed_flags lists exist if referenced)
5. Refuses to start if any validation fails

### Enforcement mechanism

1. **Startup gate** — invalid allowlist prevents server startup
2. **Dispatch guard** — every action request is checked against the allowlist before handler code runs
3. **Immutable at runtime** — the allowlist cannot be modified without a restart
4. **Code review rule** — any PR that introduces an action not defined in the allowlist, or that adds a dynamic dispatch path, is a safety defect

---

## 6. Blast Radius Caps

### Rule

Every action has a configurable maximum blast radius: max jobs affected per retry_all, max cache keys invalidated per pattern, max flags toggled per call. Hard ceilings exist that cannot be overridden by config.

### Defaults and hard ceilings

| Action category | Default cap | Hard ceiling | Unit |
|----------------|-------------|-------------|------|
| `retry_single` | 1 | 1 | jobs |
| `retry_failed_jobs` | 100 | 1000 | jobs |
| `discard` | 1 | 1 | jobs |
| `cache_invalidate_key` | 1 | 1 | keys |
| `cache_invalidate_pattern` | 100 | 500 | keys |
| `flag_enable` | 1 | 1 | flags per call |
| `flag_disable` | 1 | 1 | flags per call |

### What this means in practice

- If a `retry_failed_jobs` query matches 500 jobs but the blast radius cap is 100, **the request is rejected before any mutation occurs** — no partial execution, no silent truncation
- The rejection response includes the estimated count and the cap, so the caller knows why it failed and can narrow their scope
- The blast radius cap is checked during the dry-run preview — the preview estimates the affected count and rejects if it exceeds the cap
- At execution time, the count is rechecked — if the count has grown beyond the cap since the preview, execution is aborted
- Hard ceilings are coded into the application and cannot be raised by configuration; they exist to prevent misconfiguration from causing unbounded mutations
- A configuration value that exceeds the hard ceiling is rejected at startup

### Blast radius exceeded response

```json
{
  "status": "error",
  "error_code": "blast_radius_exceeded",
  "action": "retry_failed_jobs",
  "blast_radius_cap": 100,
  "estimated_affected": 347,
  "suggestion": "Add more specific filter criteria to reduce the affected count, or invoke multiple times with smaller batches.",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

Silent truncation (processing only the first N matches) is a safety defect — it masks the true scope of the request and creates unpredictable behavior. Rejection forces the caller to make an explicit decision about how to proceed.

### Enforcement mechanism

1. **Handler implementation** — every mutating handler enforces the cap before executing; the handler never processes more resources than the cap allows
2. **Hard ceiling validation** — hard ceilings are constants in code; configuration values are validated against them at startup
3. **Preview alignment** — dry-run previews apply the same cap, ensuring the preview matches what would actually execute
4. **Code review rule** — any handler that processes more resources than its declared cap, or any PR that raises a hard ceiling, is a safety defect

---

## 7. Rate Limiting

### Rule

Per-action rate limits prevent rapid-fire mutations. Configurable per action category. Default rates and hard ceilings prevent configuration from exceeding safe maximums.

### Defaults and hard ceilings

| Action category | Default rate | Hard ceiling | Window |
|----------------|-------------|-------------|--------|
| Job mutations (`retry_single`, `discard`) | 10/minute | 30/minute | Per minute, rolling |
| Batch job mutations (`retry_failed_jobs`) | 5/minute | 15/minute | Per minute, rolling |
| Cache invalidation (single key) | 10/minute | 30/minute | Per minute, rolling |
| Cache invalidation (pattern) | 5/minute | 10/minute | Per minute, rolling |
| Flag mutations (`flag_enable`, `flag_disable`) | 3/minute | 10/minute | Per minute, rolling |
| Read-only actions (`job_inspect`, `cache_read`, `flag_read`) | 30/minute | 120/minute | Per minute, rolling |

### What this means in practice

- Rate limits are enforced per caller identity, per action
- When a rate limit is exceeded, the action is refused with a `rate_limited` response
- The response includes a `retry_after` value indicating when the caller can try again
- Rate limits apply to both dry-run and execute invocations — dry-runs are not free
- Rate limit counters are not shared across action categories — exhausting job retry limits does not affect cache invalidation limits

### Rate limit response

```json
{
  "status": "denied",
  "reason": "rate_limited",
  "message": "Rate limit exceeded for action 'retry_failed_jobs'. Limit: 5/minute.",
  "retry_after_seconds": 23,
  "timestamp": "2026-03-18T14:30:00Z"
}
```

### Configuration

Rate limits are declared **inline per-action** in `config/action_policy.yml`, not in a separate file. Each action specifies its `rate_limit` field in the format `<count>/minute`. A global default in the `defaults` section applies to any action that omits its own rate limit. See 004-TQ-STND-mutation-policy.md for the complete policy format and all 19 actions with their rate limits.

In addition to per-action limits, `global_rate_limits` in the policy file cap total throughput across all callers:

```yaml
global_rate_limits:
  all_mutations: 120/minute
  all_reads: 600/minute
```

### Enforcement mechanism

1. **Rate limit middleware** — a middleware layer checks rate limits before the action handler is invoked
2. **Per-caller tracking** — rate limits are tracked per caller identity to prevent one caller from exhausting limits for all
3. **Hard ceiling validation** — configuration values exceeding hard ceilings are rejected at startup
4. **Code review rule** — any PR that bypasses rate limiting, or removes rate limits from a mutating action, is a safety defect

---

## 8. Before/After State Snapshots

### Rule

Every mutation records the state before and after the action in the audit trail. Snapshots are mandatory for every executed (non-dry-run) action.

### What this means in practice

- Before executing a mutation, the handler captures the current state of the affected resources
- After executing the mutation, the handler captures the new state
- Both snapshots are included in the audit record
- Snapshots provide a traceable record of exactly what changed and enable diagnosis of unexpected outcomes

**Snapshot content by action category:**

| Category | Before snapshot | After snapshot |
|----------|----------------|---------------|
| Jobs | Job ID, status, queue, error class, failed_at, retry count | Job ID, new status, enqueued_at (if retried), discarded_at (if discarded) |
| Cache | Key, existence (true/false), value hash (SHA-256, not raw value) | Key, existence (true/false), cleared confirmation |
| Flags | Flag name, enabled/disabled, scope, last_changed_at | Flag name, enabled/disabled, scope, changed_at |

### Snapshot rules

- **Raw values are never stored in snapshots.** Cache values are stored as SHA-256 hashes. Job arguments are stored as a hash, not the raw payload. This prevents sensitive data from leaking into the audit trail.
- **Snapshots are part of the audit record**, not a separate store. They travel with the audit entry.
- **Snapshot capture failures do not silently proceed.** If the before-snapshot cannot be captured (e.g., the resource is not found), the action is refused rather than proceeding without a record.
- **Dry-run invocations do not produce snapshots** — they produce previews instead (see Rule 2).

### Audit record with snapshots

```json
{
  "id": "uuid",
  "timestamp": "2026-03-18T14:30:00Z",
  "caller_id": "service-account-ops",
  "action": "retry_failed_jobs",
  "parameters": {
    "queue": "mailers",
    "failed_since": "2026-03-18T00:00:00Z",
    "limit": 50
  },
  "outcome": "success",
  "confirmation_nonce": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
  "blast_radius": {
    "affected_count": 3,
    "cap_applied": 100,
    "capped": false
  },
  "snapshots": {
    "before": [
      {"job_id": "abc123", "status": "failed", "queue": "mailers", "error_class": "Net::SMTPError", "failed_at": "2026-03-18T02:15:00Z", "retry_count": 3},
      {"job_id": "def456", "status": "failed", "queue": "mailers", "error_class": "Net::SMTPError", "failed_at": "2026-03-18T03:22:00Z", "retry_count": 1},
      {"job_id": "ghi789", "status": "failed", "queue": "mailers", "error_class": "Timeout::Error", "failed_at": "2026-03-18T04:10:00Z", "retry_count": 2}
    ],
    "after": [
      {"job_id": "abc123", "status": "enqueued", "enqueued_at": "2026-03-18T14:30:01Z"},
      {"job_id": "def456", "status": "enqueued", "enqueued_at": "2026-03-18T14:30:01Z"},
      {"job_id": "ghi789", "status": "enqueued", "enqueued_at": "2026-03-18T14:30:01Z"}
    ]
  },
  "duration_ms": 87,
  "server_version": "0.1.0"
}
```

### Enforcement mechanism

1. **Handler contract** — every mutating handler must return both `before_snapshot` and `after_snapshot` as part of its result; the audit layer rejects results missing either
2. **Snapshot validation** — the audit layer validates that snapshots are non-empty and structurally correct before writing the audit record
3. **Snapshot-before-execute ordering** — the before-snapshot is captured and stored in memory before the mutation executes; if the mutation fails, the before-snapshot is still recorded with the error outcome
4. **Code review rule** — any mutating handler that omits before/after snapshots, or stores raw sensitive values in snapshots, is a safety defect

---

## 9. Identity and Capability Gate Required

### Rule

Every invocation must carry a known caller identity. Anonymous invocations are rejected. The capability gate (`wild-capability-gate`) is MANDATORY — not stubbed. Every action checks the gate before execution. If the gate is unavailable, the action fails closed (denied), not open.

### What this means in practice

- The MCP session must provide a caller identity (API key, token, or service account identifier)
- The identity is validated before any action handler runs
- The validated identity is propagated through the entire call pipeline and recorded in the audit trail
- Anonymous requests receive a denial response and are logged as auth failures
- After identity validation, the capability gate is consulted to determine whether this caller is authorized for this specific action

**Critical difference from introspection repo:** The introspection repo stubs the capability gate in v1 because all operations are read-only. This repo does NOT stub the gate. Mutations require real capability checks from the start.

### Capability gate contract

The capability gate is an external service (`wild-capability-gate`) that answers authorization queries:

```
Request:  { caller_id, action, parameters }
Response: { allowed: true/false, reason: "...", constraints: {} }
```

- If the gate returns `allowed: false`, the action is denied
- If the gate is unreachable (network error, timeout), the action is denied (fail closed)
- If the gate returns an unexpected response format, the action is denied (fail closed)
- The gate response is included in the audit record

### Gate timeout

| Parameter | Default | Hard ceiling |
|-----------|---------|-------------|
| `gate_timeout_ms` | 3000 | 10000 |

If the gate does not respond within the timeout, the action is denied.

### Identity in audit records

Every audit record contains:
- `caller_id` — the resolved identity string
- `caller_type` — the kind of identity (api_key, service_account, token)
- `auth_result` — success, rejected, or invalid
- `gate_result` — allowed, denied, unavailable, timeout

### Denial responses

Identity failure:
```json
{
  "status": "denied",
  "reason": "authentication_required",
  "message": "A valid caller identity is required for all invocations.",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

Capability gate denial:
```json
{
  "status": "denied",
  "reason": "capability_denied",
  "message": "The caller is not authorized for the requested action.",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

Gate unavailable:
```json
{
  "status": "denied",
  "reason": "gate_unavailable",
  "message": "The capability gate is unavailable. Actions fail closed when the gate cannot be reached.",
  "timestamp": "2026-03-18T14:30:00Z"
}
```

### Enforcement mechanism

1. **Identity middleware** — a middleware layer extracts and validates caller identity before any action processing
2. **Gate middleware** — after identity validation, a separate middleware layer consults the capability gate
3. **Fail-closed default** — the gate client is configured to deny on any error condition (timeout, malformed response, network failure)
4. **No stub mode** — there is no configuration option to disable or stub the capability gate; it must be running for this server to accept any mutation
5. **Code review rule** — any PR that introduces a path bypassing identity validation or the capability gate, or that adds a stub/bypass mode for the gate, is a safety defect

---

## 10. Safety Defect Definition

### Rule

A **safety defect** is any code that, if deployed, would create a condition listed below. Safety defects must be fixed before the affected code ships. There is no "we'll fix it later" path for safety defects.

### Safety defect conditions

A safety defect is any code that:

1. **Executes an action not on the allowlist** — any code path that dispatches to an action handler without checking the action allowlist
2. **Allows dry-run to trigger side effects** — any dry-run code path that calls mutation methods, enqueues work, writes to a database, or modifies external state
3. **Allows confirmation bypass for destructive actions** — any code path that executes a destructive action (one marked `requires_confirmation: true`) without validating a confirmation nonce
4. **Omits before/after snapshots** — any mutating action handler that executes without recording before and after state snapshots in the audit trail
5. **Bypasses the capability gate** — any code path that executes an action without consulting the capability gate, or any configuration option that stubs/disables the gate
6. **Exceeds blast radius caps** — any handler that processes more resources than its declared blast radius cap, or any configuration that exceeds the hard ceiling
7. **Accepts code as input parameters** — any parameter value that is evaluated, executed, used for dynamic method dispatch (`send`, `public_send`), class resolution (`constantize`, `const_get`), or passed to `eval`, `system`, or `Kernel.open`
8. **Allows unauthenticated invocations** — any code path that reaches an action handler without a validated caller identity
9. **Bypasses rate limiting on mutating actions** — any mutating action that executes without rate limit checks, or any configuration that exceeds the hard ceiling for rate limits
10. **Omits audit records** — any action invocation (success, denial, error, timeout) that completes without producing a structured audit record

### Severity

All safety defects are treated as the highest priority. They block release. They are not weighted against feature velocity or convenience.

### Discovery protocol

When a safety defect is discovered:
1. Stop the affected work immediately
2. File the defect with a clear description of which safety rule is violated
3. Fix the defect before any other work on the affected component continues
4. Add a regression test that specifically exercises the defect scenario
5. Verify the fix against this safety model document

---

## Audit Trail

Every action invocation produces a structured audit record regardless of outcome. Successes, denials, dry-runs, timeouts, rate limits, and errors are all logged. Audit records are append-only.

### Full audit record schema

```json
{
  "id": "uuid",
  "timestamp": "ISO 8601",
  "caller_id": "string",
  "caller_type": "api_key | service_account | token",
  "action": "string",
  "category": "jobs | cache | flags",
  "parameters": {
    "sanitized": true,
    "fields": {}
  },
  "phase": "dry_run | execute",
  "confirmation_nonce": "string | null",
  "gate_result": "allowed | denied | unavailable | timeout",
  "outcome": "success | denied | rate_limited | timeout | error",
  "denial_reason": "string | null",
  "blast_radius": {
    "affected_count": 0,
    "cap_applied": 0,
    "capped": false
  },
  "snapshots": {
    "before": [],
    "after": []
  },
  "duration_ms": 0,
  "error_message": "string | null",
  "server_version": "0.1.0"
}
```

### Parameter sanitization

Before recording parameters in the audit trail:
- Action names and queue names are logged
- Job IDs and flag names are logged
- Cache keys are logged
- Cache values are never logged — only existence and value hashes
- Job arguments are logged as a hash, not raw content
- Any parameter referencing user PII is hashed before logging

### Storage

Audit records are written to a structured log (JSON lines file by default). The storage backend is pluggable. Audit records are never modified or deleted through the application.

---

## Conservative Defaults Summary

When a design decision involves choosing between more permissive and more restrictive behavior, choose restrictive. Operators can expand access through configuration. Contracting access after a mutation has executed is impossible.

| Decision point | Default | Rationale |
|---------------|---------|-----------|
| Action allowlist | Empty | No actions permitted until configured |
| Confirmation requirement | Required for destructive actions | Prevents accidental mutations |
| Blast radius caps | Low defaults (see Rule 6) | Limits damage from misconfigured calls |
| Rate limits | Conservative (see Rule 7) | Prevents rapid-fire mutation storms |
| Capability gate | Mandatory, fail-closed | No mutations without authorization |
| Nonce TTL | 30 seconds (ceiling 120s, floor 10s) | Short enough to prevent stale confirmations |
| Unknown action | Denied | Not "try to find a handler anyway" |
| Missing identity | Denied | Not "allow with reduced privileges" |
| Gate unavailable | Denied | Not "allow and check later" |
