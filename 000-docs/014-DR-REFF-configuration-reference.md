# Configuration Reference

**Doc type:** DR — Documentation & Reference
**Filed as:** 014-DR-REFF-configuration-reference
**Status:** Active
**Last updated:** 2026-03-19

---

## 1. Policy File Structure

`config/action_policy.yml` is the complete source of truth for what operations are permitted and under what constraints. The server raises `ConfigurationError` at startup if the file is missing, malformed, or invalid — all errors are collected and reported together.

Top-level keys:

```yaml
version: 1

defaults:
  # ...

hard_ceilings:
  # ...

global_rate_limits:
  # ...

action_categories:
  # ...
```

`version` must equal `1`. Any other value is a startup error.

---

## 2. Defaults Section

Applied when an action does not specify its own value for a given field.

```yaml
defaults:
  rate_limit: 30/minute          # applied if action omits rate_limit
  blast_radius_cap: 1            # applied if action omits blast_radius_cap
  requires_confirmation: true    # applied if action omits requires_confirmation
  nonce_ttl_seconds: 30          # applied if action omits nonce_ttl_seconds
```

All four fields are required. Missing any one is a startup error.

| Field | Type | Constraint |
|-------|------|------------|
| `rate_limit` | string | Must match `N/minute` |
| `blast_radius_cap` | integer | Must be <= `hard_ceilings.max_blast_radius` |
| `requires_confirmation` | boolean | — |
| `nonce_ttl_seconds` | integer | Must be within nonce TTL ceiling range |

---

## 3. Hard Ceilings Section

Absolute maximums enforced in code. No per-action override can exceed these.

```yaml
hard_ceilings:
  max_rate_limit: 60/minute
  max_blast_radius: 1000
  max_nonce_ttl_seconds: 120
  min_nonce_ttl_seconds: 10
```

All four fields are required. Any per-action value violating a ceiling is a startup error.

| Field | Meaning |
|-------|---------|
| `max_rate_limit` | Upper bound for any per-action rate limit |
| `max_blast_radius` | Upper bound for any per-action blast radius cap |
| `max_nonce_ttl_seconds` | Nonce TTL cannot exceed this (hard max: 120) |
| `min_nonce_ttl_seconds` | Nonce TTL cannot be shorter than this (hard min: 10) |

---

## 4. Global Rate Limits Section

Aggregate limits applied across all callers, in addition to per-caller per-action limits.

```yaml
global_rate_limits:
  all_mutations: 120/minute
  all_reads: 600/minute
```

Both fields are required. `all_mutations` applies to both `mutate` and `mutate_destructive` operations. `all_reads` applies to `read` operations. A request that passes its per-action limit but exceeds the global limit is denied with `rate_limited`.

Note: per-action rate limits are keyed by `caller_id:action_name`, providing per-caller isolation. The global limits are shared across all callers.

---

## 5. Action Definition Schema

Actions are defined under `action_categories`. Each category groups related actions under a name (must match `^[a-z][a-z0-9_]{0,63}$`).

```yaml
action_categories:
  <category_name>:
    description: "Human-readable category description"
    resource_scope: "Scope note for operators"
    actions:
      - name: <action_name>
        description: "What this action does"
        operation: <read|mutate|mutate_destructive>
        requires_confirmation: <true|false>
        blast_radius_cap: <integer>
        rate_limit: <N/minute>
        nonce_ttl_seconds: <integer>   # optional; defaults to defaults.nonce_ttl_seconds
        parameters:
          required:
            - <parameter definition>
          optional:
            - <parameter definition>
```

Required action fields: `name`, `operation`, `requires_confirmation`.

Action name format: must match `^[a-z][a-z0-9_]{0,63}$`. Duplicate names across categories are a startup error.

---

## 6. Parameter Schema

Each parameter in `required` or `optional` follows this structure:

```yaml
- name: <param_name>
  type: <string|integer|boolean|object>
  validation:               # optional for string/integer
    format: "^regex$"       # string only — anchored regex
    min_length: <integer>   # string only
    max_length: <integer>   # string only
    min: <integer>          # integer only
    max: <integer>          # integer only
  properties:               # object type only
    <key>:
      type: <string|integer|boolean>
  min_properties: <integer> # object type only — minimum number of keys required
  default: <value>          # optional fields only
```

All `required` parameters must be present in every call. `optional` parameters are validated against their rules if present. Missing optional parameters are not an error.

---

## 7. Operation Types

| Operation | Confirmation required | Nonce generated | Blast radius enforced | Audit phase |
|-----------|----------------------|-----------------|----------------------|-------------|
| `read` | No | No | No (reads always pass) | `execute` |
| `mutate` | Yes | Yes (call without nonce = preview) | Yes | `preview` then `execute` |
| `mutate_destructive` | Yes | Yes, shorter TTL default (15s in example) | Yes | `preview` then `execute` |

Validation rule: `read` actions must have `requires_confirmation: false`; `mutate` and `mutate_destructive` must have `requires_confirmation: true`. Mismatch is a startup error.

---

## 8. Nonce Protocol

Nonces are server-generated, single-use tokens that bind a confirmed execution to a specific preview. They are not operator-configurable beyond the TTL.

- Format: `wnc_` followed by 32 lowercase hex characters (e.g., `wnc_a3f9...`)
- Generated by: `NonceManager#generate`
- TTL source: `nonce_ttl_seconds` from action config (or defaults), clamped to `[min_nonce_ttl_seconds, max_nonce_ttl_seconds]`
- Binding: SHA-256 of `action_name | sorted_params_json | caller_id`
- Single-use: consumed on first valid confirmation; subsequent use returns `nonce_invalid`
- Client-visible denial reason is always `nonce_invalid` regardless of internal cause (oracle prevention)

---

## 9. Validation Rules and Startup Errors

`PolicyConfig.load` validates exhaustively before returning. All errors are collected and raised together as a single `ConfigurationError` with a semicolon-separated message.

Startup errors include:

| Condition | Error text pattern |
|-----------|-------------------|
| `version` != 1 | `version must be present and equal to 1` |
| Missing top-level section | `<section> section is required` |
| Missing required section field | `<section>.<field> is required` |
| `action_categories` not a Hash | `action_categories is required and must be a Hash` |
| Category name format invalid | `category name '<x>' does not match ...` |
| Action not a Hash | `action in category '<cat>' is not a Hash` |
| Action missing required field | `action '<name>' missing required field '<field>'` |
| Invalid operation value | `action '<name>' operation '<x>' must be one of: read, mutate, mutate_destructive` |
| `read` with `requires_confirmation: true` | `action '<name>' is a read operation and must have requires_confirmation: false` |
| `mutate`/`mutate_destructive` with `requires_confirmation: false` | `action '<name>' is a mutate... operation and must have requires_confirmation: true` |
| Rate limit format wrong | `action '<name>' rate_limit '<x>' must match format N/minute` |
| Rate limit exceeds ceiling | `action '<name>' rate_limit ... exceeds hard ceiling ...` |
| Blast radius exceeds ceiling | `action '<name>' blast_radius_cap ... exceeds hard ceiling ...` |
| Nonce TTL out of range | `action '<name>' nonce_ttl_seconds ... must be between ... and ...` |
| Duplicate action name | `duplicate action name '<name>' found again in category '<cat>'` |

---

## 10. Complete Parameter Reference for All 19 Actions

### Background Jobs (7 actions)

#### `inspect_job` — read

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `job_id` | yes | string | `^[a-zA-Z0-9_-]{1,255}$` |
| `queue_name` | no | string | `^[a-zA-Z0-9_-]{1,128}$` |

#### `list_failed_jobs` — read

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `queue_name` | no | string | `^[a-zA-Z0-9_-]{1,128}$` | — |
| `error_class` | no | string | `^[a-zA-Z0-9_:]{1,255}$` | — |
| `limit` | no | integer | min: 1, max: 200 | 50 |

