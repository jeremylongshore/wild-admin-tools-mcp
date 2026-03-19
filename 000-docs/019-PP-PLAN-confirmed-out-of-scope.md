# Confirmed Out-of-Scope — wild-admin-tools-mcp

**Document type:** Planning document
**Filed as:** `019-PP-PLAN-confirmed-out-of-scope.md`
**Status:** Active
**Last updated:** 2026-03-19

---

## Purpose

This document codifies what wild-admin-tools-mcp will not do. It distinguishes between permanently excluded features (architectural constraints that define what this repo is not), features deferred to v2 (valuable but not yet safe or scoped enough to ship), and features that belong in other repos in the wild ecosystem. This is a durable reference for scope decisions, not a wishlist.

---

## 1. Permanently Out of Scope

These features are excluded by design. They contradict the repo's safety model, architectural boundaries, or mission. They will not be added in any version without a fundamental re-evaluation of what this repo is.

### Arbitrary Ruby execution without sandbox

Accepting arbitrary Ruby code as input and executing it without a dedicated sandbox environment violates safety rule 4 (parameter validation — no code as input) and safety defect condition 10.7. The entire v1 safety model rests on the structural impossibility of arbitrary execution. If console proxying is ever added (see v2 deferred list), it requires a dedicated sandbox with its own safety analysis. Unsandboxed execution is permanently excluded.

### Database migrations or schema changes

Running ActiveRecord migrations, executing DDL (`CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`), or modifying database schema through the MCP interface. Migrations have their own tooling, review workflows, and deployment pipelines. Exposing migration execution through an MCP server creates unbounded risk (a migration can drop tables, alter columns, or corrupt referential integrity) with minimal incremental value over existing migration tooling. Schema changes are not administrative operations; they are deployment operations.

### Analytics queries or reporting pipelines

Aggregation queries, time-series analysis, job failure rate dashboards, cache hit-rate reports, or any statistical analysis over populations of resources. The tools answer operational questions about specific resources ("what is the state of this job?"), not statistical questions about populations ("how many jobs failed last month?"). Analytics belongs in dedicated data infrastructure, not in an MCP server optimized for governed mutation.

### Multi-tenant routing or SaaS features

Routing requests to different tenant databases, tenant-scoped configuration, or any multi-tenancy logic within the MCP server itself. Admin-tools-mcp operates against a single Rails application's backend services. Tenant isolation is the host application's responsibility. The MCP server does not interpret, enforce, or route based on tenant identity.

### Dynamic tool generation or plugin marketplace

Loading tool definitions from external sources at runtime, user-uploaded tool definitions, or a plugin system that adds actions without configuration changes and server restarts. The action allowlist is static, loaded at startup, and immutable at runtime (safety rule 1, safety rule 5). Dynamic tool registration is incompatible with the safety model's requirement that the set of possible operations is known, reviewed, and fixed before the server accepts requests.

### Streaming responses

Streaming partial results back to the client during execution (e.g., streaming individual job retry results as they complete). The MCP protocol and the two-phase confirmation flow both assume request-response semantics. The audit record captures the complete result of an action, not a stream of intermediate states. Streaming introduces partial-result complexity (what if the stream is interrupted mid-mutation?) without clear value for the bounded batch sizes enforced by blast radius caps.

### Direct database access

Executing raw SQL queries, reading or writing directly to the application's database through the MCP server. All data access is mediated through adapters that use the application's domain model (ActiveRecord, Sidekiq API, Rails cache interface, Flipper API). Direct database access bypasses application-level validations, callbacks, and access controls. It is the admin-tools equivalent of giving someone a database password instead of an application login.

---

## 2. Deferred to v2

These features are valuable and may eventually ship, but require additional safety analysis, ecosystem dependencies, or design work that exceeds v1 scope. Deferral is not permanent exclusion — each item has specific conditions for re-evaluation.

### Rails console proxying

Governed, sandboxed Rails console access via MCP. The single highest-risk feature this ecosystem could ship. Requires: sandboxed execution environment with deny-by-default allowlist, output sanitization, write detection (best-effort), timeout enforcement, command allowlist/denylist, elevated capability gate tier, enhanced audit with full command/output capture. Requires a dedicated safety analysis document and threat model update before any code is written. See 016-PP-PLAN-v2-expansion-roadmap.md for full requirements.

