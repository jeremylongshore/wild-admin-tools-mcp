# REVIEW.md

Reviewer law for `wild-admin-tools-mcp`. The automated pull-request reviewer (MiniMax, two advisory
lanes) is bound by this file. Report only defects the pull request introduces, verify each against
the surrounding source, and rank by safety risk.

## What this repo is, and therefore what a defect is

This gem executes **mutations against a live Rails application** (Sidekiq jobs, Rails cache, Flipper
flags) on behalf of an AI agent or an operator, over MCP. It is the write half of the pair whose read
half is `wild-rails-safe-introspection-mcp`. Nothing here is a toy: a bad merge deletes production
cache keys, discards a queue, or flips a flag for every actor.

The request path is fixed and every stage is load bearing: `ToolHandler` to
`Identity::AuthenticatedPipeline` (identity, capability gate) to `Audit::AuditedPipeline` (audit
wrapping) to `Guard::Pipeline` (allowlist, params, rate limit, blast radius, nonce) to an Executor to
an Adapter to Rails. A change that lets a request reach an Executor while skipping, weakening, or reordering any stage
above it is the highest severity finding this repo has. Say so plainly and name the stage.

## Top defect classes to hunt, in order

1. **Fail-open capability gate.** `Identity::AuthenticatedPipeline#authorize_via_gate` rescues
   `GateError` into `session.with_gate_result('denied')`, and `GateClient#authorize` raises when the
   gate is `nil`. Any diff that turns a gate error, timeout, missing gate, or unknown gate result into
   an allow, or that adds a stub gate, a `skip_gate` option, or a test double reachable in production
   config, is fail open. Also flag a rescue widened to swallow the denial, and a capability string
   that stops being derived per action (`:"admin_tools.#{action_name}"`), since one coarse capability
   silently grants every action.
2. **Two-phase confirmation bypass.** A mutation must be previewed, then confirmed with a
   server-generated nonce bound by SHA256 to `action | sorted params | caller_id`. Flag: dropping
   `caller_id` or params from `compute_binding_hash`; comparing the binding with a non-constant path
   that leaks; consuming the nonce after execution instead of before; making `NonceStore` non-atomic
   so the same nonce confirms twice; any client-supplied nonce, TTL outside the 10 to 120 clamp, or
   any parameter named like `skip_confirmation`, `force`, or `confirm: true`.
3. **Confirmation oracle leaks.** `NonceManager` returns a single opaque `client_reason` of
   `nonce_invalid` and reports the discriminating detail separately as `internal_reason`
   (`nonce_not_found`, `nonce_expired`, `nonce_already_used`, `nonce_action_mismatch`,
   `nonce_identity_mismatch`, `nonce_parameter_mismatch`). **That separation does not currently hold
   end to end.** `TwoPhaseFlow#nonce_denied_result` copies `internal_reason` into the denial
   metadata, and `ResponseFormatter.denied_hash` splats the whole `result.metadata` into the client
   response, so today the discriminating reason does reach the client and **any key added to denial
   metadata is client visible**. Treat a diff that closes that leak as a fix, not a regression, and
   flag any new denial metadata that tells an attacker which check failed.
4. **Blast radius that stops being enforced twice.** `Guard::Pipeline` checks the cap at preview and
   again at confirmation (`at_execution: true`) precisely because the affected count can grow between
   the two phases. Flag removal of the second check, a count estimated from client input rather than
   from `executor.preview(...).data[:estimated_affected]`, and a cap read from anywhere other than the
   validated policy. Watch `invalidate_cache_pattern` and the batch job actions hardest.
5. **Preview with side effects.** Dry run must be observably inert. Every `preview_*` method must
   only read. `Guard::Pipeline#estimate_count` calls `executor.preview` on the confirmation path too,
   so a preview that mutates now mutates twice. Flag any `preview_*` that calls a bang adapter method
   (`delete_key!`, `delete_matching!`, retry, discard, enable, disable) or writes state.
6. **Unvalidated parameters reaching an adapter.** Parameters are data, never code. Flag `eval`,
   `constantize`, `send`, `public_send`, `Object.const_get`, string interpolation into a shell,
   ActiveRecord `where` with raw SQL, or a Redis or Sidekiq call built from an unchecked string.
   `ParameterValidator` is an allowlist: unknown keys are errors and every key must be declared in
   the action's policy schema. A new action or parameter that ships without a schema entry, or a
   schema whose `format` regex uses `^...$` rather than `\A...\z` (Ruby anchors those per line, so an
   embedded newline slips past), is a validation bypass.
