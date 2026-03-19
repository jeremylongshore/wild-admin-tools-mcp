# v2 Expansion Roadmap — wild-admin-tools-mcp

**Document type:** Expansion roadmap
**Filed as:** `016-PP-PLAN-v2-expansion-roadmap.md`
**Status:** Planning
**Last updated:** 2026-03-19

---

## Purpose

This document defines the expansion direction for wild-admin-tools-mcp beyond v1. v1 shipped with 3 MCP tools, 19 actions (8 read, 7 mutate, 4 mutate_destructive), a full safety model (10 rules), threat model (10 threats), adversarial test suite (439 tests, 42 safety-specific), and mandatory capability gate integration. This roadmap identifies what comes next, prioritized by value and safety risk.

---

## 1. Console Proxying — Highest-Risk v2 Feature

### What it is

Governed, sandboxed Rails console access via MCP. A caller submits a Ruby expression; the server evaluates it within a constrained sandbox and returns the output. Unlike the v1 action model (curated operations with fixed parameter schemas), console proxying accepts arbitrary Ruby as input.

### Why it is dangerous

Console proxying is the single highest-risk feature this ecosystem could ship. The v1 safety model rests on the structural impossibility of arbitrary execution — safety rule 4 prohibits accepting code as input, and safety defect condition 10.7 classifies any code-as-input path as a safety defect. Console proxying directly contradicts this foundation.

Specific dangers:

- **Arbitrary Ruby execution.** Even sandboxed, Ruby's reflective capabilities (`send`, `eval`, `const_get`, `ObjectSpace`, `Kernel.exec`) make containment difficult. A sandbox escape grants full application-level access.
- **Output exfiltration.** Console output may contain PII, secrets, database credentials, or environment variables. Returning raw output to the caller bypasses every data-access control in the host application.
- **Write detection is unreliable.** Distinguishing read-only Ruby from mutating Ruby through static analysis is unsolvable in the general case. A sandboxed read can trigger callbacks, observers, or lazy-loaded associations that perform writes.
- **Timeout enforcement gaps.** Ruby threads can be interrupted, but native extensions (C libraries, system calls) may not honor timeout signals. A malicious or poorly written expression can hang the server.

### Required safety controls before implementation

1. **Sandboxed execution environment.** Evaluation occurs in an isolated context with restricted constant access, no `Kernel` methods (`system`, `exec`, `open`, `fork`), no `ObjectSpace`, no `send`/`public_send` on arbitrary receivers, no file or network I/O. The sandbox must be a deny-by-default allowlist, not a blocklist.
2. **Output sanitization.** All output is passed through a sanitizer that redacts patterns matching known secret formats (API keys, tokens, passwords, connection strings). Raw ActiveRecord attribute dumps are redacted to show only non-sensitive columns defined in an output allowlist.
3. **Write detection.** Static analysis (AST inspection of the parsed Ruby) rejects expressions containing known mutation methods (`save`, `update`, `delete`, `destroy`, `create`, `execute`, database adapter write methods). This is a best-effort heuristic, not a guarantee.
4. **Timeout enforcement.** Hard timeout (configurable, default 5 seconds, ceiling 30 seconds) with `Timeout.timeout` and a process-level watchdog. Expressions exceeding the timeout are killed and logged.
5. **Command allowlist/denylist.** A curated allowlist of permitted method calls (e.g., `.find`, `.where`, `.count`, `.pluck`) and a denylist of prohibited patterns (e.g., regex matching `system\(`, `exec\(`, `eval\(`). The denylist is defense-in-depth; the sandbox is the primary control.
6. **Capability gate escalation tier.** Console proxying requires an elevated capability level: `admin_tools.console.*` (separate from `admin_tools.*`). The gate must support tiered authorization so that standard admin_tools callers cannot access console proxying without explicit escalation grants.
7. **Enhanced audit.** Full command text is captured in the audit record (sanitized for output, but preserved for forensics). Console output is captured and stored alongside the command. Before/after state capture is not feasible for arbitrary expressions, so the audit record captures: command text, output text, execution duration, sandbox violations (if any), and write-detection results.
8. **Blast radius concept for console.** Bounded by timeout (max execution duration) and resource limits (max memory allocation, max output size). There is no "affected count" analog for arbitrary expressions, so blast radius is measured in resource consumption rather than record count.

### Pre-implementation requirements

Before any console proxying code is written:

1. Dedicated safety analysis document in `000-docs/` — a full threat model specific to console proxying, covering sandbox escape, output exfiltration, write-through-read, timeout evasion, and resource exhaustion.
2. Threat model update — add console-specific threats to 005-AT-ADEC, or create a companion document.
3. New adversarial test suite — tests specifically targeting sandbox escape (reflection, `const_get`, `ObjectSpace`, `Binding`), output exfiltration (environment variables, database credentials in output), and timeout evasion (infinite loops, native extension hangs).
4. Gate escalation tier implementation — `wild-capability-gate` must support tiered capabilities before console proxying can be gated.

### Risk assessment

Console proxying may not be implementable safely. The sandbox-escape attack surface in Ruby is large, and the value of governed console access must be weighed against the risk of a sandbox breach granting unrestricted application access. It is possible that the safety analysis will conclude this feature should not ship.

---

## 2. v2 Tool Candidates

Each candidate is assessed for safety impact independently.

### 2.1 User Management Operations

**Actions:** Create user, suspend user, reactivate user, delete user, modify user attributes.

