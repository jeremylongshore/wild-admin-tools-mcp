# Mutation Policy — wild-admin-tools-mcp

**Document type:** Safety standard
**Filed as:** `004-TQ-STND-mutation-policy.md`
**Status:** Active — governing spec for mutation operations
**Last updated:** 2026-03-18

---

## Purpose

This document defines the exact format, rules, and behavior of the action allowlist policy system for wild-admin-tools-mcp. It is the reference for implementing the mutation guard and confirmation protocol, and for operators who need to configure which administrative actions are available, their rate limits, blast radius caps, and confirmation requirements.

This is the mutation analog of the introspection repo's blocked-resource policy. Where that document governs what data can be _read_, this document governs what operations can be _performed_ — and under what constraints.

---

## Design Principles

1. **Deny by default.** If an action is not in the allowlist, it does not exist. There is no discovery of unregistered actions.
2. **Blast radius is bounded.** Every mutating action has an explicit cap on how many resources it can affect in a single invocation. There are no unbounded operations.
3. **Mutations require confirmation.** Every operation typed `mutate` or `mutate_destructive` requires a confirmation nonce before execution. No mutation executes on a single call.
4. **Rate limits are mandatory.** Every action has a rate limit. Hard ceilings exist that operators cannot exceed.
5. **The policy is static.** Loaded at startup, not modifiable at runtime. Changes require a restart.
6. **Scope is narrow.** Each action category can only touch its designated resource type. A job action cannot touch the cache. A cache action cannot toggle feature flags.

---

## Policy File

| File | Purpose | Location |
|------|---------|----------|
| `action_policy.yml` | Action allowlist — which actions are permitted, their types, rate limits, blast radius caps, and parameter schemas | `config/action_policy.yml` |

The policy file is loaded at server startup. Changes require a server restart. There is no runtime reload mechanism.

---

## Operation Types

Every action declares exactly one operation type. The operation type determines the confirmation and safety behavior.

| Operation | Confirmation | Description | Examples |
|-----------|-------------|-------------|----------|
| `read` | None | Retrieves state without modifying it | Inspect a job, read a flag value, view cache stats |
| `mutate` | Nonce required | Modifies state in a recoverable way | Retry a job, toggle a flag, invalidate a single cache key |
| `mutate_destructive` | Nonce required + warning | Modifies state in a way that may not be recoverable | Discard a job permanently, invalidate a cache pattern, delete a flag |

---

## Action Allowlist: `action_policy.yml`

### Format