#### `list_queues` — read

No parameters.

#### `retry_job` — mutate

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `job_id` | yes | string | `^[a-zA-Z0-9_-]{1,255}$` |

blast_radius_cap: 1, rate_limit: 10/minute

#### `retry_jobs_by_filter` — mutate

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `filter` | yes | object | min_properties: 1; properties: `queue_name` (string), `error_class` (string), `job_class` (string) | — |
| `max_count` | no | integer | min: 1, max: 100 | 10 |

blast_radius_cap: 100, rate_limit: 3/minute

#### `discard_job` — mutate_destructive

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `job_id` | yes | string | `^[a-zA-Z0-9_-]{1,255}$` |

blast_radius_cap: 1, rate_limit: 10/minute, nonce_ttl_seconds: 15

#### `discard_jobs_by_filter` — mutate_destructive

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `filter` | yes | object | min_properties: 1; properties: `queue_name` (string), `error_class` (string), `job_class` (string) | — |
| `max_count` | no | integer | min: 1, max: 100 | 10 |

blast_radius_cap: 100, rate_limit: 2/minute, nonce_ttl_seconds: 15

---

### Cache (5 actions)

#### `inspect_cache_key` — read

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `cache_key` | yes | string | max_length: 512 |

#### `inspect_cache_stats` — read

No parameters.

#### `list_cache_keys` — read

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `prefix` | yes | string | `^[a-zA-Z0-9_:/-]{1,256}$` | — |
| `limit` | no | integer | min: 1, max: 200 | 50 |

#### `invalidate_cache_key` — mutate

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `cache_key` | yes | string | max_length: 512 |

blast_radius_cap: 1, rate_limit: 30/minute

#### `invalidate_cache_pattern` — mutate_destructive

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `pattern` | yes | string | `^[a-zA-Z0-9_:/-]{1,256}$`, min_length: 3 | — |
| `dry_run` | no | boolean | — | false |

blast_radius_cap: 500, rate_limit: 2/minute, nonce_ttl_seconds: 15

The `min_length: 3` on `pattern` prevents accidental broad matches (e.g., a single-character prefix).

---

### Feature Flags (7 actions)

#### `read_flag` — read

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `flag_name` | yes | string | `^[a-zA-Z0-9_.-]{1,128}$` |

#### `list_flags` — read

| Param | Required | Type | Validation | Default |
|-------|----------|------|------------|---------|
| `filter` | no | string | `^[a-zA-Z0-9_.-]{1,128}$` | — |
| `enabled_only` | no | boolean | — | false |
| `limit` | no | integer | min: 1, max: 500 | 100 |

#### `toggle_flag` — mutate

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `flag_name` | yes | string | `^[a-zA-Z0-9_.-]{1,128}$` |
| `enabled` | yes | boolean | — |

blast_radius_cap: 1, rate_limit: 10/minute

#### `enable_flag_for_actor` — mutate

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `flag_name` | yes | string | `^[a-zA-Z0-9_.-]{1,128}$` |
| `actor_type` | yes | string | `^[a-zA-Z0-9_]{1,64}$` |
| `actor_id` | yes | string | `^[a-zA-Z0-9_-]{1,255}$` |

blast_radius_cap: 1, rate_limit: 10/minute

#### `disable_flag_for_actor` — mutate

Same parameters as `enable_flag_for_actor`.

blast_radius_cap: 1, rate_limit: 10/minute

#### `enable_flag_percentage` — mutate

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `flag_name` | yes | string | `^[a-zA-Z0-9_.-]{1,128}$` |
| `percentage` | yes | integer | min: 0, max: 100 |

blast_radius_cap: 1, rate_limit: 5/minute

#### `delete_flag` — mutate_destructive

| Param | Required | Type | Validation |
|-------|----------|------|------------|
| `flag_name` | yes | string | `^[a-zA-Z0-9_.-]{1,128}$` |

blast_radius_cap: 1, rate_limit: 3/minute, nonce_ttl_seconds: 15