**Safety review:**
- **Sensitivity: High.** User operations involve PII (names, emails, phone numbers), are subject to legal/regulatory requirements (GDPR right to deletion, data retention laws), and have compliance implications (audit requirements for user lifecycle changes).
- **Blast radius:** Single-user operations have blast radius 1, but bulk operations (suspend all users matching criteria) carry the same batch risks as v1 job operations.
- **Before/after snapshots:** Must capture user state without storing PII in the audit trail. Snapshots must hash or redact sensitive fields. The snapshot schema requires a dedicated design to balance forensic value against privacy requirements.
- **Confirmation:** All user mutations require two-phase confirmation. User deletion requires elevated gate permissions and an extended confirmation warning.
- **Gate policy:** Requires its own capability namespace: `admin_tools.user_management.*`. User deletion requires `admin_tools.user_management.delete` with explicit grant — not inherited from a wildcard.
- **Pre-implementation:** Legal review of audit data retention for user lifecycle events. Privacy impact assessment for before/after snapshot content.

### 2.2 Audit Log Lifecycle Management

**Actions:** Query audit log (time range, caller, action), export audit records, configure retention policy, rotate log files.

**Safety review:**
- **Sensitivity: Medium.** Audit logs contain operational data (who did what, when) but not direct PII (v1 sanitizes parameters). The primary risk is allowing callers to delete or modify audit records, which undermines the append-only guarantee.
- **Non-negotiable constraint:** No action in this category may delete, modify, or truncate audit records through the MCP interface. Export and query are read-only. Retention and rotation are operator-level configuration changes, not runtime mutations.
- **Gate policy:** Read-only audit queries use `admin_tools.audit.read`. Export uses `admin_tools.audit.export`. Retention configuration (if exposed at all) uses `admin_tools.audit.configure` with elevated gate requirements.
- **Risk:** Low for read/export. Medium for retention configuration (misconfiguration could cause premature data loss).

### 2.3 Deployment Status Inspection

**Actions:** Read current deployment version, read deployment history, read deployment health checks.

**Safety review:**
- **Sensitivity: Low.** All operations are read-only. No mutations.
- **Risk:** Minimal. Information exposure risk is bounded — deployment metadata is not secrets. Rate limiting prevents enumeration.
- **Gate policy:** `admin_tools.deployment.read`.
- **Implementation cost:** Low. Adapter interface against deployment metadata (Capistrano revision files, Docker labels, environment variables).

### 2.4 Rake Task Execution

**Actions:** List available rake tasks, execute a named rake task with arguments.

**Safety review:**
- **Sensitivity: High.** Rake tasks are arbitrary code. `rake db:drop`, `rake db:seed`, `rake data:migrate` can all cause catastrophic damage. This is effectively console proxying with a different surface syntax.
- **Non-negotiable constraint:** Only explicitly allowlisted rake tasks may be executed. The allowlist is configuration-driven, not discovered at runtime. The task allowlist is separate from the action allowlist and requires its own safety analysis.
- **Sandboxing:** Same sandbox requirements as console proxying. Rake tasks run in the full application context and can do anything the application can do.
- **Risk:** High. Rake task execution requires the same level of safety analysis as console proxying. It should not be implemented before console proxying's safety analysis is complete, because the attack surfaces overlap.
- **Recommendation:** Defer until after console proxying safety analysis. If console proxying is deemed too risky, rake task execution is also too risky.

---

## 3. Cross-Repo Dependency Updates for v2

### What admin-tools-mcp provides to the ecosystem

| Artifact | Consumer | Description |
|----------|----------|-------------|
| Mutation audit record format | wild-session-telemetry | Structured JSON audit records (Record schema from `Audit::Record`) that telemetry can ingest as usage events. The format is stable as of v1 and documented in 008-AT-ADEC. |
| Tool catalog | wild-skillops-registry | The 3-tool, 19-action catalog with parameter schemas, operation types, and safety classifications. Registry can import this as a versioned capability manifest. |
| Action execution patterns | wild-session-telemetry, wild-gap-miner | Which actions are invoked, denied, previewed, and confirmed — raw signal for usage analysis and gap detection. |

### What admin-tools-mcp needs from the ecosystem

| Dependency | Provider | Required for | Status |
|------------|----------|-------------|--------|
| Capability gate escalation tiers | wild-capability-gate | Console proxying and user management. Current gate evaluates `admin_tools.*` as a flat namespace. v2 features require tiered capabilities (e.g., `admin_tools.console.*` as an elevated tier above `admin_tools.jobs.*`). | Not yet implemented in gate. |
| Telemetry emission interface | wild-session-telemetry | Emitting usage events (action invoked, action denied, confirmation abandoned) to the telemetry pipeline. See 018-AT-ADEC for the proposed hook interface. | Interface defined (018), not yet wired. Awaiting wild-session-telemetry. |
| Gap analysis input format | wild-gap-miner | Feeding action patterns (most-invoked actions, most-denied actions, confirmation abandonment rates) into gap analysis for product prioritization. | Not yet specified. Depends on wild-gap-miner repo entering active development. |

### Dependency sequencing

1. **Gate escalation tiers** must be implemented in wild-capability-gate before console proxying or user management work begins in admin-tools-mcp.
2. **Telemetry emission** can be wired incrementally — the hook interface (018) is designed to be optional, so admin-tools-mcp can ship v2 features before telemetry is ready.
3. **Gap analysis** is a downstream consumer, not a blocker. Admin-tools-mcp does not need to wait for wild-gap-miner.

---

## 4. v2 Prioritization

| Priority | Feature | Rationale |
|----------|---------|-----------|
| 1 | Deployment status inspection | Low risk, low effort, immediate value for operational context |
| 2 | Audit log query/export | Medium risk (read-only), fills a real gap in audit usability |
| 3 | User management operations | High value but requires legal/privacy review |
| 4 | Console proxying safety analysis | Highest risk, requires dedicated safety work before any code |
| 5 | Rake task execution | Blocked by console proxying safety analysis (overlapping attack surface) |