```yaml
# config/action_policy.yml
#
# Actions listed here are available through admin tools.
# Actions NOT listed here do not exist — no exceptions.
# Every mutating action requires confirmation via nonce.

version: 1

defaults:
  rate_limit: 30/minute          # default per-action rate limit
  blast_radius_cap: 1            # default max affected resources
  requires_confirmation: true    # default confirmation requirement
  nonce_ttl_seconds: 30          # default nonce time-to-live

hard_ceilings:
  max_rate_limit: 60/minute      # no action can exceed this rate
  max_blast_radius: 1000         # no action can affect more than this many resources
  max_nonce_ttl_seconds: 120     # nonces cannot live longer than this
  min_nonce_ttl_seconds: 10      # nonces cannot expire faster than this

action_categories:
  background_jobs:
    description: "Background job management — inspect, retry, discard"
    resource_scope: "Job management system only (Sidekiq, GoodJob, etc.). No arbitrary ActiveRecord access."
    actions:
      - name: inspect_job
        description: "Retrieve the current state of a single background job"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: job_id
              type: string
              description: "The unique identifier of the job"
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional:
            - name: queue_name
              type: string
              description: "Queue to search in (omit to search all queues)"
              validation:
                format: "^[a-zA-Z0-9_-]{1,128}$"
        response_fields:
          - job_id
          - job_class
          - queue
          - status
          - arguments_summary
          - created_at
          - enqueued_at
          - started_at
          - completed_at
          - error_message
          - error_class
          - retry_count

      - name: list_failed_jobs
        description: "List jobs in a failed state with optional filtering"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required: []
          optional:
            - name: queue_name
              type: string
              description: "Filter by queue name"
              validation:
                format: "^[a-zA-Z0-9_-]{1,128}$"
            - name: error_class
              type: string
              description: "Filter by error class name"
              validation:
                format: "^[a-zA-Z0-9_:]{1,255}$"
            - name: job_class
              type: string
              description: "Filter by job class name"
              validation:
                format: "^[a-zA-Z0-9_:]{1,255}$"
            - name: limit
              type: integer
              description: "Maximum number of jobs to return"
              validation:
                min: 1
                max: 200
              default: 50
            - name: since
              type: string
              description: "Only jobs failed after this ISO8601 timestamp"
              validation:
                format: iso8601

      - name: list_queues
        description: "List all known queues with their current depth and status"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required: []
          optional: []

      - name: retry_job
        description: "Re-enqueue a single failed job for retry"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: job_id
              type: string
              description: "The unique identifier of the job to retry"
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: retry_jobs_by_filter
        description: "Re-enqueue multiple failed jobs matching a filter"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 100
        rate_limit: 3/minute
        parameters:
          required:
            - name: filter
              type: object
              description: "Filter criteria for selecting jobs to retry"
              properties:
                queue_name:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_-]{1,128}$"
                error_class:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_:]{1,255}$"
                job_class:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_:]{1,255}$"
                failed_since:
                  type: string
                  validation:
                    format: iso8601
              min_properties: 1
          optional:
            - name: max_count
              type: integer
              description: "Maximum number of jobs to retry in this batch"
              validation:
                min: 1
                max: 100
              default: 10

      - name: discard_job
        description: "Permanently discard a single failed job — not recoverable"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: job_id
              type: string
              description: "The unique identifier of the job to discard"
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: discard_jobs_by_filter
        description: "Permanently discard multiple failed jobs matching a filter — not recoverable"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 100
        rate_limit: 2/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: filter
              type: object
              description: "Filter criteria for selecting jobs to discard"
              properties:
                queue_name:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_-]{1,128}$"
                error_class:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_:]{1,255}$"
                job_class:
                  type: string
                  validation:
                    format: "^[a-zA-Z0-9_:]{1,255}$"
                failed_since:
                  type: string
                  validation:
                    format: iso8601
              min_properties: 1
          optional:
            - name: max_count
              type: integer
              description: "Maximum number of jobs to discard in this batch"
              validation:
                min: 1
                max: 100
              default: 10

  cache:
    description: "Cache management — inspect, invalidate"
    resource_scope: "Rails.cache operations only. No direct Redis/Memcached commands. No database access."
    actions:
      - name: inspect_cache_key
        description: "Read the value and metadata for a single cache key"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: cache_key
              type: string
              description: "The exact cache key to inspect"
              validation:
                format: "^[\\x20-\\x7E]{1,512}$"
                max_length: 512
          optional: []
        response_fields:
          - cache_key
          - exists
          - value_class
          - value_summary
          - byte_size
          - expires_at
          - created_at

      - name: inspect_cache_stats
        description: "Retrieve aggregate cache statistics"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required: []
          optional: []
        response_fields:
          - store_class
          - total_entries
          - memory_usage_bytes
          - hit_rate_percent
          - miss_rate_percent
          - eviction_count

      - name: list_cache_keys
        description: "List cache keys matching a safe prefix pattern"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: prefix
              type: string
              description: "Key prefix to search (no glob/regex — prefix match only)"
              validation:
                format: "^[a-zA-Z0-9_:/-]{1,256}$"
                max_length: 256
          optional:
            - name: limit
              type: integer
              description: "Maximum number of keys to return"
              validation:
                min: 1
                max: 200
              default: 50

      - name: invalidate_cache_key
        description: "Delete a single cache key"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required:
            - name: cache_key
              type: string
              description: "The exact cache key to invalidate"
              validation:
                format: "^[\\x20-\\x7E]{1,512}$"
                max_length: 512
          optional: []

      - name: invalidate_cache_pattern
        description: "Delete all cache keys matching a prefix pattern — may affect many keys"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 500
        rate_limit: 2/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: pattern
              type: string
              description: "Key prefix to match for deletion (prefix match only — no glob or regex)"
              validation:
                format: "^[a-zA-Z0-9_:/-]{1,256}$"
                max_length: 256
                min_length: 3
          optional:
            - name: dry_run
              type: boolean
              description: "If true, return the count and sample of keys that would be deleted without deleting them"
              default: false

  feature_flags:
    description: "Feature flag management — read, toggle, create, delete"
    resource_scope: "Configured feature flag framework only (Flipper, Unleash, LaunchDarkly, etc.). No direct database access."
    actions:
      - name: read_flag
        description: "Read the current state and configuration of a single feature flag"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
          optional: []
        response_fields:
          - flag_name
          - enabled
          - enabled_percentage
          - enabled_actors
          - enabled_groups
          - gate_values
          - created_at
          - updated_at

      - name: list_flags
        description: "List all known feature flags with their enabled state"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required: []
          optional:
            - name: filter
              type: string
              description: "Substring filter on flag name"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: enabled_only
              type: boolean
              description: "If true, return only enabled flags"
              default: false
            - name: limit
              type: integer
              description: "Maximum number of flags to return"
              validation:
                min: 1
                max: 500
              default: 100

      - name: toggle_flag
        description: "Enable or disable a feature flag globally"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag to toggle"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: enabled
              type: boolean
              description: "The desired state — true to enable, false to disable"
          optional: []

      - name: enable_flag_for_actor
        description: "Enable a feature flag for a specific actor (user, account, etc.)"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: actor_type
              type: string
              description: "The type of actor (e.g., User, Account)"
              validation:
                format: "^[a-zA-Z0-9_]{1,64}$"
            - name: actor_id
              type: string
              description: "The unique identifier of the actor"
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: disable_flag_for_actor
        description: "Disable a feature flag for a specific actor"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: actor_type
              type: string
              description: "The type of actor"
              validation:
                format: "^[a-zA-Z0-9_]{1,64}$"
            - name: actor_id
              type: string
              description: "The unique identifier of the actor"
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: enable_flag_percentage
        description: "Enable a feature flag for a percentage of actors"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 5/minute
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: percentage
              type: integer
              description: "Percentage of actors to enable the flag for (0-100)"
              validation:
                min: 0
                max: 100
          optional: []

      - name: delete_flag
        description: "Permanently delete a feature flag and all its gate data — not recoverable"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 3/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: flag_name
              type: string
              description: "The name of the feature flag to delete"
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
          optional: []
```

