# Evaluation Strategy — Safety Model Verification

**Document type:** Security evaluation
**Filed as:** `012-TQ-SECU-evaluation-strategy.md`
**Status:** Active
**Last updated:** 2026-03-19

---

## Purpose

This document defines how the safety model (003-TQ-STND) is verified through adversarial testing. It maps every safety rule to its test coverage, defines what constitutes a passing result, and establishes the regression protocol.

---

## Test Suite Location

All adversarial safety tests live in `spec/safety/`:

| File | Beads Task | Safety Rules Covered |
|------|-----------|---------------------|
| `dry_run_isolation_spec.rb` | npj.1 | Rule 2 (dry-run enforcement) |
| `confirmation_enforcement_spec.rb` | npj.2 | Rule 3 (two-phase confirmation), Rule 5 (action allowlist nonce binding) |
| `blast_radius_spec.rb` | npj.3 | Rule 6 (blast radius caps) |
| `rate_limit_spec.rb` | npj.4 | Rule 7 (rate limiting) |
| `gate_failure_spec.rb` | npj.5 | Rule 9 (identity and capability gate), Rule 10.5 (gate bypass), Rule 10.8 (unauthenticated) |
| `parameter_injection_spec.rb` | npj.6 | Rule 4 (parameter validation), Rule 10.7 (code as input) |

---

## Safety Rule Coverage Map

| Safety Rule | Description | Test File(s) | Key Assertions |
|------------|-------------|-------------|----------------|
| 1. Mutation-bounded operations | Only allowlisted actions execute | `gate_failure_spec.rb`, existing `server/integration_spec.rb` | Unknown action returns `action_not_allowed` |
| 2. Dry-run enforcement | Preview never triggers side effects | `dry_run_isolation_spec.rb` | All 11 mutation actions: status=preview, nonce present, `write_methods_called` empty, adapter state unchanged |
| 3. Two-phase confirmation | Mutations require valid nonce | `confirmation_enforcement_spec.rb` | nil/fake/empty/expired/consumed/cross-action/cross-caller nonces all denied |
| 4. Parameter validation | Strict schema enforcement | `parameter_injection_spec.rb` | SQL, shell, eval, constantize, path traversal, oversized payloads all rejected |
| 5. Action allowlist | Dispatch guard checks before execution | Existing `guard/integration_spec.rb` + `server/integration_spec.rb` | Unknown actions denied before any handler code runs |
| 6. Blast radius caps | Operations exceeding caps are rejected | `blast_radius_spec.rb` | 150 jobs vs cap 100 denied; 600 keys vs cap 500 denied; response includes `estimated_count` and `cap` |
| 7. Rate limiting | Per-action and global rate limits | `rate_limit_spec.rb` | At-limit passes, over-limit denied, cross-caller isolated, global read limit enforced |
| 8. Before/after snapshots | Mutations record state changes | Existing executor specs + `server/integration_spec.rb` | Before/after snapshots present on successful mutations |
| 9. Identity and capability gate | Gate required, fail-closed | `gate_failure_spec.rb` | Explicit deny, GateError, StandardError, nil caller, empty caller — all denied with audit records |
| 10. Safety defect conditions | 10 prohibited patterns | Covered across all safety specs | Each defect condition has at least one adversarial test |

---

## Threat Model Coverage Map

| Threat (005-AT-ADEC) | Primary Test File | Verification |
|----------------------|-------------------|--------------|
| T1: Unintended mutation | `dry_run_isolation_spec.rb`, `confirmation_enforcement_spec.rb` | Preview produces no writes; no execution without valid nonce |
| T2: State corruption | `dry_run_isolation_spec.rb` | Adapter state unchanged after all previews |
| T3: Cascading failures | `blast_radius_spec.rb`, `rate_limit_spec.rb` | Caps enforced; rate limits deny excess requests |
| T4: Privilege escalation | `gate_failure_spec.rb` | Gate checked per-invocation; denial responses are uniform |
| T5: Parameter injection | `parameter_injection_spec.rb` | All injection payloads rejected before reaching adapters |
| T6: Audit bypass | `gate_failure_spec.rb` | Audit records verified for every denial path |
| T7: Replay attacks | `confirmation_enforcement_spec.rb` | Consumed nonce rejected on replay |
| T8: Confirmation bypass | `confirmation_enforcement_spec.rb` | Fabricated, empty, cross-action, cross-caller nonces all denied |
| T9: Rate limit bypass | `rate_limit_spec.rb` | Server-side enforcement; per-caller and global limits |
| T10: Rollback abuse | N/A (v1 excludes rollback) | No rollback endpoints exist |

---

## How to Run

```bash
# Run only the adversarial safety suite
bundle exec rspec spec/safety/ --format documentation

# Run the full test suite (includes safety + unit + integration)
bundle exec rspec

# Run with rubocop
bundle exec rubocop
```

---

## What a Passing Result Looks Like

A passing safety evaluation requires:

1. **All safety tests green** — `bundle exec rspec spec/safety/` exits with 0 failures
2. **Full suite green** — `bundle exec rspec` exits with 0 failures (safety tests do not break existing behavior)
3. **Zero rubocop offenses** — `bundle exec rubocop` exits with 0 offenses
4. **Every safety rule from 003-TQ-STND has at least one adversarial test** (verified by the coverage map above)
5. **Every threat from 005-AT-ADEC has corresponding test coverage** (verified by the threat map above)

---

## What Constitutes a Safety Defect

Per safety model rule 10, a safety defect is any code that:

1. Executes an action not on the allowlist
2. Allows dry-run to trigger side effects
3. Allows confirmation bypass for destructive actions
4. Omits before/after snapshots for mutations
5. Bypasses the capability gate
6. Exceeds blast radius caps
7. Accepts code as input parameters
8. Allows unauthenticated invocations
9. Bypasses rate limiting on mutating actions
10. Omits audit records for any invocation path

If any safety test fails, it indicates a potential safety defect. The defect must be fixed before the affected code ships.

---

## Regression Protocol

1. **On every PR**: Run `bundle exec rspec spec/safety/` as part of the CI pipeline. Any failure blocks merge.
2. **Before every release**: Run the full suite (`bundle exec rspec`) and verify safety tests pass independently.
3. **When adding new actions**: Add corresponding entries to `dry_run_isolation_spec.rb` (preview with zero writes) and ensure parameter validation covers the new action's schema.
4. **When modifying safety infrastructure**: Run the full safety suite and verify no regressions. Review the coverage maps above to ensure no gaps.
5. **Quarterly review**: Re-read 003-TQ-STND and 005-AT-ADEC, verify the coverage maps are still complete, and add tests for any new safety rules or threats.

---

## Current Metrics

| Metric | Value |
|--------|-------|
| Total tests | 439 |
| Safety tests | 42 |
| Mutation actions tested in dry-run | 11/11 |
| Safety rules with adversarial coverage | 10/10 |
| Threats with adversarial coverage | 9/10 (T10 N/A in v1) |
| Rubocop offenses | 0 |