7. **PII escaping the audit redactor.** `Audit::ParameterSanitizer` redacts and hashes by substring
   match against a fixed key list. Two live gaps a reviewer must police: a new parameter whose name
   is not covered by `DEFAULT_REDACT_KEYS` or `DEFAULT_HASH_KEYS` lands in the audit store in the
   clear, and **before/after snapshots are not sanitized at all**, so any snapshot field widened in
   `Executor::StateCapture` writes raw application state to the audit trail. Flag both, and never
   reproduce a suspected secret in a comment: name its location and the fix.
8. **Audit gaps.** Every invocation, including denials and raised errors, produces a record.
   `Audit::Recorder#record` appends an error record before re-raising. Flag any new early return,
   rescue, or short circuit that reaches an executor or a denial without passing through the
   recorder, and any change that drops `before_snapshot` or `after_snapshot` for an executed mutation.
9. **Policy ceilings that stop binding.** `Guard::PolicyConfig` validates exhaustively then freezes.
   Hard ceilings (`max_rate_limit`, `max_blast_radius`, `max_nonce_ttl_seconds`,
   `min_nonce_ttl_seconds`) are not overridable. Note the existing shape of the guards: ceiling checks
   `return unless cap.is_a?(Integer)` and `return unless rl`, so a wrong typed or absent value skips
   validation rather than failing. Flag any new setting that inherits that pattern, any mutation of
   the frozen config at runtime, and any path that lets the server boot without a valid policy.
10. **Rate limit bucket splitting.** `Guard::RateLimiter` keys per caller windows on
    `"#{caller_id}:#{action_name}"`. If `caller_id` becomes client controlled or nondeterministic, a
    caller mints a fresh bucket per request and the limit is gone. Flag identity that is not derived
    from the authenticated session.

## Invariants that must never regress

- **Gate mandatory.** No request reaches an executor without an allowed gate result. No bypass flag,
  no stub mode, no anonymous session (`session.anonymous?` is rejected before the gate runs).
- **Mutation implies confirmation.** `operation: mutate` and `mutate_destructive` require
  `requires_confirmation: true`; `operation: read` requires `false`. `PolicyConfig::ActionValidator`
  enforces this pairing and it must keep doing so.
- **Nonce is single use and fully bound.** One nonce, one action, one parameter set, one caller, one
  execution.
- **Caps are enforced in code, not advised in docs.** Blast radius, rate limits and TTLs are checked
  at runtime against the frozen policy.
- **The audit trail is complete.** Success, denial and error all produce a record.
- **Denial detail is meant to stay internal, and today it does not.** `NonceManager` produces the
  opaque `client_reason`, but `TwoPhaseFlow` copies `internal_reason` into denial metadata and
  `denied_hash` splats that metadata to the client. This is a known open gap, not a satisfied
  invariant: do not cite it as one, do not widen it, and welcome a diff that closes it.
- **Allowlist, never denylist.** Unknown actions and unknown parameters are denied by construction.

## What fail closed means here

On any uncertainty the request is **denied and audited**, never allowed and logged. Concretely: gate
unreachable means denied; gate raises means denied; policy file missing or invalid means the server
does not start; unknown action means denied; unknown or mistyped parameter means denied; nonce
missing, expired, reused or mismatched means denied. **One exception, verified in the source:** an
unknown blast radius is not denied. `Guard::Pipeline#estimate_count` substitutes `1` when a preview
returns no `estimated_affected`, so a mutating action whose preview omits that key passes the cap
check by default. Police new mutating actions for a real `estimated_affected`, and read that
fallback as an existing gap rather than as the fail closed rule.
A rescue that returns a permissive default, an `|| true`, an `unless ... allowed` inversion, or a
`rescue nil` on a guard is a fail-open defect even when the tests still pass.

## Generated, vendored, or operator owned files

- `Gemfile.lock`, `.beads/`, `vendor/bundle/`, `pkg/` are untracked by design. A PR that starts
  tracking one needs an explicit reason.
- `config/action_policy.yml` is **operator owned and gitignored**. Only
  `config/action_policy.yml.example` is tracked. A real policy committed to the repo is a finding.
- `000-docs/` follows the numbered filing standard and is canonical. `003-TQ-STND-safety-model.md`
  and `004-TQ-STND-mutation-policy.md` govern behaviour: a code change that alters a safety rule
  without updating its doc is drift, and so is a doc edit that silently relaxes a rule.
- `wild-capability-gate` resolves from git in CI and production. Flag a path dependency, an unpinned
  source, or a Gemfile change that makes the gate optional.

## What not to spend comments on

