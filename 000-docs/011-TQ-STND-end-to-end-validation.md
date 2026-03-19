# End-to-End Validation — Confirmation Flow Demo

**Document type:** Testing & Quality standard
**Filed as:** `011-TQ-STND-end-to-end-validation.md`
**Status:** Active
**Last updated:** 2026-03-19

---

## Purpose

This document describes how to validate the complete MCP server lifecycle: tool discovery, read operations, dry-run preview, nonce-based confirmation, before/after snapshots, and denial paths. It serves as the acceptance test for operator deployment.

---

## Quick Validation

Run the full test suite — it covers every code path including the adversarial safety suite:

```bash
bundle exec rspec --format documentation
# Expected: 439 examples, 0 failures

bundle exec rspec spec/safety/ --format documentation
# Expected: 42 adversarial safety tests, 0 failures
```

---

## Manual Validation Script

The following Ruby script exercises the full confirmation flow through the actual MCP tool classes. Run it after configuring your adapters and gate.

```ruby
require 'wild_admin_tools_mcp'

# 1. Configure adapters (replace with your real adapters)
WildAdminToolsMcp.configure do |c|
  c.job_adapter  = YourApp::SidekiqJobAdapter.new
  c.cache_adapter = YourApp::RedisCacheAdapter.new
  c.flag_adapter  = YourApp::FlipperFlagAdapter.new
end

# 2. Load policy and build pipeline
policy = WildAdminToolsMcp::Guard::PolicyConfig.load('config/action_policy.yml')
gate   = YourApp::CapabilityGate.new  # must implement evaluate(caller:, capability:, context:)
audit  = WildAdminToolsMcp::Audit::JsonLinesStore.new('log/admin_audit.jsonl')

pipeline = WildAdminToolsMcp::Server::ServerFactory.build_pipeline(
  gate: gate, policy_config: policy, audit_store: audit
)

ctx = WildAdminToolsMcp::Server::ServerFactory.build_server_context(
  pipeline: pipeline, caller_id: 'validation-operator'
)

# 3. Test a read action (no confirmation required)
read_response = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
  action: 'inspect_job', job_id: 'test-job-1', server_context: ctx
)
puts "Read: #{read_response.structured_content[:status]}"
# Expected: "success"

# 4. Test a mutation preview (returns nonce)
preview = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
  action: 'retry_job', job_id: 'test-job-1', server_context: ctx
)
puts "Preview: #{preview.structured_content[:status]}"
puts "Nonce: #{preview.structured_content[:metadata][:nonce]}"
# Expected: status="preview", nonce starts with "wnc_"

# 5. Confirm with nonce (executes the mutation)
nonce = preview.structured_content[:metadata][:nonce]
confirm = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
  action: 'retry_job', job_id: 'test-job-1', nonce: nonce, server_context: ctx
)
puts "Confirm: #{confirm.structured_content[:status]}"
puts "Before: #{confirm.structured_content[:before_snapshot]}"
puts "After: #{confirm.structured_content[:after_snapshot]}"
# Expected: status="success", both snapshots present

# 6. Verify nonce replay is rejected
replay = WildAdminToolsMcp::Server::Tools::ManageBackgroundJobs.call(
  action: 'retry_job', job_id: 'test-job-1', nonce: nonce, server_context: ctx
)
puts "Replay: #{replay.structured_content[:status]} — #{replay.structured_content[:reason]}"
# Expected: status="denied", reason="nonce_invalid"

# 7. Verify audit trail
puts "Audit records: #{audit.count}"
# Expected: >= 4 records (read + preview + confirm + replay denial)
```

---

## What a Passing Validation Looks Like

| Step | Expected Status | Key Assertion |
|------|----------------|---------------|
| Read action | `success` | Direct execution, no nonce required |
| Mutation preview | `preview` | Nonce present in metadata, no state change |
| Nonce confirmation | `success` | Before/after snapshots present |
| Nonce replay | `denied` | Reason: `nonce_invalid` |
| Audit trail | 4+ records | Every invocation audited |

---

## Failure Indicators

| Symptom | Likely Cause |
|---------|-------------|
| All actions return `denied` with `gate_denied` | Gate not configured or denying all capabilities |
| All actions return `denied` with `anonymous_request_rejected` | caller_id not set in server context |
| Server won't start | Policy YAML validation error — check startup logs |
| Preview works but confirm fails with `nonce_invalid` | Nonce TTL too short, or params changed between calls |
| No audit records | Audit store not wired into pipeline |