---

## Resource Scope Limits

Each action category is strictly scoped to its designated resource type. The mutation guard enforces these boundaries at the code level — not just by convention.

| Category | Permitted resource access | Explicitly forbidden |
|----------|--------------------------|---------------------|
| `background_jobs` | Job management system API (Sidekiq, GoodJob, Solid Queue, etc.) | No arbitrary ActiveRecord queries. No direct Redis commands. No database writes outside the job system. |
| `cache` | `Rails.cache` API only (`read`, `delete`, `delete_matched`, `stats`) | No direct Redis/Memcached commands. No database access. No filesystem cache manipulation. |
| `feature_flags` | Configured flag framework API (Flipper, Unleash, etc.) | No direct database queries against flag tables. No flag framework internals. No other ORM access. |

### Enforcement

The mutation guard resolves each incoming action to its category and routes it to the category-specific adapter. The adapter exposes only the operations listed in the policy. There is no pass-through to the underlying system — the adapter is the boundary.

If an action attempts to access a resource outside its category scope, the guard rejects the request with `scope_violation` and logs the attempt.

---

## Confirmation Requirements

### Protocol Overview

Mutating actions use a two-step confirmation protocol:

1. **Request phase:** The caller invokes the action. The server validates parameters, checks rate limits, and returns a confirmation prompt with a nonce — but does not execute the action.
2. **Confirm phase:** The caller invokes the action again with the nonce. The server validates the nonce, executes the action, and returns the result.

Read operations skip the confirmation protocol entirely.

### Confirmation by Operation Type

| Operation | Step 1 response | Step 2 required | Additional behavior |
|-----------|----------------|-----------------|---------------------|
| `read` | Direct result | No | — |
| `mutate` | Confirmation prompt + nonce | Yes | Standard nonce |
| `mutate_destructive` | Confirmation prompt + nonce + destructive warning | Yes | Warning text explicitly states the operation is not recoverable. Nonce TTL uses the action's `nonce_ttl_seconds` or the default. |

