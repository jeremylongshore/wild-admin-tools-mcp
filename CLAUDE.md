# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** `wild-admin-tools-mcp`
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Archetype:** A — Product-Facing Operational
- **Mission:** Governed administrative operations (jobs, cache, flags) for Rails applications via MCP
- **Language:** Ruby
- **Status:** v1 complete — 439 tests, 0 failures, all 10 epics closed

## What This Repo Does

Provides a curated set of MCP tools that let AI agents and authorized operators execute governed administrative operations against live Rails applications — managing background jobs, invalidating caches, and toggling feature flags. Every operation is dry-run previewed, confirmation-gated, audit-logged with before/after state snapshots, and bounded by blast radius caps and rate limits.

## What This Repo Does NOT Do

- No read-only introspection (that's `wild-rails-safe-introspection-mcp`)
- No arbitrary Ruby/Rails console execution
- No database migrations or schema changes
- No analytics queries or reporting pipelines
- No user management operations (v2)
- No Rails console proxying (v2)
- No multi-framework support in v1 (Rails only)

## Directory Layout

```
lib/                    # Source code (Ruby convention)
  wild_admin_tools_mcp/
    executor/           # Action executor (job, cache, flag operations)
    guard/              # Mutation guard (allowlist, validation, blast radius, rate limits)
    confirmation/       # Confirmation protocol (nonce generation, validation, expiry)
    audit/              # Audit trail (before/after snapshots, mutation logging)
    identity/           # Identity extraction and capability gate integration
    server/             # MCP server layer and tool definitions
spec/                   # Tests (RSpec)
config/                 # Configuration files (action allowlist, rate limits, defaults)
000-docs/               # Canonical docs per /doc-filing
planning/               # Active planning artifacts
```

## Build Commands

```bash
bundle install          # Install dependencies (uses git-based wild-capability-gate)
bundle exec rspec       # Run test suite
bundle exec rubocop     # Lint
```

## Dependency Strategy

`wild-capability-gate` uses a dual-mode resolution in Gemfile:
- **Default (CI + production):** fetched from GitHub via git
- **Local dev:** set `USE_LOCAL_CAPABILITY_GATE=true` to use `../wild-capability-gate`

Path dependencies are never used in CI. This ensures reproducible builds everywhere.

## Testing Approach

- **RSpec** for unit and integration tests
- Tests run against a real test Rails app schema (not mocks for data access)
- Every safety claim in `003-TQ-STND-safety-model.md` must have a corresponding test
- Adversarial tests explicitly try to break safety guarantees (confirmation bypass, blast radius exceed, rate limit circumvent)
- Dry-run tests confirm preview mode never triggers side effects

## Safety Rules for Claude Code

These are non-negotiable when working in this repo:

1. **Never bypass the capability gate.** All operations require gate authorization. If the gate is unavailable, operations fail closed (denied). No stub mode. No bypass flag.
2. **Never skip dry-run support.** Every action handler must implement both preview and execute paths. Dry-run must never trigger side effects.
3. **Never skip confirmation for destructive operations.** Two-phase confirmation with server-generated nonce is mandatory for all mutating actions. No "skip confirmation" parameter.
4. **Never skip audit logging.** Every invocation — success, denial, error — must produce an audit record with before/after state snapshots for executed mutations.
5. **Never accept arbitrary code as input.** Tool parameters are data, not code. No `eval`, no `constantize`, no dynamic method dispatch on user input.
6. **Never exceed blast radius caps.** Per-action limits are enforced in code, not advisory. Hard ceilings cannot be overridden.
7. **Prefer restrictive defaults.** When uncertain between permissive and restrictive, choose restrictive. Operators expand access through configuration.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| `000-docs/001-PP-PLAN-repo-blueprint.md` | Mission, boundaries, architecture direction |
| `000-docs/002-PP-PLAN-epic-build-plan.md` | 10-epic build plan with sequencing and dependencies |
| `000-docs/003-TQ-STND-safety-model.md` | Governing safety specification — 10 enforceable rules for mutations |
| `000-docs/004-TQ-STND-mutation-policy.md` | Action allowlist format, blast radius caps, rate limits, confirmation protocol |
| `000-docs/005-AT-ADEC-threat-model.md` | 10 mutation-specific threats with mitigations |
| `000-docs/006-AT-ADEC-safety-architecture-decisions.md` | 7 safety-driven architecture decisions with rationale |
| `000-docs/012-TQ-SECU-evaluation-strategy.md` | Adversarial test coverage map and regression protocol |
| `000-docs/013-OD-OPNS-operator-deployment-guide.md` | Setup, configuration, and deployment |
| `000-docs/014-DR-REFF-configuration-reference.md` | Every parameter, type, default, and hard ceiling |
| `000-docs/015-OD-GUID-operator-workflow-guide.md` | Day-to-day operations and troubleshooting |

## Task Tracking

Uses **Beads** (`bd`). All execution tracked repo-locally.

```bash
bd ready                # Find unblocked work
bd update <id> --claim  # Claim a task
bd close <id> --reason "evidence"  # Close with evidence
bd list                 # View all tasks
```

## Before Working Here

1. Read this file completely
2. Read the ecosystem CLAUDE.md at `../CLAUDE.md`
3. Check `bd ready` for current work state
4. Read the relevant canonical doc for the active epic
5. Do not skip ahead to later epics
