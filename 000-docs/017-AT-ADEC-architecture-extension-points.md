# Architecture Extension Points — wild-admin-tools-mcp

**Document type:** Architecture decision
**Filed as:** `017-AT-ADEC-architecture-extension-points.md`
**Status:** Active
**Last updated:** 2026-03-19

---

## Purpose

This document describes how to extend wild-admin-tools-mcp without modifying its safety infrastructure. Every extension point is designed so that the 10 safety rules (003-TQ-STND) remain enforced by the existing pipeline: AuthenticatedPipeline --> AuditedPipeline --> Guard::Pipeline --> Executors. Extensions add capabilities within those constraints; they do not bypass them.

---

## 1. Adding a New MCP Tool

A tool is the MCP-level surface — the thing a client sees and invokes. v1 ships with 3 tools: `ManageBackgroundJobs`, `ManageCache`, `ManageFeatureFlags`.

### Steps

1. Create a new class in `lib/wild_admin_tools_mcp/server/tools/` that follows the pattern of existing tool classes (parameter schema, handler method, delegation to pipeline).
2. Register the tool in `ServerFactory::TOOLS` array in `lib/wild_admin_tools_mcp/server/server_factory.rb`.
3. Add corresponding actions to `config/action_policy.yml` (see section 3 below).
4. Create a new executor (see section 2 below) to handle the tool's actions.
5. Register the executor in `ServerFactory.build_pipeline`.

### What the pipeline enforces automatically

Once the tool delegates to `AuthenticatedPipeline.call(action_name, params, request_context, nonce:)`, the following are enforced without any tool-level code:

- Identity extraction and anonymous rejection
- Capability gate authorization (fail-closed)
- Action allowlist check
- Parameter validation against policy schema
- Rate limiting (per-caller and global)
- Blast radius enforcement
- Two-phase confirmation flow (preview with nonce, then execute with nonce)
- Before/after state capture
- Audit record creation for every outcome

The tool class itself only needs to: define MCP parameter schemas, extract parameters from the MCP request, and call the pipeline.

---

## 2. Adding a New Action Category

An action category is a logical grouping of related actions served by a single executor. v1 has 3 categories: `background_jobs` (7 actions), `cache` (5 actions), `feature_flags` (7 actions).

### Steps

1. **Create a new executor** subclassing `Executor::Base` in `lib/wild_admin_tools_mcp/executor/`. Define an `ACTION_MAP` constant mapping action names to `{ preview:, execute:, operation: }` tuples. Every mutating action must have distinct `preview_*` and `execute_*` methods.
2. **Create a new adapter** (see section 3 below) defining the abstract interface for the backend.
3. **Add actions to the policy YAML.** Create a new `action_categories` entry in `config/action_policy.yml` with all required fields: `name`, `description`, `operation`, `requires_confirmation`, `blast_radius_cap`, `rate_limit`, and `parameters` for each action.
4. **Register the executor** in `ServerFactory.build_pipeline` via `authenticated_pipeline.register_executor(YourExecutor.new)`.
5. **Add capability definitions** in the gate configuration (`capabilities.yml`, `grants.yml`) with `admin_tools.{action_name}` entries for each new action.

### Executor contract

The executor must:

- Include `StateCapture` for before/after snapshots on mutating actions.
- Implement `preview_*` methods that query state without mutation. Preview methods must never call adapter write methods (those suffixed with `!`).
- Implement `execute_*` methods that perform the mutation via adapter write methods.
- Return `Result` objects from `preview` and `execute` (the `Base` class handles this).

### What `Base` provides

`Executor::Base` handles: action lookup via `ACTION_MAP`, timing, `Result` construction, before/after snapshot orchestration (calling `StateCapture` methods), and error wrapping. Subclasses only implement the action-specific preview and execute logic.

---

## 3. Adding a New Adapter Backend

Adapters bridge between executors and the underlying Rails subsystem. v1 ships with abstract adapters (`JobAdapter`, `CacheAdapter`, `FlagAdapter`) and concrete implementations (`SidekiqAdapter`, `RailsCacheAdapter`, `FlipperAdapter`).

### Steps

1. **Implement the abstract adapter interface.** Subclass the relevant abstract adapter (`Executor::Adapters::JobAdapter`, `CacheAdapter`, or `FlagAdapter`). Implement every method — the abstract base raises `NotImplementedError` for unimplemented methods.
2. **Follow the read/write convention.** Read methods (no side effects) have plain names: `find_job`, `read_key`, `read_flag`. Write methods (mutating) are suffixed with `!`: `retry_job!`, `delete_key!`, `toggle_flag!`. This convention is not decorative — preview methods must only call read methods, and execute methods call write methods.
3. **Configure via `WildAdminToolsMcp.configure`.** Set the adapter in the configuration block:

```ruby
WildAdminToolsMcp.configure do |config|
  config.job_adapter = YourCustomJobAdapter.new
  config.cache_adapter = YourCustomCacheAdapter.new
  config.flag_adapter = YourCustomFlagAdapter.new
end
```

### Adapter interface: JobAdapter

| Method | Type | Returns |
|--------|------|---------|
| `find_job(job_id)` | read | Hash with job details or nil |
| `list_failed_jobs(**options)` | read | Array of job hashes |
| `list_queues` | read | Array of queue hashes |
| `count_matching_jobs(**filter)` | read | Integer |
| `retry_job!(job_id)` | write | Result hash |
| `retry_jobs!(**filter, max_count:)` | write | Result hash with affected count |
| `discard_job!(job_id)` | write | Result hash |
| `discard_jobs!(**filter, max_count:)` | write | Result hash with affected count |