**Condition for re-evaluation:** Dedicated safety analysis complete; capability gate escalation tiers available in wild-capability-gate; adversarial test plan for sandbox escape scenarios written and reviewed.

### User management operations

Create, suspend, reactivate, delete users. High sensitivity due to PII, legal/regulatory requirements (GDPR, data retention), and compliance implications. Requires: PII-safe before/after snapshot schema, dedicated gate capability namespace (`admin_tools.user_management.*`), privacy impact assessment, legal review of audit data retention requirements.

**Condition for re-evaluation:** Privacy impact assessment complete; legal review of audit retention for user lifecycle events; gate capability namespace implemented.

### Audit log lifecycle management

Query, export, and configure retention for audit records. Read/export operations are low-risk. Retention configuration carries medium risk (misconfiguration could cause premature data loss). The append-only guarantee must be preserved — no action in this category may delete or modify records through the MCP interface.

**Condition for re-evaluation:** Clear distinction between read-only query (low gate tier) and retention configuration (elevated gate tier); retention configuration impact analysis.

### Rake task execution

Execute named rake tasks with arguments. Effectively console proxying with a different surface syntax — the same attack surface (arbitrary code execution in the application context). Blocked by console proxying safety analysis because the risks overlap.

**Condition for re-evaluation:** Console proxying safety analysis complete. If console proxying is deemed too risky, rake task execution is also too risky.

### Multi-application deployment

Configuring admin-tools-mcp to manage multiple Rails applications from a single server instance. Requires: per-application adapter configuration, per-application capability gate policies, per-application rate limiting, cross-application blast radius isolation. Adds significant operational complexity without clear demand in v1 use cases.

**Condition for re-evaluation:** At least two production deployments of v1 requesting multi-app support; design for cross-application isolation that maintains per-app safety guarantees.

### Cloud deployment guides

Production deployment documentation for specific cloud platforms (AWS ECS, GCP Cloud Run, Heroku, bare metal). v1 ships as a Ruby gem with local configuration. Cloud-specific deployment guides require testing against each platform's constraints and are documentation-heavy work that does not affect the core product.

**Condition for re-evaluation:** v1 in production use; operator feedback identifying deployment as a pain point.

---

## 3. Belongs in Other Repos

These features are legitimate parts of the wild ecosystem but are architecturally separated from admin-tools-mcp. Building them here would violate repo boundaries and dilute this repo's mission.

| Feature | Correct Repo | Rationale |
|---------|-------------|-----------|
| Read-only introspection (record lookup, schema inspection, ActiveRecord queries) | wild-rails-safe-introspection-mcp | The architectural separation between read and write is the primary safety boundary. Admin-tools-mcp acts on state; introspection observes state. Merging them removes the structural guarantee that the read-only server cannot mutate. |
| Authorization policy management (creating/editing capabilities, managing grants) | wild-capability-gate | The gate is admin-tools-mcp's authorization provider. Managing the gate's own policies through a tool that the gate authorizes creates a circular dependency and a privilege escalation vector ("use admin tools to grant yourself more admin tool permissions"). |
| Session telemetry collection and export | wild-session-telemetry | Admin-tools-mcp emits events (see 018-AT-ADEC); it does not collect, aggregate, store, or export them. Telemetry infrastructure is a separate operational concern with its own storage, retention, and privacy requirements. |
| Gap analysis from usage patterns | wild-gap-miner | Analyzing which actions are used, denied, or abandoned is a downstream analytics function. Admin-tools-mcp provides the raw signal (audit records, telemetry events); gap-miner interprets it. |
| Skill/tool registry and discovery | wild-skillops-registry | Admin-tools-mcp publishes its tool catalog; the registry indexes and serves it. The registry is a coordination layer across all wild repos, not a feature of any single repo. |
| Hook lifecycle management | wild-hook-ops | If admin-tools-mcp's telemetry hooks need lifecycle management (enable/disable, health monitoring), that management belongs in a dedicated ops tool, not self-referentially in admin-tools-mcp. |
| Permission model analysis and audit | wild-permission-analyzer | Analyzing the capability gate's grant structure, finding over-permissioned callers, or auditing capability drift is an analysis function, not an admin operation. |
| Test flake detection and triage | wild-test-flake-forensics | Unrelated to administrative operations. Different domain, different data sources, different users. |