CI already runs `bundle exec rspec` and `bundle exec rubocop` on Ruby 3.2 and 3.3. Do not restate
RuboCop offenses, formatting, frozen string literal comments, method length, or Ruby idiom
preferences. Do not propose renames without a correctness reason, do not review the untracked
`Gemfile.lock`, and do not ask for tests that already exist in `spec/safety/` (42 adversarial
examples covering gate failure, dry run isolation, parameter injection, blast radius, rate limits and
confirmation enforcement; the six files hold 28 literal `it` blocks and two of them generate the
rest in loops, so count with `bundle exec rspec spec/safety --dry-run`, not with grep). Prefer a
few high conviction safety findings over a long list.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved and do not
invent objections on unchanged lines you previously accepted. If the change is correct and every
invariant above holds, reply `lgtm`. Both lanes are advisory and never block a merge.

## Sources

Every code-grounded claim above was verified by opening the file and reading the line, at commit
`5c02cec`, the head of this pull request branch immediately before this citation commit. No Ruby
source changed in either commit, so the line numbers below are current. Entries are grouped by the
section that makes the claim, so any one claim can be checked in a single jump.

**Request path (the fixed pipeline)**

- Wiring of every stage: `lib/wild_admin_tools_mcp/server/server_factory.rb:21-36`
- `ToolHandler` entry and response formatting: `lib/wild_admin_tools_mcp/server/tool_handler.rb:6-17`
- `Identity::AuthenticatedPipeline#call`: `lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb:12-25`
- `Audit::AuditedPipeline#call`: `lib/wild_admin_tools_mcp/audit/audited_pipeline.rb:13-23`
- `Guard::Pipeline` stage order, allowlist then params then rate limit then blast radius and nonce: `lib/wild_admin_tools_mcp/guard/pipeline.rb:28-45`

**1. Fail-open capability gate**

- `authorize_via_gate` rescues `GateError` into `session.with_gate_result('denied')`: `lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb:33-37`
- `GateClient#authorize` raises when the gate is `nil`: `lib/wild_admin_tools_mcp/identity/gate_client.rb:11`
- Per-action capability `:"admin_tools.#{action_name}"`: `lib/wild_admin_tools_mcp/identity/gate_client.rb:13`
- Anonymous session rejected before the gate runs: `lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb:15`, predicate at `lib/wild_admin_tools_mcp/identity/session_context.rb:22-24`
- Only `gate_result == 'allowed'` continues: `lib/wild_admin_tools_mcp/identity/session_context.rb:30-32`, checked at `lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb:19`

**2. Two-phase confirmation**

- Binding hash over `action | sorted params | caller_id`: `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:60-63`
- TTL clamp of 10 to 120 seconds: `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:16-17,27`
- Nonce consumed before execution, not after: `lib/wild_admin_tools_mcp/guard/two_phase_flow.rb:24-29`, consume at `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:54`
- Single use, mutex-guarded store: `lib/wild_admin_tools_mcp/guard/nonce_store.rb:33-48`, reuse rejected at `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:49`
- Nonce is server generated, never client supplied: `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:26-38`, issued at `lib/wild_admin_tools_mcp/guard/two_phase_flow.rb:12-22`

**3. Confirmation oracle**

- Single opaque `client_reason`: `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:18,75-77`
- The discriminating internal reasons: `lib/wild_admin_tools_mcp/guard/nonce_manager.rb:42,46,49,66,67,70`
- `internal_reason` copied into denial metadata: `lib/wild_admin_tools_mcp/guard/two_phase_flow.rb:33-42`
- `denied_hash` splats all metadata to the client: `lib/wild_admin_tools_mcp/server/response_formatter.rb:66-72`

**4. Blast radius**

- Checked at preview and again at confirmation: `lib/wild_admin_tools_mcp/guard/pipeline.rb:68-76`
- Enforcement helper and the `at_execution` reason string: `lib/wild_admin_tools_mcp/guard/pipeline.rb:78-84`
- Cap comparison and the read-operation exemption: `lib/wild_admin_tools_mcp/guard/blast_radius_enforcer.rb:10-28`
- Count source, including the fallback to `1`: `lib/wild_admin_tools_mcp/guard/pipeline.rb:86-89`
- Actions that publish `estimated_affected`: `lib/wild_admin_tools_mcp/executor/cache_executor.rb:73-76`, `lib/wild_admin_tools_mcp/executor/job_executor.rb:74-77,99-102`

**5. Preview must be inert**

- `preview` dispatch through `ACTION_MAP`: `lib/wild_admin_tools_mcp/executor/base.rb:8-25`
- Preview also runs on the confirmation path: `lib/wild_admin_tools_mcp/guard/pipeline.rb:87`
- Bang adapter methods a preview must never call: `lib/wild_admin_tools_mcp/executor/adapters/rails_cache_adapter.rb:54,61`, `lib/wild_admin_tools_mcp/executor/adapters/flipper_adapter.rb:29,40,47,54,60`, `lib/wild_admin_tools_mcp/executor/adapters/sidekiq_adapter.rb:37,46,53,62`
- A correct read-only preview beside its mutating execute: `lib/wild_admin_tools_mcp/executor/cache_executor.rb:62-80`

