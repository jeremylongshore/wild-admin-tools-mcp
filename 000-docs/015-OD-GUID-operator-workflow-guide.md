# Operator Workflow Guide

**Doc type:** OD — Operations & Deployment
**Filed as:** 015-OD-GUID-operator-workflow-guide
**Status:** Active
**Last updated:** 2026-03-19

---

## 1. Adding a New Action to the Allowlist

Actions not present in `config/action_policy.yml` are unconditionally denied with `action_not_allowed`. To expose a new action:

**Step 1: Choose the correct category.** Place the action under `background_jobs`, `cache`, or `feature_flags`. Category names must match `^[a-z][a-z0-9_]{0,63}$`.

**Step 2: Write the action definition.** Minimum required fields: `name`, `operation`, `requires_confirmation`.

```yaml
- name: pause_queue
  description: "Pause a specific Sidekiq queue"
  operation: mutate
  requires_confirmation: true
  blast_radius_cap: 1
  rate_limit: 5/minute
  nonce_ttl_seconds: 30
  parameters:
    required:
      - name: queue_name
        type: string
        validation:
          format: "^[a-zA-Z0-9_-]{1,128}$"
    optional: []
```

**Step 3: Validate the format.** The server collects all policy errors at startup. Run the server (or write a quick script) to surface any validation problems:

```ruby
WildAdminToolsMcp::Guard::PolicyConfig.load('config/action_policy.yml')
```

**Step 4: Implement the executor method.** The action will be denied with `action_not_found` at runtime if the corresponding executor does not handle it. Add the action name to your adapter and executor.

**Step 5: Restart the server.** Policy is loaded once at startup. There is no live reload.

---

## 2. Adjusting Blast Radius Caps

Blast radius caps bound how many records a single mutation can affect. They are enforced at both preview and execution time — if the executor's `preview` returns an `estimated_affected` count that exceeds the cap, the request is denied before any side effect occurs.

### When to lower a cap

- A pattern-based operation (e.g., `invalidate_cache_pattern`) covers a broader key space than expected
- An environment has production data at a scale where even the default cap is too permissive
- Operators are making errors that affect more records than intended

### When to raise a cap

- A legitimate bulk operation (e.g., retrying all jobs from a known bad deploy) requires affecting more records than the current cap permits
- The cap is so low that it blocks routine maintenance

### Hard ceiling constraint

No cap can exceed `hard_ceilings.max_blast_radius` (default: 1000). Attempting to set `blast_radius_cap: 1001` is a startup error. To change the maximum possible cap, edit `max_blast_radius` and restart.

```yaml
hard_ceilings:
  max_blast_radius: 500  # lower the ceiling for a conservative environment
```

### Example: tighten invalidate_cache_pattern

```yaml
- name: invalidate_cache_pattern
  operation: mutate_destructive
  requires_confirmation: true
  blast_radius_cap: 50    # was 500; tightened for this environment
  rate_limit: 2/minute
  nonce_ttl_seconds: 15
```

---

## 3. Changing Rate Limits

### Format

All rate limits use the format `N/minute` (e.g., `"10/minute"`). Any other format is a startup error. Only `/minute` is supported.

### Per-action vs. global

- **Per-action limits** are keyed by `caller_id:action_name` — each caller has an independent window for each action. Caller A being rate-limited does not affect Caller B.
- **Global limits** (`global_rate_limits.all_mutations`, `global_rate_limits.all_reads`) are shared across all callers and all actions in that category. They cap total throughput regardless of how many callers are active.

Both limits are checked on every request. A request that passes its per-action limit but exceeds the global is denied with `rate_limited`.

### Lowering a per-action rate limit

Edit the action's `rate_limit` field and restart. The sliding window is in-memory; there is no state to migrate.

```yaml
- name: discard_jobs_by_filter
  rate_limit: 1/minute   # was 2/minute; incident triage revealed this is safer
```

### Hard ceiling

No per-action rate limit can exceed `hard_ceilings.max_rate_limit` (default: `60/minute`). Attempting to set a higher value is a startup error.

---

## 4. Inspecting Audit Logs

### JsonLinesStore format

Each line is a self-contained JSON object. Parse with any JSON tool:

```bash
tail -n 100 log/admin_tools_audit.jsonl | jq .
```

### Record fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique record identifier |
| `timestamp` | string (ISO8601 ms) | UTC time of record creation |
| `caller_id` | string | Identity of the caller; `"anonymous"` if not authenticated |
| `action` | string | Action name (e.g., `"retry_job"`) |
| `category` | string | Category: `"background_jobs"`, `"cache"`, `"feature_flags"`, or `"unknown"` |
| `parameters` | object | Sanitized call parameters (sensitive values redacted by `ParameterSanitizer`) |
| `phase` | string | `"execute"`, `"preview"`, `"denied"`, `"error"` |
| `confirmation_nonce` | string or null | Nonce used in this call (execute phase only) |
| `gate_result` | string | `"allowed"`, `"denied"`, or `"not_checked"` |
| `outcome` | string | `"success"`, `"preview"`, `"denied"`, `"error"` |
| `denial_reason` | string or null | Machine-readable denial reason when `outcome == "denied"` |
| `before_snapshot` | object or null | State captured before mutation |
| `after_snapshot` | object or null | State captured after mutation |
| `duration_ms` | float | Wall-clock milliseconds for the operation |
| `error_message` | string or null | `"ClassName: message"` on `outcome == "error"` |
| `server_version` | string | Gem version that produced this record |

