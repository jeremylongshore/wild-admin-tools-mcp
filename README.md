# wild-admin-tools-mcp

**Governed administrative operations for Rails applications via MCP**

Part of the **[wild ecosystem](https://github.com/intent-solutions-io/wild-rails-ai-ops)** — 10 Ruby gems for running AI agents inside Rails apps under capability control.

## Mission

`wild-admin-tools-mcp` provides safe, audited administrative operations for live Rails applications via MCP. It gives AI agents and authorized operators the ability to manage background jobs, cache, and feature flags — with mandatory dry-run previews, two-phase confirmation for destructive actions, before/after audit snapshots, and enforced blast radius caps.

This repo is the **write/admin complement** to [`wild-rails-safe-introspection-mcp`](https://github.com/jeremylongshore/wild-rails-safe-introspection-mcp) (read-only introspection). Introspection reads; admin-tools acts. The safety boundary between them is architectural, not just policy-based.

## Status

**v1 complete — shippable.** All 10 epics closed. 439 tests, 0 failures, 0 lint offenses.

## Quick Start

```bash
# Install
gem 'wild-admin-tools-mcp', git: 'https://github.com/jeremylongshore/wild-admin-tools-mcp'
bundle install

# Configure
cp config/action_policy.yml.example config/action_policy.yml
# Edit config/action_policy.yml for your environment

# Verify
bundle exec rspec
bundle exec rubocop
```

See `000-docs/013-OD-OPNS-operator-deployment-guide.md` for full setup instructions.

## v1 Tools

| Tool | Actions | Description |
|------|---------|-------------|
| `manage_background_jobs` | 7 | Inspect, retry, discard jobs — single or batch with blast radius caps |
| `manage_cache` | 5 | Inspect keys/stats, invalidate single keys or patterns |
| `manage_feature_flags` | 7 | Read/list flags, toggle, enable/disable per actor, set percentage, delete |

**19 total actions** across 3 categories. All mutations require two-phase nonce confirmation.

## Safety Model

Every operation is governed by 10 enforceable safety rules:

1. **Mutation-bounded** — Only allowlisted actions can execute
2. **Dry-run first** — Every action supports preview mode with zero side effects
3. **Two-phase confirmation** — Mutations require explicit nonce-based confirmation
4. **Parameter validation** — Strict schema enforcement, no eval/constantize/send
5. **Action allowlist** — Configuration-driven, validated at startup
6. **Blast radius caps** — Per-action limits with hard ceilings
7. **Rate limited** — Per-caller and global rate limits
8. **Before/after snapshots** — State captured for every executed mutation
9. **Gate required** — Mandatory capability gate, fail-closed on error
10. **Audit everything** — Every invocation produces a structured audit record

Proven by 42 adversarial tests that actively try to break each safety claim. See `000-docs/012-TQ-SECU-evaluation-strategy.md`.

## Architecture

```
MCP Client → MCP Server
               ↓
           ToolHandler
               ↓
     AuthenticatedPipeline  (identity extraction, gate check)
               ↓
       AuditedPipeline      (audit record wrapping)
               ↓
        Guard::Pipeline     (allowlist, params, rate limit, blast radius, nonce)
               ↓
          Executors          (JobExecutor, CacheExecutor, FlagExecutor)
               ↓
           Adapters          (abstract interface → concrete Rails backend)
```

## Non-Goals

- Read-only introspection (that's `wild-rails-safe-introspection-mcp`)
- Arbitrary Ruby/Rails console execution
- Database migrations or schema changes
- Analytics queries or reporting
- Rails console proxying (deferred to v2 — see `000-docs/016-PP-PLAN-v2-expansion-roadmap.md`)
- User management operations (deferred to v2)

## Canonical Docs

| Doc | Description |
|-----|-------------|
| `001` | Repo blueprint — mission, vision, safety model |
| `002` | 10-epic build plan |
| `003` | Safety model — 10 enforceable rules |
| `004` | Mutation policy — action allowlist format |
| `005` | Threat model — 10 threats with mitigations |
| `012` | Evaluation strategy — adversarial test coverage map |
| `013` | Operator deployment guide |
| `014` | Configuration reference |
| `015` | Operator workflow guide |

Full index: `000-docs/000-INDEX.md`

## Ecosystem

| Repo | Relationship |
|------|-------------|
| `wild-rails-safe-introspection-mcp` | Read-only companion — shares MCP patterns, not code |
| `wild-capability-gate` | Mandatory runtime dependency — gates all operations |

## Development

```bash
bundle install                    # Install dependencies
bundle exec rspec                 # Run tests (439 examples)
bundle exec rspec spec/safety/    # Run adversarial safety suite (42 examples)
bundle exec rubocop               # Lint (91 files)
```

For local development with a sibling `wild-capability-gate` checkout:

```bash
USE_LOCAL_CAPABILITY_GATE=true bundle install
```

## License

Intent Solutions Proprietary. See `LICENSE`.
