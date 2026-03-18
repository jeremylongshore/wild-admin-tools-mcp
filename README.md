# wild-admin-tools-mcp

**Governed administrative operations for Rails applications via MCP**

Part of the [wild](https://github.com/jeremylongshore) ecosystem — the operational intelligence layer for AI-assisted Rails development.

## Mission

`wild-admin-tools-mcp` provides safe, audited administrative operations for live Rails applications via MCP. It gives AI agents and authorized operators the ability to manage background jobs, cache, and feature flags — with mandatory dry-run previews, two-phase confirmation for destructive actions, before/after audit snapshots, and enforced blast radius caps.

This repo is the **write/admin complement** to [`wild-rails-safe-introspection-mcp`](https://github.com/jeremylongshore/wild-rails-safe-introspection-mcp) (read-only introspection). Introspection reads; admin-tools acts. The safety boundary between them is architectural, not just policy-based.

## Status

**Phase 0 — Planning and scaffolding.** No application code exists yet.

- Repo blueprint: complete
- Safety model: complete
- Threat model: complete
- 10-epic build plan: complete
- Beads initialized: complete
- Implementation: not started

## Planned v1 Tools

| Tool | Category | Description |
|------|----------|-------------|
| `manage_background_jobs` | Jobs | Inspect, retry, discard background jobs (Sidekiq/GoodJob) |
| `manage_cache` | Cache | Inspect cache keys/stats, invalidate specific keys or patterns |
| `manage_feature_flags` | Flags | Read flag state, toggle flags with confirmation |

## Safety Model

Every operation in this repo is governed by a mutation-aware safety model:

1. **Mutation-bounded** — Only allowlisted actions can execute
2. **Dry-run first** — Every action supports preview mode
3. **Two-phase confirmation** — Destructive actions require explicit nonce-based confirmation
4. **Before/after audit** — State snapshots recorded for every mutation
5. **Gate-required** — Mandatory capability gate integration (not stubbed)
6. **Blast radius caps** — Per-action limits on affected resources
7. **Rate limited** — Per-caller, per-category mutation throttling

See `000-docs/003-TQ-STND-safety-model.md` for the full governing specification.

## Non-Goals

- Read-only introspection (that's `wild-rails-safe-introspection-mcp`)
- Arbitrary Ruby/Rails console execution
- Database migrations or schema changes
- Analytics queries or reporting
- Rails console proxying (deferred to v2)
- User management operations (deferred to v2)

## Canonical Docs

| Doc | Description |
|-----|-------------|
| `000-docs/001-PP-PLAN-repo-blueprint.md` | Mission, vision, architecture, safety model overview |
| `000-docs/002-PP-PLAN-epic-build-plan.md` | 10-epic build plan with sequencing and dependencies |
| `000-docs/003-TQ-STND-safety-model.md` | Governing safety specification — 10 enforceable rules |
| `000-docs/004-TQ-STND-mutation-policy.md` | Action allowlist format, blast radius, rate limits |
| `000-docs/005-AT-ADEC-threat-model.md` | 10 mutation-specific threats with mitigations |
| `000-docs/006-AT-ADEC-safety-architecture-decisions.md` | 7 architecture decisions with rationale |

## Ecosystem

| Repo | Relationship |
|------|-------------|
| `wild-rails-safe-introspection-mcp` | Read-only companion — shares MCP patterns, not code |
| `wild-capability-gate` | Mandatory runtime dependency — gates all operations |

## License

Intent Solutions Proprietary. See `LICENSE`.
