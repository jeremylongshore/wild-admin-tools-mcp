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
3. **Confirmation oracle leaks.** `NonceManager` deliberately returns a single opaque
   `client_reason` of `nonce_invalid` while keeping the discriminating `internal_reason`
   (`nonce_expired`, `nonce_identity_mismatch`, `nonce_parameter_mismatch`) internal. Note that
   `ResponseFormatter.denied_hash` splats the whole `result.metadata` into the client response, so
   **any key added to denial metadata is client visible**. Flag new denial metadata that tells an
   attacker which check failed.
4. **Blast radius that stops being enforced twice.** `Guard::Pipeline` checks the cap at preview and
   again at confirmation (`at_execution: true`) precisely because the affected count can grow between
   the two phases. Flag removal of the second check, a count estimated from client input rather than
   from `executor.preview(...)[:estimated_affected]`, and a cap read from anywhere other than the
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
- **Only `client_reason` crosses the response boundary.** Internal denial detail stays internal.
- **Allowlist, never denylist.** Unknown actions and unknown parameters are denied by construction.

## What fail closed means here

On any uncertainty the request is **denied and audited**, never allowed and logged. Concretely: gate
unreachable means denied; gate raises means denied; policy file missing or invalid means the server
does not start; unknown action means denied; unknown or mistyped parameter means denied; nonce
missing, expired, reused or mismatched means denied; estimated blast radius unknown means denied.
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
confirmation enforcement). Prefer a few high conviction safety findings over a long list.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved and do not
invent objections on unchanged lines you previously accepted. If the change is correct and every
invariant above holds, reply `lgtm`. Both lanes are advisory and never block a merge.
