# Operator Deployment Guide

**Doc type:** OD — Operations & Deployment
**Filed as:** 013-OD-OPNS-operator-deployment-guide
**Status:** Active
**Last updated:** 2026-03-19

---

## 1. Prerequisites

- Ruby >= 3.2.0
- Rails >= 7.0 (the host application)
- `wild-capability-gate` reachable — either as a local gem sibling (`../wild-capability-gate`) or via GitHub. The server will not start without a configured gate.
- Sidekiq (or compatible adapter) for background job actions
- `Rails.cache` configured for cache actions
- Flipper (or compatible adapter) for feature flag actions

---

## 2. Installation

Add the gem to your application's Gemfile:

```ruby
# Production / CI — fetched from GitHub
gem 'wild-admin-tools-mcp',
    git: 'https://github.com/jeremylongshore/wild-admin-tools-mcp',
    branch: 'main'

# Local dev override (optional)
# USE_LOCAL_CAPABILITY_GATE=true bundle install
```

Install dependencies:

```bash
bundle install
```

---

## 3. Configuration

### 3a. Copy the policy file

The server will not start without `config/action_policy.yml`. Copy the example and edit for your environment:

```bash
cp config/action_policy.yml.example config/action_policy.yml
```

Edit `config/action_policy.yml` to enable the specific actions your environment needs. Actions not listed in the file are unconditionally denied.

See `014-DR-REFF-configuration-reference.md` for full schema documentation.

### 3b. Configure the capability gate

The gate must implement:

```ruby
gate.evaluate(caller:, capability:, context:)
# Returns an object with #allowed? and #denied? methods
```

The gate is called for every action with a capability in the form `admin_tools.<action_name>`. If the gate raises or returns denied, the request is rejected and audited. The server never falls back to a permissive mode — absent or erroring gates always deny.

### 3c. Configure adapters

Adapters bridge the executor layer to your actual infrastructure. All three are required; the server will raise `ConfigurationError` on startup if any are missing.

```ruby
WildAdminToolsMcp.configure do |config|
  config.gate = MyCapabilityGate.new

  config.job_adapter   = MyJobAdapter.new    # must subclass Executor::Adapters::JobAdapter
  config.cache_adapter = MyCacheAdapter.new  # must subclass Executor::Adapters::CacheAdapter
  config.flag_adapter  = MyFlagAdapter.new   # must subclass Executor::Adapters::FlagAdapter
end
```

Each adapter base class defines the required interface with `NotImplementedError` stubs. Implement all methods; read methods have no `!` suffix, mutating methods do.

**JobAdapter required methods:**
- `find_job(job_id)`
- `list_failed_jobs(**options)`
- `list_queues`
- `count_matching_jobs(**filter)`
- `retry_job!(job_id)`
- `retry_jobs!(**filter)`
- `discard_job!(job_id)`
- `discard_jobs!(**filter)`

**CacheAdapter required methods:**
- `read_key(cache_key)`
- `list_keys(**options)`
- `cache_stats`
- `count_matching_keys(pattern)`
- `delete_key!(cache_key)`
- `delete_matching!(pattern)`

**FlagAdapter required methods:**
- `read_flag(flag_name)`
- `list_flags(**options)`
- `toggle_flag!(flag_name, enabled)`
- `enable_for_actor!(flag_name, actor_type, actor_id)`
- `disable_for_actor!(flag_name, actor_type, actor_id)`
- `enable_percentage!(flag_name, percentage)`
- `delete_flag!(flag_name)`

### 3d. Configure the audit store (production)

`MemoryStore` is the default and is suitable only for tests — it does not survive process restarts. For production, use `JsonLinesStore`:

```ruby
WildAdminToolsMcp.configure do |config|
  config.audit_store = WildAdminToolsMcp::Audit::JsonLinesStore.new(
    path: 'log/admin_tools_audit.jsonl'
  )
end
```

The store creates its parent directory automatically. Each line is a complete JSON audit record.

---

## 4. Server Setup

### 4a. Load the policy config

```ruby
policy_config = WildAdminToolsMcp::Guard::PolicyConfig.load('config/action_policy.yml')
```

This raises `ConfigurationError` if the file is missing, contains invalid YAML, or fails any validation rule. All validation errors are collected and reported together — fix them all before retrying.

### 4b. Build the pipeline

```ruby
pipeline = WildAdminToolsMcp::Server::ServerFactory.build_pipeline(
  gate:          WildAdminToolsMcp.configuration.gate,
  policy_config: policy_config,
  audit_store:   WildAdminToolsMcp.configuration.audit_store
)
```

The pipeline wires together: Identity (extract + gate check) → Guard (allowlist, params, rate limit, blast radius) → AuditedPipeline (record before/after) → Executor (job/cache/flag).

### 4c. Build the server context

```ruby
server_context = WildAdminToolsMcp::Server::ServerFactory.build_server_context(
  pipeline:    pipeline,
  caller_id:   'ops-agent-1',   # identity of the connecting caller
  caller_type: 'agent'          # or 'user', 'system'
)
```

### 4d. Create and start the server

```ruby
server = WildAdminToolsMcp::Server::ServerFactory.create(server_context: server_context)
server.start
```

The MCP server exposes three tools: `manage_background_jobs`, `manage_cache`, `manage_feature_flags`.

---

## 5. Connection Testing

### Verify tools are discoverable

After starting, list available tools via your MCP client. You should see exactly three tools:

```
manage_background_jobs
manage_cache
manage_feature_flags
```

### Test a read action (no confirmation needed)

Call `manage_background_jobs` with `action: "list_queues"`. Expect a `status: "success"` response immediately — read actions bypass the two-phase confirmation flow.

### Test a preview (mutate action — phase 1)

Call `manage_background_jobs` with `action: "retry_job"` and `job_id: "<a real id>"`, without a nonce. Expect a `status: "preview"` response containing the projected effect and a `nonce` field in `metadata`. The nonce begins with `wnc_`.

### Test confirmation (phase 2)

Re-call with the same action, same parameters, and `nonce: "<the nonce from phase 1>"`. Expect `status: "success"`. The nonce is single-use and will be rejected on any subsequent call.

---

## 6. Production Checklist

- [ ] `config/action_policy.yml` copied and reviewed — remove any actions not needed in this environment
- [ ] Gate configured and reachable — server tested to return denied for unknown callers
- [ ] All three adapters implemented and returning correct data structures
- [ ] `JsonLinesStore` configured and log path is writable by the process
- [ ] `caller_id` set to a stable, auditable identity — not a placeholder
- [ ] Rate limits reviewed against expected traffic — lower per-action limits for destructive actions
- [ ] Blast radius caps reviewed — `invalidate_cache_pattern` defaults to 500, lower if pattern scope is uncertain
- [ ] Log rotation configured for the JSONL audit file
- [ ] Gate health check verified: `GateHealthCheck.new(gate_client: gate_client).check` returns `status: "healthy"`
- [ ] Test suite passes in this environment: `bundle exec rspec`