**6. Parameter validation**

- Allowlist entry point: `lib/wild_admin_tools_mcp/guard/parameter_validator.rb:18-32`
- Unknown keys are errors: `lib/wild_admin_tools_mcp/guard/parameter_validator.rb:43-48`
- `format` compiled with `Regexp.new`, so `^...$` anchors per line: `lib/wild_admin_tools_mcp/guard/parameter_validator.rb:99`
- Undeclared nested object properties rejected: `lib/wild_admin_tools_mcp/guard/parameter_validator.rb:113-129`
- Denial on validation failure: `lib/wild_admin_tools_mcp/guard/pipeline.rb:54-59`

**7. Audit redaction**

- Fixed `DEFAULT_REDACT_KEYS` and `DEFAULT_HASH_KEYS` lists: `lib/wild_admin_tools_mcp/audit/parameter_sanitizer.rb:11-19`
- Substring matching against those lists: `lib/wild_admin_tools_mcp/audit/parameter_sanitizer.rb:37-47`
- Snapshots written to the record unsanitized: `lib/wild_admin_tools_mcp/audit/recorder.rb:46-47`
- Snapshot fields that would flow there: `lib/wild_admin_tools_mcp/executor/state_capture.rb:44-50,60-76,88-94`

**8. Audit completeness**

- Every invocation wrapped by the recorder: `lib/wild_admin_tools_mcp/audit/audited_pipeline.rb:13-23`
- Success record, denial reason, snapshots: `lib/wild_admin_tools_mcp/audit/recorder.rb:35-50`
- Error record appended before the re-raise: `lib/wild_admin_tools_mcp/audit/recorder.rb:28-31`
- Denials raised above the guard are still recorded: `lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb:39-53`

**9. Policy ceilings**

- Validate exhaustively, raise, then freeze: `lib/wild_admin_tools_mcp/guard/policy_config.rb:31-38,44-48`
- Required hard ceilings: `lib/wild_admin_tools_mcp/guard/policy_config.rb:17`, required-section check at `lib/wild_admin_tools_mcp/guard/policy_config.rb:138-145`
- Early-return guard patterns `return unless rl`, `return unless cap.is_a?(Integer)`, `return unless ttl.is_a?(Integer)`: `lib/wild_admin_tools_mcp/guard/policy_config.rb:197,216,226`
- Missing or invalid policy file raises `ConfigurationError`: `lib/wild_admin_tools_mcp/guard/policy_config.rb:22-29`
- Mutation implies confirmation, read forbids it: `lib/wild_admin_tools_mcp/guard/policy_config.rb:185-193`

**10. Rate limiting**

- Per-caller bucket key `"#{caller_id}:#{action_name}"`: `lib/wild_admin_tools_mcp/guard/rate_limiter.rb:18-26`
- Global mutation and read buckets: `lib/wild_admin_tools_mcp/guard/rate_limiter.rb:40-47`
- Denial carrying `retry_after_seconds`: `lib/wild_admin_tools_mcp/guard/pipeline.rb:61-66`

**Allowlist and fail closed**

- Unknown action denied by construction: `lib/wild_admin_tools_mcp/guard/action_allowlist.rb:10-16`, denial at `lib/wild_admin_tools_mcp/guard/pipeline.rb:47-52`
- Single denial constructor for the guard stage: `lib/wild_admin_tools_mcp/guard/pipeline.rb:99-104`

**Generated, vendored, or operator owned**

- `Gemfile.lock`, `.beads/`, `vendor/bundle/`, `pkg/` ignored: `.gitignore:6,9,10,12`
- `config/action_policy.yml` ignored while the example is tracked: `.gitignore:19`, `config/action_policy.yml.example`
- The two governing safety docs named above exist: `000-docs/003-TQ-STND-safety-model.md`, `000-docs/004-TQ-STND-mutation-policy.md`
- `wild-capability-gate` resolved from git: `Gemfile:10-12`

**CI and the safety suite**

- rspec plus rubocop on Ruby 3.2 and 3.3: `.github/workflows/ci.yml:14,26,29`
- 42 safety examples: six files under `spec/safety/` holding 28 literal `it` blocks plus two
  generated groups (`spec/safety/parameter_injection_spec.rb:40`,
  `spec/safety/dry_run_isolation_spec.rb:35,48`). Counted by running
  `bundle exec rspec spec/safety --dry-run` at this commit, which reports `42 examples, 0 failures`.
