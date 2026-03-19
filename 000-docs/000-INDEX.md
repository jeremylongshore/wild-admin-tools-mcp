# 000-docs Index — wild-admin-tools-mcp

| # | File | Category | Type | Description |
|---|------|----------|------|-------------|
| 001 | 001-PP-PLAN-repo-blueprint.md | PP — Product & Planning | PLAN | Canonical repo blueprint — mission, vision, safety model, architecture direction |
| 002 | 002-PP-PLAN-epic-build-plan.md | PP — Product & Planning | PLAN | Canonical 10-epic build plan — sequenced execution story, child-task themes, dependencies |
| 003 | 003-TQ-STND-safety-model.md | TQ — Testing & Quality | STND | Safety model spec — mutation-bounded ops, dry-run enforcement, confirmation protocol, blast radius caps, rate limits, audit, defect definition |
| 004 | 004-TQ-STND-mutation-policy.md | TQ — Testing & Quality | STND | Mutation policy spec — action allowlist YAML format, blast radius caps, rate limits, confirmation requirements, nonce protocol |
| 005 | 005-AT-ADEC-threat-model.md | AT — Architecture & Technical | ADEC | Threat model — 10 mutation-specific threats with mitigations and verification requirements |
| 006 | 006-AT-ADEC-safety-architecture-decisions.md | AT — Architecture & Technical | ADEC | 8 safety-driven architecture decisions with context, rationale, and trade-off analysis |
| 007 | 007-TQ-STND-safety-cross-reference-matrix.md | TQ — Testing & Quality | STND | Safety cross-reference matrix — rule-threat-decision mapping, 19-action cross-reference, resolved inconsistencies log, gap analysis |
| 008 | 008-AT-ADEC-audit-trail-storage-decision.md | AT — Architecture & Technical | ADEC | Audit trail storage decision — JSON Lines for production, MemoryStore for tests, shared Store interface |
| 009 | 009-AT-ADEC-identity-and-auth-model.md | AT — Architecture & Technical | ADEC | Identity and auth model — SessionContext value object, IdentityExtractor, anonymous rejection |
| 010 | 010-AT-ADEC-capability-gate-integration.md | AT — Architecture & Technical | ADEC | Capability gate integration — in-process library, fail-closed, GateClient wrapper, AuthenticatedPipeline |
| 011 | 011-TQ-STND-end-to-end-validation.md | TQ — Testing & Quality | STND | End-to-end validation — confirmation flow demo script, acceptance criteria, failure indicators |
| 012 | 012-TQ-SECU-evaluation-strategy.md | TQ — Testing & Quality | SECU | Security evaluation strategy — safety rule coverage map, threat coverage, regression protocol |
| 013 | 013-OD-OPNS-operator-deployment-guide.md | OD — Operations & Deployment | OPNS | Operator deployment guide — prerequisites, installation, adapter config, server setup, production checklist |
| 014 | 014-DR-REFF-configuration-reference.md | DR — Documentation & Reference | REFF | Configuration reference — full policy YAML schema, all 19 action parameter specs, operation types, nonce protocol |
| 015 | 015-OD-GUID-operator-workflow-guide.md | OD — Operations & Deployment | GUID | Operator workflow guide — adding actions, blast radius, rate limits, audit log inspection, access revocation, troubleshooting |
| 016 | 016-PP-PLAN-v2-expansion-roadmap.md | PP — Product & Planning | PLAN | v2 expansion roadmap — console proxying safety requirements, tool candidates with safety review, cross-repo dependency updates |
| 017 | 017-AT-ADEC-architecture-extension-points.md | AT — Architecture & Technical | ADEC | Architecture extension points — adding tools, action categories, adapter backends, identity providers, audit stores, extension safety rules |
| 018 | 018-AT-ADEC-telemetry-emission-hook-interface.md | AT — Architecture & Technical | ADEC | Telemetry emission hook interface — event schema, hook points, privacy constraints, integration pattern with wild-session-telemetry |
| 019 | 019-PP-PLAN-confirmed-out-of-scope.md | PP — Product & Planning | PLAN | Confirmed out-of-scope — permanently excluded features, v2 deferrals with re-evaluation conditions, ecosystem repo boundaries |

## Category Reference

| Code | Meaning |
|------|---------|
| PP | Product & Planning |
| AT | Architecture & Technical |
| TQ | Testing & Quality |
| OD | Operations & Deployment |
| DR | Documentation & Reference |
| RL | Release |

## Type Reference

| Code | Meaning |
|------|---------|
| PLAN | Master plan / blueprint |
| ARCH | Architecture document |
| ADEC | Architecture decision record |
| STND | Standard / policy |
| SECU | Security evaluation / protocol |
| GUID | Workflow / operator guide |
| OPNS | Operations / deployment guide |
| REFF | Reference document |
| REPT | Release report |