### Adapter interface: CacheAdapter

| Method | Type | Returns |
|--------|------|---------|
| `read_key(cache_key)` | read | Hash with key details or nil |
| `list_keys(**options)` | read | Array of key strings |
| `cache_stats` | read | Hash with stats |
| `count_matching_keys(pattern)` | read | Integer |
| `delete_key!(cache_key)` | write | Result hash |
| `delete_matching!(pattern)` | write | Result hash with affected count |

### Adapter interface: FlagAdapter

| Method | Type | Returns |
|--------|------|---------|
| `read_flag(flag_name)` | read | Hash with flag details or nil |
| `list_flags(**options)` | read | Array of flag hashes |
| `toggle_flag!(flag_name, enabled)` | write | Result hash |
| `enable_for_actor!(flag_name, actor_type, actor_id)` | write | Result hash |
| `disable_for_actor!(flag_name, actor_type, actor_id)` | write | Result hash |
| `enable_percentage!(flag_name, percentage)` | write | Result hash |
| `delete_flag!(flag_name)` | write | Result hash |

---

## 4. Adding a New Identity Provider

The identity layer extracts caller identity from the MCP request context. v1 uses `IdentityExtractor` which reads `caller_id`/`user_id`/`client_id` keys from a request context hash.

### Steps

1. **Subclass or replace `IdentityExtractor`.** The extractor must return a `SessionContext` value object (via `Data.define`) with: `caller_id`, `caller_type`, `authenticated` (boolean), `gate_result`, and `capabilities`.
2. **Handle anonymous detection.** Return a `SessionContext` with `authenticated: false` for any request where identity cannot be established. The `AuthenticatedPipeline` rejects anonymous sessions before the gate or guard pipeline is reached.
3. **Configure in pipeline construction.** Pass the custom extractor to `AuthenticatedPipeline.new(audited_pipeline:, gate_client:, extractor: YourExtractor.new)`.

### Extension scenarios

- **JWT tokens:** Extract caller_id from a JWT in the request context. Validate signature and expiry. Map JWT claims to caller_type.
- **OAuth tokens:** Exchange an OAuth token for identity via an introspection endpoint. Cache results with short TTL.
- **mTLS client certificates:** Extract identity from the client certificate CN or SAN fields.

### Constraint

The identity provider must not make authorization decisions. It extracts and validates identity only. Authorization is the gate's responsibility. The extractor must never return `authenticated: true` for a caller whose identity has not been verified.

---

## 5. Adding a New Audit Storage Backend

The audit layer uses a `Store` interface with two v1 implementations: `MemoryStore` (tests) and `JsonLinesStore` (production).

### Steps

1. **Implement the `Store` interface.** The store must support four methods:

| Method | Signature | Behavior |
|--------|-----------|----------|
| `append` | `append(record)` | Persist a single `Audit::Record`. Must be thread-safe. Must not raise on success. |
| `recent` | `recent(limit:)` | Return the most recent `limit` records, newest first. |
| `find` | `find(id)` | Return a single record by ID, or nil. |
| `count` | `count` | Return the total number of stored records. |

2. **Pass to `build_pipeline`.** Configure the store in `ServerFactory.build_pipeline(gate:, policy_config:, audit_store: YourStore.new)`.

### Constraints

- **Append-only.** The store must not support update or delete operations through its interface. Audit records are immutable once written.
- **Thread-safe.** Multiple pipeline invocations may write concurrently. The store must handle concurrent appends without data loss or corruption.
- **No silent failures.** If a write fails, the store must raise. The `Recorder` wraps execution in a begin/rescue that ensures audit records are written even for error paths.

### Extension scenarios

- **PostgreSQL store:** Write records to a database table. Use `INSERT` only — no `UPDATE` or `DELETE`.
- **Cloud logging store:** Emit records to a structured logging service (CloudWatch, Stackdriver, Datadog).
- **Multi-store fanout:** Write to multiple backends simultaneously (e.g., local JSON Lines + remote cloud logging).

---

## 6. Extension Safety Rules

Every extension — new tools, categories, adapters, identity providers, audit stores — must maintain the full safety model. These rules are non-negotiable:

1. **All 10 safety rules remain enforced.** Adding a new tool or action does not exempt it from any rule. The pipeline enforces rules structurally; extensions that bypass the pipeline are safety defects.
2. **New actions require parameter schemas in the policy YAML.** An action without a parameter schema in `config/action_policy.yml` cannot be dispatched — the `ActionAllowlist` guard rejects it.
3. **New adapters must support the preview/execute split.** Read methods for preview, write methods (suffixed with `!`) for execute. An adapter that exposes a write method without the `!` suffix, or a preview that calls a `!` method, is a safety defect.
4. **New actions require capability gate entries.** An action without a corresponding `admin_tools.{action_name}` capability definition in the gate configuration will be denied by the gate on every invocation.
5. **New mutating actions require adversarial test coverage.** At minimum: dry-run isolation test (preview produces no writes), confirmation enforcement test (execute without nonce is denied), and parameter injection test (malicious inputs are rejected).
6. **New audit stores must not break append-only semantics.** A store that exposes delete or update operations through any path — even an admin path — violates the audit integrity guarantee.
