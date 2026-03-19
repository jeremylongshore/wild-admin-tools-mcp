# Safety Cross-Reference Matrix — wild-admin-tools-mcp

**Document type:** Safety standard / reference
**Filed as:** `007-TQ-STND-safety-cross-reference-matrix.md`
**Status:** Active
**Last updated:** 2026-03-18

---

## Purpose

This document maps the relationships between the four safety documents that govern wild-admin-tools-mcp:

| Doc | Role |
|-----|------|
| 003 — Safety Model | 10 enforceable rules — the "what" |
| 004 — Mutation Policy | Action catalog, formats, config — the "how" |
| 005 — Threat Model | 10 threats with mitigations — the "why" |
| 006 — Architecture Decisions | 8 design decisions with rationale — the "why this way" |

This matrix exists to verify that every safety rule has corresponding threats it mitigates, architecture decisions that implement it, and policy artifacts that operationalize it. It also documents the 10 inconsistencies resolved during Epic 2 validation.

---

## 1. Rule-to-Threat-to-Decision Matrix

Each row is a safety rule from 003. Columns show which threats (005) it mitigates and which architecture decisions (006) implement it.

| # | Safety Rule (003) | Threats Mitigated (005) | Architecture Decisions (006) |
|---|-------------------|------------------------|------------------------------|
| 1 | Mutation-Bounded Operations (allowlist) | T1 (Unintended Mutation), T4 (Privilege Escalation), T5 (Parameter Injection) | D4 (Shared MCP Patterns — allowlist convention) |
| 2 | Dry-Run Enforcement | T1 (Unintended Mutation), T2 (State Corruption), T3 (Cascading Failures) | D1 (Dry-Run as First-Class Primitive) |
| 3 | Two-Phase Confirmation Protocol | T1 (Unintended Mutation), T7 (Replay Attacks), T8 (Confirmation Bypass) | D2 (Confirmation Nonce Pattern), D8 (Nonce Error Response Design) |
| 4 | Parameter Validation | T1 (Unintended Mutation), T5 (Parameter Injection) | D4 (Shared MCP Patterns — parameter convention) |
| 5 | Action Allowlist (YAML config) | T1 (Unintended Mutation), T4 (Privilege Escalation) | D4 (Shared MCP Patterns — config convention) |
| 6 | Blast Radius Caps | T1 (Unintended Mutation), T2 (State Corruption), T3 (Cascading Failures) | D6 (Blast Radius Caps as Architecture) |
| 7 | Rate Limiting | T3 (Cascading Failures), T9 (Rate Limit Bypass) | D7 (Rate Limiting Strategy) |
| 8 | Before/After State Snapshots | T2 (State Corruption), T6 (Audit Bypass), T10 (Rollback Abuse) | D3 (Before/After Audit Snapshots) |
| 9 | Identity and Capability Gate | T4 (Privilege Escalation), T8 (Confirmation Bypass), T9 (Rate Limit Bypass) | D5 (Mandatory Capability Gate) |
| 10 | Safety Defect Definition | All threats (defines the enforcement standard) | All decisions (defines what constitutes a violation) |

**Coverage analysis:** Every rule maps to at least one threat and one decision. No orphaned rules, threats, or decisions.

---

## 2. Threat-to-Rule Reverse Map

Verifies that every threat in 005 is addressed by at least one rule in 003.

| # | Threat (005) | Rules That Mitigate (003) |
|---|-------------|--------------------------|
| T1 | Unintended Mutation | R1 (Allowlist), R2 (Dry-Run), R3 (Confirmation), R4 (Parameters), R5 (YAML config), R6 (Blast Radius) |
| T2 | State Corruption | R2 (Dry-Run), R6 (Blast Radius), R8 (Snapshots) |
| T3 | Cascading Failures | R2 (Dry-Run), R6 (Blast Radius), R7 (Rate Limits) |
| T4 | Privilege Escalation | R1 (Allowlist), R5 (YAML config), R9 (Identity/Gate) |
| T5 | Parameter Injection | R1 (Allowlist), R4 (Parameters) |
| T6 | Audit Bypass | R8 (Snapshots), R10 (Defect Definition) |
| T7 | Replay Attacks | R3 (Confirmation) |
| T8 | Confirmation Bypass | R3 (Confirmation), R9 (Identity/Gate) |
| T9 | Rate Limit Bypass | R7 (Rate Limits), R9 (Identity/Gate) |
| T10 | Rollback Abuse | R8 (Snapshots — informational only, no rollback in v1) |

**Coverage analysis:** Every threat is mitigated by at least one rule. No unmitigated threats.

---

## 3. Action Catalog Cross-Reference

The 19 actions from 004's canonical action catalog with their safety-relevant properties and governing rules.