### Confirmation Prompt Format

When a mutating action is invoked without a nonce, the response contains:

```json
{
  "status": "confirmation_required",
  "action": "retry_job",
  "operation": "mutate",
  "description": "Re-enqueue a single failed job for retry",
  "parameters_received": {
    "job_id": "abc-123"
  },
  "blast_radius": {
    "max_affected": 1,
    "estimated_affected": 1
  },
  "nonce": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
  "nonce_expires_at": "2026-03-18T14:30:30Z",
  "confirm_by_repeating": "Invoke this action again with the same parameters and include the nonce field."
}
```

For `mutate_destructive` operations, the response additionally includes:

```json
{
  "destructive_warning": "This operation permanently discards job abc-123. This action cannot be undone.",
  "status": "confirmation_required",
  ...
}
```

---

## Nonce Protocol

### Generation

- Nonces are generated server-side using a cryptographically secure random number generator.
- Format: `wnc_` prefix followed by 32 hex characters (128 bits of entropy). Example: `wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4`.
- The `wnc_` prefix stands for "wild nonce confirmation" and allows pattern matching in logs and audits.

### Binding

A nonce is bound to:

1. **Action name** — The nonce is only valid for the action that generated it.
2. **Parameters** — The nonce is only valid with the exact parameters that were submitted in the request phase. If any parameter changes, the nonce is invalid.
3. **Caller identity** — The nonce is only valid for the identity (API key / request context) that requested it.
4. **Timestamp** — The nonce has a TTL. After expiry, it is invalid.

If any of these bindings do not match on the confirm phase, the nonce is rejected with `nonce_invalid` and a new confirmation must be requested.

### TTL

| Setting | Default | Hard ceiling | Hard floor |
|---------|---------|-------------|------------|
| `nonce_ttl_seconds` (global default) | 30 seconds | 120 seconds | 10 seconds |
| Per-action `nonce_ttl_seconds` | Overrides global default | 120 seconds | 10 seconds |

After TTL expiry, the nonce is automatically invalidated. A new request phase is required.

### Single-Use

Every nonce is single-use. After successful confirmation and execution, the nonce is consumed and cannot be reused. Attempting to reuse a consumed nonce returns `nonce_already_used`.

### Storage

Nonces are stored in-memory with a background sweep that removes expired nonces. The nonce store is not persisted across server restarts — all outstanding nonces are invalidated on restart.

### Failure Modes

| Condition | Error code | Behavior |
|-----------|-----------|----------|
| Nonce not found | `nonce_not_found` | Reject. Caller must start a new request phase. |
| Nonce expired | `nonce_expired` | Reject. Caller must start a new request phase. |
| Nonce already used | `nonce_already_used` | Reject. This is logged as a potential replay attempt. |
| Parameters changed | `nonce_parameter_mismatch` | Reject. Caller must start a new request phase with the new parameters. |
| Caller identity mismatch | `nonce_identity_mismatch` | Reject. Logged as a potential impersonation attempt. |
| Action name mismatch | `nonce_action_mismatch` | Reject. Logged as a potential misuse attempt. |

### Error Response Design

The granular error codes in the table above (`nonce_not_found`, `nonce_expired`, `nonce_already_used`, etc.) are used **internally** — in server-side audit logs, structured log output, and the `denial_reason` field of audit records. This granularity enables precise incident investigation and replay detection.