### Common queries

Find all denials in the last hour:

```bash
jq 'select(.outcome == "denied")' log/admin_tools_audit.jsonl | jq -s 'sort_by(.timestamp) | reverse | .[:20]'
```

Find all mutations by a specific caller:

```bash
jq 'select(.caller_id == "ops-agent-1" and .phase == "execute")' log/admin_tools_audit.jsonl
```

Find blast radius denials:

```bash
jq 'select(.denial_reason == "blast_radius_exceeded")' log/admin_tools_audit.jsonl
```

---

## 5. Revoking Access

### Via the gate

The gate is the primary access control mechanism. The server calls `gate.evaluate(caller:, capability:, context:)` before every operation. To revoke a caller's access:

1. Update the gate configuration to deny the caller's `caller_id` for `admin_tools.*` capabilities.
2. No server restart required — the gate is consulted on each request.

Denied gate responses produce an audit record with `outcome: "denied"`, `denial_reason: "gate_denied"`, and `gate_result: "denied"`.

### Anonymous rejection

Requests that arrive without a `caller_id` (or with a blank one) are rejected before gate evaluation with `denial_reason: "anonymous_request_rejected"`. There is no anonymous access mode. To reject a caller that previously had access, ensure its `caller_id` is absent from the request context or denied by the gate.

### Removing an action from the allowlist

Remove the action definition from `config/action_policy.yml` and restart the server. Subsequent calls to that action receive `action_not_allowed` immediately.

---

## 6. Troubleshooting Common Issues

### Server won't start

**Symptom:** `WildAdminToolsMcp::ConfigurationError` raised at startup with one or more semicolon-separated messages.

**Cause:** Policy validation failed. All errors are reported together.

**Fix:** Read the error message. Each clause names the field and the rule it violated. Correct all listed issues in `config/action_policy.yml` and restart. Common causes:

- `version` key missing or not `1`
- A required section (`defaults`, `hard_ceilings`, `global_rate_limits`) is absent
- An action's `rate_limit` exceeds `hard_ceilings.max_rate_limit`
- A `read` action has `requires_confirmation: true` (or vice versa)
- Duplicate action name across categories

### All actions denied — gate misconfigured

**Symptom:** Every request returns `status: "denied"`, audit log shows `gate_result: "denied"` or `denial_reason: "anonymous_request_rejected"`.

**Diagnosis:**

1. Check that `caller_id` is set in `server_context` — a blank or nil `caller_id` causes anonymous rejection before the gate is consulted.
2. Verify the gate is configured: `WildAdminToolsMcp.configuration.gate` must not be nil.
3. Run the gate health check:
   ```ruby
   gate_client = WildAdminToolsMcp::Identity::GateClient.new(gate: your_gate)
   WildAdminToolsMcp::Identity::GateHealthCheck.new(gate_client: gate_client).check
   # => { status: "healthy", gate_configured: true }
   ```
4. Verify the gate grants the `admin_tools.<action_name>` capability for this caller.

If the gate raises an exception during evaluation, the server treats it as a denial (`gate_denied`) and logs the error. Check application logs for `GateError` entries.

### Nonce expired — TTL too short

**Symptom:** Phase 2 call returns `status: "denied"` with `reason: "nonce_invalid"`. Internal audit shows `denial_reason` of `nonce_expired` (visible in the audit log, not the client response).

**Cause:** The caller took longer than `nonce_ttl_seconds` to submit the confirmation. The nonce is consumed (removed from the nonce store) upon expiry detection.

**Fix options:**

1. Increase `nonce_ttl_seconds` for the action in `config/action_policy.yml` (maximum: `hard_ceilings.max_nonce_ttl_seconds`, default max: 120).
2. Ensure the caller's workflow completes the confirmation step promptly after receiving the preview.

Note: the client always receives `reason: "nonce_invalid"` regardless of the specific internal cause (expired, action mismatch, parameter mismatch, already consumed). This is intentional — see the threat model for rationale.

### Rate limited unexpectedly

**Symptom:** `status: "denied"`, `reason: "rate_limited"`. May include `retry_after_seconds`.

**Diagnosis:**

- Check per-action rate: is this caller calling the action more than `rate_limit` times per minute?
- Check global rate: is the aggregate mutation or read rate across all callers exceeding `global_rate_limits`?

Per-action limits are keyed per caller, so a single noisy caller does not block others on per-action limits. The global limit is shared.

**Fix:** Either reduce call frequency, increase the relevant rate limit in policy, or investigate whether automation is running more frequently than expected.