| # | Action | Category | Operation Type | Confirmation | Blast Radius Cap | Rate Limit | Governing Rules |
|---|--------|----------|---------------|-------------|-----------------|-----------|-----------------|
| 1 | `inspect_job` | background_jobs | read | No | 1 | 60/min | R1, R4, R5 |
| 2 | `list_failed_jobs` | background_jobs | read | No | 1 | 30/min | R1, R4, R5 |
| 3 | `list_queues` | background_jobs | read | No | 1 | 30/min | R1, R5 |
| 4 | `retry_job` | background_jobs | mutate | Yes | 1 | 10/min | R1-R8 |
| 5 | `retry_jobs_by_filter` | background_jobs | mutate | Yes | 100 | 3/min | R1-R8 |
| 6 | `discard_job` | background_jobs | mutate_destructive | Yes | 1 | 10/min | R1-R8 |
| 7 | `discard_jobs_by_filter` | background_jobs | mutate_destructive | Yes | 100 | 2/min | R1-R8 |
| 8 | `inspect_cache_key` | cache | read | No | 1 | 60/min | R1, R4, R5 |
| 9 | `inspect_cache_stats` | cache | read | No | 1 | 10/min | R1, R5 |
| 10 | `list_cache_keys` | cache | read | No | 1 | 10/min | R1, R4, R5 |
| 11 | `invalidate_cache_key` | cache | mutate | Yes | 1 | 30/min | R1-R8 |
| 12 | `invalidate_cache_pattern` | cache | mutate_destructive | Yes | 500 | 2/min | R1-R8 |
| 13 | `read_flag` | feature_flags | read | No | 1 | 60/min | R1, R4, R5 |
| 14 | `list_flags` | feature_flags | read | No | 1 | 10/min | R1, R4, R5 |
| 15 | `toggle_flag` | feature_flags | mutate | Yes | 1 | 10/min | R1-R8 |
| 16 | `enable_flag_for_actor` | feature_flags | mutate | Yes | 1 | 10/min | R1-R8 |
| 17 | `disable_flag_for_actor` | feature_flags | mutate | Yes | 1 | 10/min | R1-R8 |
| 18 | `enable_flag_percentage` | feature_flags | mutate | Yes | 1 | 5/min | R1-R8 |
| 19 | `delete_flag` | feature_flags | mutate_destructive | Yes | 1 | 3/min | R1-R8 |

**Summary:** 8 read actions, 7 mutate actions, 4 mutate_destructive actions. All mutating actions (11 total) require confirmation and are subject to all 8 operational rules (R1-R8). All actions are subject to R9 (Identity/Gate) and R10 (Safety Defect Definition).

---

## 4. Resolved Inconsistencies Log

During Epic 2 validation, 10 cross-document inconsistencies were identified and resolved. The resolution rationale follows the source-of-truth hierarchy: 004 wins on operational details, 003 wins on safety invariants.

| # | Issue | Severity | Docs in Conflict | Resolution | Docs Changed |
|---|-------|----------|-----------------|------------|--------------|
| 1 | Nonce TTL: 5min (003) vs 30s (004) vs 30min ceiling (006) | HIGH | 003, 006 vs 004 | Standardized to 004: default 30s, ceiling 120s, floor 10s | 003, 006 |
| 2 | Blast radius: truncation (003) vs rejection (004, 005, 006) | HIGH | 003 vs 004, 005, 006 | Standardized to rejection per 004. Truncation is a safety defect — it masks scope. | 003 |
| 3 | Nonce format: UUID v4 (003, 006) vs `wnc_` prefix (004) | MEDIUM | 003, 006 vs 004 | Standardized to 004: `wnc_` + 32 hex chars. Prefix enables log grep. | 003, 006 |
| 4 | Action names: illustrative (003) vs canonical (004) | LOW | 003 vs 004 | Added cross-reference note in 003 Rule 5 pointing to 004 as canonical catalog. | 003 |
| 5 | Operation types: binary (003) vs three-tier (004) | MEDIUM | 003 missing `mutate_destructive` | Added operation types subsection in 003 Rule 3 referencing 004's three-tier system. | 003 |
| 6 | Config file: `action_allowlist.yml` (003) vs `action_policy.yml` (004) | MEDIUM | 003 vs 004 | Standardized to 004: `config/action_policy.yml`. Updated all references in 003. | 003 |
| 7 | Rate limit config: separate file (003) vs inline (004) | MEDIUM | 003 vs 004 | Standardized to 004: inline per-action in `action_policy.yml`. Updated 003 Rule 7. | 003 |
| 8 | YAML field: `confirmation_required` (003) vs `requires_confirmation` (004) | LOW-MED | 003 vs 004 | Standardized to 004: `requires_confirmation`. Updated all 14 instances in 003. | 003 |
| 9 | Nonce errors: generic (003) vs granular (004) | MEDIUM | 003 vs 004 | Reconciled: granular internally (audit/logs), generic `nonce_invalid` externally (client). Added to 004 and 006. | 004, 006 |
| 10 | Global rate limits: required by 005 but missing from 004 | LOW-MED | 005 gap in 004 | Added `global_rate_limits` section to 004 policy format, validation rules, and example YAML. Cross-referenced in 005 Threat 9 and 006 Decision 7. | 004, 005, 006 |

---

## 5. Gap Analysis

Post-resolution gap check: are there rules without threats, threats without rules, or decisions without rules?

| Check | Result |
|-------|--------|
| Rules without threats | None. All 10 rules map to at least one threat. |
| Threats without rules | None. All 10 threats are mitigated by at least one rule. |
| Decisions without rules | None. All 8 decisions implement at least one rule. |
| Actions without full rule coverage | None. All 19 actions are covered by the applicable rule set. |
| Unresolved inconsistencies | None. All 10 identified inconsistencies are resolved and documented above. |

---

## 6. Config Artifact Reference

| Artifact | Path | Tracked in Git | Purpose |
|----------|------|---------------|---------|
| Policy template | `config/action_policy.yml.example` | Yes | Complete 19-action policy template with all required sections |
| Operator policy | `config/action_policy.yml` | No (`.gitignore`) | Operator's customized policy — copied from `.example` |
| Policy spec | `000-docs/004-TQ-STND-mutation-policy.md` | Yes | Canonical format specification, validation rules, operator workflows |