The **client-facing response** always uses the generic `nonce_invalid` error code, per the security rationale in 003 Rule 3: distinguishing between "not found," "expired," and "already used" in client responses would allow an attacker to probe the nonce store (e.g., determining whether a nonce existed, whether it's been consumed, or whether timing is the issue).

```json
{
  "status": "error",
  "error_code": "nonce_invalid",
  "message": "Confirmation nonce is invalid, expired, or already used. Request a new confirmation.",
  "action": "retry_job"
}
```

The audit record for the same event includes the specific internal code:

```json
{
  "outcome": "nonce_rejected",
  "denial_reason": "nonce_expired",
  "nonce_id": "wnc_a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4",
  "ttl_exceeded_by_seconds": 14
}
```

---

## Rate Limit Configuration

### Structure

Every action declares a rate limit in the format `<count>/<window>`. The window is always `minute`.

```yaml
rate_limit: 30/minute
```

### Defaults and Overrides

| Level | How it works |
|-------|-------------|
| Global default | `defaults.rate_limit` in the policy file applies to any action that does not specify its own. |
| Per-action override | An action's `rate_limit` field overrides the global default. |
| Hard ceiling | `hard_ceilings.max_rate_limit` cannot be exceeded by any action, regardless of its declared rate limit. |

### Enforcement

- Rate limits are enforced per-action, per-caller-identity.
- The rate limiter uses a sliding window counter.
- When the limit is hit, the server returns `rate_limit_exceeded` with a `retry_after_seconds` field.
- Both request phases and confirm phases count against the rate limit.
- Read operations and mutate operations share no rate limit budget — they are tracked independently per action name.

### Rate Limit Response

```json
{
  "status": "error",
  "error_code": "rate_limit_exceeded",
  "action": "retry_job",
  "limit": "10/minute",
  "retry_after_seconds": 12
}
```

### Global Rate Limits

In addition to per-action, per-caller rate limits, the policy supports **global rate limits** that cap the total throughput across all callers and all actions. This defends against distributed attacks using multiple valid identities (see 005 Threat 9: Rate Limit Bypass).

```yaml
global_rate_limits:
  all_mutations: 120/minute
  all_reads: 600/minute
```

| Setting | Default | Hard ceiling | Scope |
|---------|---------|-------------|-------|
| `all_mutations` | 120/minute | 600/minute | All `mutate` and `mutate_destructive` actions combined |
| `all_reads` | 600/minute | 3000/minute | All `read` actions combined |

Global rate limits are enforced **in addition to** per-action limits. A request must pass both the per-action rate check and the global rate check. When the global limit is hit:

```json
{
  "status": "error",
  "error_code": "global_rate_limit_exceeded",
  "limit": "120/minute",
  "retry_after_seconds": 8,
  "message": "Global mutation rate limit exceeded. Try again in 8 seconds."
}
```

The `global_rate_limits` section is required in the policy file. It is validated at startup alongside per-action limits.

---

## Blast Radius Caps

### Purpose

Blast radius caps prevent a single invocation from affecting more resources than intended. They are the last-resort safety boundary — even if a filter matches 10,000 jobs, a cap of 100 means only 100 are processed.

### Structure

Every action declares a `blast_radius_cap` — an integer representing the maximum number of resources that a single invocation can affect.

### Defaults and Overrides

| Level | How it works |
|-------|-------------|
| Global default | `defaults.blast_radius_cap` in the policy file applies to any action that does not specify its own. |
| Per-action override | An action's `blast_radius_cap` overrides the global default. |
| Hard ceiling | `hard_ceilings.max_blast_radius` cannot be exceeded by any action, regardless of its declared cap. |

### Enforcement

- Before executing a batch mutation, the guard estimates the number of affected resources.
- If the estimate exceeds the blast radius cap, the request is rejected with `blast_radius_exceeded` before any mutation occurs.
- The confirmation prompt includes `blast_radius.estimated_affected` so the caller knows how many resources will be affected before confirming.

### Estimation

For batch operations (`retry_jobs_by_filter`, `discard_jobs_by_filter`, `invalidate_cache_pattern`), the guard runs a count query first. This count is:

1. Returned in the confirmation prompt as `estimated_affected`.
2. Compared against the blast radius cap.
3. Rechecked at execution time (between confirm and execute). If the count has grown beyond the cap since the request phase, execution is aborted with `blast_radius_exceeded_at_execution`.

### Blast Radius Response

```json
{
  "status": "error",
  "error_code": "blast_radius_exceeded",
  "action": "retry_jobs_by_filter",
  "blast_radius_cap": 100,
  "estimated_affected": 347,
  "suggestion": "Add more specific filter criteria to reduce the affected count, or invoke multiple times with smaller batches."
}
```

---

## Policy Loading and Validation

### Loading

1. The server reads `config/action_policy.yml` at startup.
2. The YAML is parsed and validated against the schema rules below.
3. If validation passes, the policy is frozen (immutable) and stored in memory.
4. If validation fails, the server refuses to start.

### Missing Policy File

If `config/action_policy.yml` does not exist, the server refuses to start with:

```
FATAL: Action policy file not found at config/action_policy.yml.
       wild-admin-tools-mcp requires an explicit action policy to operate.
       Create the file or copy from config/action_policy.yml.example.
```

There is no implicit default policy. The operator must define one.

### Validation Rules

| Check | Failure behavior |
|-------|-----------------|
| YAML syntax valid | Server refuses to start |
| `version` field present and equals `1` | Server refuses to start |
| `defaults` section present with `rate_limit` and `blast_radius_cap` | Server refuses to start |
| `hard_ceilings` section present with all four fields | Server refuses to start |
| Every action has `name`, `operation`, `requires_confirmation` | Server refuses to start |
| `operation` is one of `read`, `mutate`, `mutate_destructive` | Server refuses to start |
| `read` operations have `requires_confirmation: false` | Server refuses to start |
| `mutate` and `mutate_destructive` operations have `requires_confirmation: true` | Server refuses to start |
| `rate_limit` matches `^\d+/minute$` format | Server refuses to start |
| Per-action `rate_limit` does not exceed `hard_ceilings.max_rate_limit` | Server refuses to start |
| Per-action `blast_radius_cap` does not exceed `hard_ceilings.max_blast_radius` | Server refuses to start |
| Per-action `nonce_ttl_seconds` within hard ceiling and floor bounds | Server refuses to start |
| No duplicate action names across all categories | Server refuses to start |
| All `required` parameter names are non-empty strings | Server refuses to start |
| Parameter `type` is one of `string`, `integer`, `boolean`, `object` | Server refuses to start |
| Action `name` matches `^[a-z][a-z0-9_]{0,63}$` | Server refuses to start |
| Category name matches `^[a-z][a-z0-9_]{0,63}$` | Server refuses to start |
| `global_rate_limits` section present with `all_mutations` and `all_reads` | Server refuses to start |
| `global_rate_limits` values match `^\d+/minute$` format | Server refuses to start |
| `global_rate_limits` values do not exceed their hard ceilings (600/minute for mutations, 3000/minute for reads) | Server refuses to start |
| At least one action category with at least one action | Warning logged (server starts but nothing is usable) |

### Validation Error Format

Validation errors are collected and reported all at once — the server does not stop at the first error. This allows operators to fix all issues in a single pass.

```
FATAL: Action policy validation failed (4 errors):
  1. action_categories.background_jobs.actions[2].rate_limit "200/minute" exceeds hard ceiling "60/minute"
  2. action_categories.cache.actions[0] missing required field "operation"
  3. action_categories.feature_flags.actions[3].name "Toggle-Flag" does not match ^[a-z][a-z0-9_]{0,63}$
  4. Duplicate action name "inspect_job" found in categories "background_jobs" and "cache"
```

---

## Parameter Validation

### Type Rules

| Type | Validation |
|------|-----------|
| `string` | Must be a string. If `format` is provided, must match the regex. If `max_length` is provided, must not exceed it. If `min_length` is provided, must meet it. |
| `integer` | Must be a whole number. If `min` is provided, must be >= min. If `max` is provided, must be <= max. |
| `boolean` | Must be `true` or `false`. No truthy/falsy coercion. |
| `object` | Must be a hash/object. If `properties` are defined, only declared properties are accepted. If `min_properties` is defined, the object must have at least that many keys. Undeclared properties are rejected. |

### Required vs. Optional

- `required` parameters must be present. If missing, the request is rejected with `missing_required_parameter`.
- `optional` parameters may be omitted. If omitted and a `default` is declared, the default is used. If omitted with no default, the parameter is absent.
- Undeclared parameters (not in `required` or `optional`) are rejected with `unknown_parameter`. This prevents parameter injection.

### Validation Error Response

```json
{
  "status": "error",
  "error_code": "parameter_validation_failed",
  "action": "retry_jobs_by_filter",
  "errors": [
    {
      "parameter": "filter",
      "error": "missing_required_parameter",
      "message": "The 'filter' parameter is required."
    },
    {
      "parameter": "max_count",
      "error": "validation_failed",
      "message": "Value 500 exceeds maximum of 100."
    }
  ]
}
```

---

## Audit Trail

Every invocation — whether it succeeds, fails, or is a confirmation request — produces an audit record. The audit record format is defined in the audit specification (separate document), but the mutation policy mandates these fields be present for every mutation-related log entry:

| Field | Description |
|-------|-------------|
| `action` | The action name |
| `operation` | `read`, `mutate`, or `mutate_destructive` |
| `category` | The action category |
| `phase` | `request`, `confirm`, or `direct` (for reads) |
| `parameters` | The parameters submitted (with sensitive values redacted) |
| `caller_identity` | The identity of the caller |
| `outcome` | `success`, `denied`, `error`, `confirmation_issued`, `nonce_rejected` |
| `resources_affected` | Count of resources affected (0 for reads and denials) |
| `nonce_id` | The nonce used (if applicable), for cross-referencing request and confirm phases |
| `timestamp` | ISO8601 timestamp |
| `duration_ms` | Wall-clock duration of the operation |

---

## Operator Workflows

### Adding a New Action

1. Open `config/action_policy.yml`.
2. Add the action to the appropriate `action_categories` section.
3. Define all required fields: `name`, `description`, `operation`, `requires_confirmation`, `blast_radius_cap`, `rate_limit`.
4. Define all parameters with types and validation rules.
5. Ensure the action name is unique across all categories.
6. Ensure `rate_limit` does not exceed `hard_ceilings.max_rate_limit`.
7. Ensure `blast_radius_cap` does not exceed `hard_ceilings.max_blast_radius`.
8. Implement the action handler in the corresponding category adapter.
9. Add tests that verify: parameter validation, confirmation protocol, rate limiting, blast radius enforcement, and audit logging.
10. Restart the server.
11. Verify by invoking the action and checking the audit log.

### Adjusting Rate Limits

1. Open `config/action_policy.yml`.
2. Modify the `rate_limit` field on the target action.
3. Verify the new value does not exceed `hard_ceilings.max_rate_limit`.
4. Restart the server.
5. Rate limit changes take effect immediately on restart — no in-flight rate windows are preserved.

### Adjusting Blast Radius Caps

1. Open `config/action_policy.yml`.
2. Modify the `blast_radius_cap` field on the target action.
3. Verify the new value does not exceed `hard_ceilings.max_blast_radius`.
4. Restart the server.
5. Any outstanding nonces from before the restart are invalidated — callers must re-request confirmation.

### Changing Hard Ceilings

Hard ceilings are safety boundaries. Raising them requires careful consideration.

1. Open `config/action_policy.yml`.
2. Modify the relevant `hard_ceilings` field.
3. Validate that no existing action exceeds the new ceiling (the server will catch this at startup if you lower a ceiling).
4. Document the reason for the change in the commit message.
5. Restart the server.

### Removing an Action

1. Remove the action entry from `config/action_policy.yml`.
2. The corresponding handler code can be left in place (it becomes unreachable) or removed.
3. Restart the server.
4. Any outstanding nonces for the removed action are invalidated — the action no longer exists.

### Emergency Lockdown

Set `action_categories: {}` in `action_policy.yml` and restart. The server will start with a warning that no actions are available. All incoming requests will be rejected with `action_not_found`.

---

## Example: Complete Policy File

A realistic policy for a mid-size Rails SaaS application:

```yaml
# config/action_policy.yml
version: 1

defaults:
  rate_limit: 30/minute
  blast_radius_cap: 1
  requires_confirmation: true
  nonce_ttl_seconds: 30

hard_ceilings:
  max_rate_limit: 60/minute
  max_blast_radius: 1000
  max_nonce_ttl_seconds: 120
  min_nonce_ttl_seconds: 10

global_rate_limits:
  all_mutations: 120/minute
  all_reads: 600/minute

action_categories:
  background_jobs:
    description: "Background job management"
    resource_scope: "Sidekiq API only"
    actions:
      - name: inspect_job
        description: "Retrieve state of a single job"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: job_id
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional:
            - name: queue_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,128}$"

      - name: list_failed_jobs
        description: "List jobs in failed state"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required: []
          optional:
            - name: queue_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,128}$"
            - name: error_class
              type: string
              validation:
                format: "^[a-zA-Z0-9_:]{1,255}$"
            - name: limit
              type: integer
              validation:
                min: 1
                max: 200
              default: 50

      - name: list_queues
        description: "List all queues with depth"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required: []
          optional: []

      - name: retry_job
        description: "Re-enqueue a single failed job"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: job_id
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: retry_jobs_by_filter
        description: "Re-enqueue failed jobs matching filter"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 100
        rate_limit: 3/minute
        parameters:
          required:
            - name: filter
              type: object
              properties:
                queue_name:
                  type: string
                error_class:
                  type: string
                job_class:
                  type: string
              min_properties: 1
          optional:
            - name: max_count
              type: integer
              validation:
                min: 1
                max: 100
              default: 10

      - name: discard_job
        description: "Permanently discard a single failed job"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: job_id
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: discard_jobs_by_filter
        description: "Permanently discard failed jobs matching filter"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 100
        rate_limit: 2/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: filter
              type: object
              properties:
                queue_name:
                  type: string
                error_class:
                  type: string
                job_class:
                  type: string
              min_properties: 1
          optional:
            - name: max_count
              type: integer
              validation:
                min: 1
                max: 100
              default: 10

  cache:
    description: "Cache management"
    resource_scope: "Rails.cache API only"
    actions:
      - name: inspect_cache_key
        description: "Read value and metadata for a cache key"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: cache_key
              type: string
              validation:
                max_length: 512
          optional: []

      - name: inspect_cache_stats
        description: "Retrieve aggregate cache statistics"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required: []
          optional: []

      - name: list_cache_keys
        description: "List cache keys matching a prefix"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: prefix
              type: string
              validation:
                format: "^[a-zA-Z0-9_:/-]{1,256}$"
          optional:
            - name: limit
              type: integer
              validation:
                min: 1
                max: 200
              default: 50

      - name: invalidate_cache_key
        description: "Delete a single cache key"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 30/minute
        parameters:
          required:
            - name: cache_key
              type: string
              validation:
                max_length: 512
          optional: []

      - name: invalidate_cache_pattern
        description: "Delete all cache keys matching a prefix"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 500
        rate_limit: 2/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: pattern
              type: string
              validation:
                format: "^[a-zA-Z0-9_:/-]{1,256}$"
                min_length: 3
          optional:
            - name: dry_run
              type: boolean
              default: false

  feature_flags:
    description: "Feature flag management"
    resource_scope: "Flipper API only"
    actions:
      - name: read_flag
        description: "Read state of a feature flag"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 60/minute
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
          optional: []

      - name: list_flags
        description: "List all feature flags"
        operation: read
        requires_confirmation: false
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required: []
          optional:
            - name: filter
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: enabled_only
              type: boolean
              default: false
            - name: limit
              type: integer
              validation:
                min: 1
                max: 500
              default: 100

      - name: toggle_flag
        description: "Enable or disable a feature flag"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: enabled
              type: boolean
          optional: []

      - name: enable_flag_for_actor
        description: "Enable flag for a specific actor"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: actor_type
              type: string
              validation:
                format: "^[a-zA-Z0-9_]{1,64}$"
            - name: actor_id
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: disable_flag_for_actor
        description: "Disable flag for a specific actor"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 10/minute
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: actor_type
              type: string
              validation:
                format: "^[a-zA-Z0-9_]{1,64}$"
            - name: actor_id
              type: string
              validation:
                format: "^[a-zA-Z0-9_-]{1,255}$"
          optional: []

      - name: enable_flag_percentage
        description: "Enable flag for a percentage of actors"
        operation: mutate
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 5/minute
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
            - name: percentage
              type: integer
              validation:
                min: 0
                max: 100
          optional: []

      - name: delete_flag
        description: "Permanently delete a feature flag"
        operation: mutate_destructive
        requires_confirmation: true
        blast_radius_cap: 1
        rate_limit: 3/minute
        nonce_ttl_seconds: 15
        parameters:
          required:
            - name: flag_name
              type: string
              validation:
                format: "^[a-zA-Z0-9_.-]{1,128}$"
          optional: []
```
