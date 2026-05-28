# 020-AT-AUDT — Operator-Grade System Audit, 2026-05-28

**Subject:** `wild-admin-tools-mcp` v1 (Ruby gem, 42 source files, 2,245 LoC, 439 specs)
**Audience:** Senior Rails/Ruby engineer reading the repo for the first time
**Goal:** Functional understanding in ten minutes; operable under stress.
**Reference frame:** `lib/`, `spec/`, `config/`, and `000-docs/` (ADRs 003-019) as of HEAD on `feat/epic8-adversarial-bz3.2-bz3.6`.

---

## 1. Mission and boundaries

`wild-admin-tools-mcp` is a Ruby gem that exposes a [Model Context Protocol](https://modelcontextprotocol.io/) server providing **governed administrative operations against a live Rails application**. AI agents (or human operators behind an MCP client) get exactly three tools — `manage_background_jobs`, `manage_cache`, `manage_feature_flags` — registered as a frozen list in [`lib/wild_admin_tools_mcp/server/server_factory.rb:6-10`](../lib/wild_admin_tools_mcp/server/server_factory.rb). Across those three tools the gem fans out to 19 named actions (8 read, 7 mutate, 4 mutate-destructive) declared in [`config/action_policy.yml.example`](../config/action_policy.yml.example).

The gem is the **write/admin complement** to its read-only sibling `wild-rails-safe-introspection-mcp`. That split is structural, not stylistic: this codebase carries the entire two-phase nonce machinery, blast-radius enforcement, before/after snapshot capture, and mandatory capability-gate integration. The introspection sibling shares neither code nor runtime dependencies with this gem — only conventions, by deliberate decision in [`000-docs/006-AT-ADEC-safety-architecture-decisions.md:114-133`](006-AT-ADEC-safety-architecture-decisions.md) (Decision 4).

**What this gem does:**

- Registers `manage_background_jobs`, `manage_cache`, `manage_feature_flags` as `MCP::Tool` subclasses ([`lib/wild_admin_tools_mcp/server/tools/`](../lib/wild_admin_tools_mcp/server/tools/)).
- Runs every invocation through a five-stage pipeline: identity extraction, capability-gate evaluation, audit recording, guard checks (allowlist, parameter validation, rate limit, blast radius, nonce), and finally the executor.
- Captures structured before/after state snapshots for every mutation via [`lib/wild_admin_tools_mcp/executor/state_capture.rb`](../lib/wild_admin_tools_mcp/executor/state_capture.rb).
- Emits append-only JSON Lines audit records ([`lib/wild_admin_tools_mcp/audit/store.rb:54-111`](../lib/wild_admin_tools_mcp/audit/store.rb)).

**What this gem explicitly does not do** (see [`000-docs/019-PP-PLAN-confirmed-out-of-scope.md`](019-PP-PLAN-confirmed-out-of-scope.md) and the README "Non-Goals" block):

- No read-only introspection. That is the sibling repo's job.
- No arbitrary Ruby evaluation, no Rails console proxying, no rake-task execution. Safety rule 4 in [`000-docs/003-TQ-STND-safety-model.md`](003-TQ-STND-safety-model.md) forbids accepting code as input; the v2 roadmap in [`016-PP-PLAN-v2-expansion-roadmap.md`](016-PP-PLAN-v2-expansion-roadmap.md) explicitly classifies console proxying as the highest-risk feature the ecosystem could ship.
- No DB migrations, no schema changes, no user-management mutations, no analytics queries.
- No multi-framework support — Rails-only in v1, by configuration choice rather than hard dependency.
- No infrastructure operations (deploy, restart, scale) — the action allowlist in `config/action_policy.yml.example` simply does not name them.

The gem is intentionally narrow: it solves *governed mutation of three resource classes that Rails operators routinely touch* — failed jobs, cached values, and feature flags — and then stops. Every constraint is enforced at multiple layers; nothing about the safety model is advisory.

---

## 2. MCP server architecture

The MCP server itself is a thin facade. Almost all the interesting code is in the pipeline stack the server delegates to.

### Tool registration and dispatch

Tools register as static `MCP::Tool` subclasses. [`lib/wild_admin_tools_mcp/server/tools/manage_background_jobs.rb`](../lib/wild_admin_tools_mcp/server/tools/manage_background_jobs.rb) is the prototype: it declares `tool_name`, a free-text `description`, a JSON-Schema `input_schema` whose `action` enum lists the seven background-job actions, and `annotations(read_only_hint: false, destructive_hint: true)`. The class method `call(action:, server_context: nil, nonce: nil, **params)` forwards everything to [`ToolHandler.execute`](../lib/wild_admin_tools_mcp/server/tool_handler.rb):

```ruby
ToolHandler.execute(action_name: action, params: params.compact,
                    server_context: server_context, nonce: nonce)
```

This is the seam: the MCP SDK does the wire-level work (tool listing, JSON-Schema validation of inputs, response framing). The gem's job is to take a validated `(action, params, nonce)` triple, look up the `pipeline` instance in `server_context`, run it, and convert the `Result` value object into an `MCP::Tool::Response` body.

### Pipeline construction

The pipeline is wired top-down in [`ServerFactory.build_pipeline`](../lib/wild_admin_tools_mcp/server/server_factory.rb#L21-L36):

| Layer | Class | Responsibility |
|-------|-------|----------------|
| 1. Identity | `Identity::AuthenticatedPipeline` | Extract `caller_id`, reject anonymous, call gate, deny on gate failure |
| 2. Audit | `Audit::AuditedPipeline` | Wrap inner pipeline with `Audit::Recorder.record { … }` |
| 3. Guard | `Guard::Pipeline` | Allowlist → param validate → rate limit → blast radius → nonce |
| 4. Executor | `Executor::JobExecutor` / `CacheExecutor` / `FlagExecutor` | Adapter calls + snapshot capture |
| 5. Adapter | `Executor::Adapters::*` | Host-app implementations (Sidekiq, Rails.cache, Flipper) |

Layers compose by constructor injection; each outer layer holds a reference to the next via instance variables (`@audited_pipeline`, `@pipeline`, `@executors`). The build order in `ServerFactory` is fixed: guard → audited → authenticated. Executors are registered after construction via `register_executor`, which delegates downward until it reaches `Guard::Pipeline#register_executor`, where each executor's action names are folded into `@executors`.

### Transport

Transport is decoupled from the gem. The bundled `exe/wild-admin-tools-mcp` script ([`exe/wild-admin-tools-mcp:1-28`](../exe/wild-admin-tools-mcp)) uses `MCP::Server::Transports::StdioTransport` — appropriate for local Claude Code clients spawning the gem as a subprocess over stdio. Nothing in `lib/` references the transport; any MCP-compatible transport (HTTP, SSE, WebSocket) can replace it by editing the bin script. The server itself is constructed via [`MCP::Server.new`](../lib/wild_admin_tools_mcp/server/server_factory.rb#L13-L18) with the static `TOOLS` array and the per-invocation `server_context`.

### Response shape

[`ResponseFormatter`](../lib/wild_admin_tools_mcp/server/response_formatter.rb) is the only place that knows the wire shape. It pattern-matches on `result.status` (`:success`, `:preview`, `:denied`, `:error`) and emits one of four hash shapes (lines 44-80). Importantly, `denied?` and `error?` both flip the `error:` flag on the `MCP::Tool::Response` so MCP clients can short-circuit normally. The body is duplicated as both `text` content (a JSON string) and `structured_content` (a hash) — the structured form is what every spec asserts against.

### What lives in `Configuration`

[`WildAdminToolsMcp::Configuration`](../lib/wild_admin_tools_mcp/configuration.rb) is a small mutable object accessible via the module-level `WildAdminToolsMcp.configure { |c| … }` block (see [`lib/wild_admin_tools_mcp.rb:42-55`](../lib/wild_admin_tools_mcp.rb)). It stores the three required adapters (`job_adapter`, `cache_adapter`, `flag_adapter`), the gate, the policy path, and the audit store. `validate!` raises `ConfigurationError` if any of the three adapters are nil. Nothing else in the gem touches `Configuration` mutably — every other component receives its dependencies via constructor injection from `ServerFactory`.

---

## 3. The critical path

Trace a single `retry_job` invocation end-to-end. This is the canonical mutate path and exercises every layer except blast-radius-exceeded.

**Step 1 — MCP client sends `manage_background_jobs(action: "retry_job", job_id: "abc-123")`** with no nonce. The MCP SDK validates input against the JSON Schema in [`ManageBackgroundJobs.input_schema`](../lib/wild_admin_tools_mcp/server/tools/manage_background_jobs.rb#L14-L31). Validation only catches structural problems (wrong type, missing required `action`); content rules belong to the guard layer.

**Step 2 — `ManageBackgroundJobs.call` → `ToolHandler.execute`** ([`tool_handler.rb:6-17`](../lib/wild_admin_tools_mcp/server/tool_handler.rb)). The handler pulls `pipeline`, `caller_id`, and `caller_type` from `server_context`, builds a `request_context`, and calls `pipeline.call(action_name, params, request_context, nonce: nil)`.

**Step 3 — `AuthenticatedPipeline#call`** ([`authenticated_pipeline.rb:12-25`](../lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb)). `IdentityExtractor#extract` ([`identity_extractor.rb:6-18`](../lib/wild_admin_tools_mcp/identity/identity_extractor.rb)) returns a `SessionContext` Data object. If `session.anonymous?`, the pipeline immediately calls `deny_with_audit(... 'anonymous_request_rejected')` and returns. Otherwise `authorize_via_gate(session, action_name, params)` runs.

**Step 4 — `GateClient#authorize`** ([`gate_client.rb:10-26`](../lib/wild_admin_tools_mcp/identity/gate_client.rb)). The gate is called with `capability: :"admin_tools.retry_job"`. The `:admin_tools.` namespace is the integration contract with `wild-capability-gate`. Any `StandardError` is re-wrapped as `GateError`; the `AuthenticatedPipeline` catches `GateError` and downgrades the session to gate_result `'denied'`. **Fail-closed**: gate exceptions never bypass authorization.

**Step 5 — `AuditedPipeline#call`** wraps the next call in `Audit::Recorder.record { … }` ([`audited_pipeline.rb:13-23`](../lib/wild_admin_tools_mcp/audit/audited_pipeline.rb)). The recorder sanitizes params (redacting secrets, SHA256-hashing the `job_id` per [`parameter_sanitizer.rb:11-23`](../lib/wild_admin_tools_mcp/audit/parameter_sanitizer.rb)), captures wall-clock duration, and runs the yielded block. Whatever `Result` comes back, the recorder builds an `Audit::Record` and `@store.append`s it.

**Step 6 — `Guard::Pipeline#call`** uses `catch(:result)` ([`pipeline.rb:18-20`](../lib/wild_admin_tools_mcp/guard/pipeline.rb)) so any guard layer can `throw :result, Result.new(status: :denied, …)` and skip the remaining stages cleanly. Order is fixed: `check_allowlist!` → `check_params!` → `check_rate_limit!` → `find_executor!` → `route_action`. For `retry_job` (operation `mutate`), with no nonce, `route_action` falls through to `preview_mutation`.

**Step 7 — Preview** runs blast-radius check (estimated count = 1 for `retry_job`), then `TwoPhaseFlow#preview_with_nonce` ([`two_phase_flow.rb:12-22`](../lib/wild_admin_tools_mcp/guard/two_phase_flow.rb)) calls `executor.preview` and generates a nonce via `NonceManager#generate` ([`nonce_manager.rb:26-38`](../lib/wild_admin_tools_mcp/guard/nonce_manager.rb)). The nonce is cryptographically bound to a SHA256 hash of `(action_name | sorted_params | caller_id)`, stored with a TTL (clamped 10-120 s), and returned in `result.metadata[:nonce]`. The pipeline returns a `Result.new(status: :preview, …)` which the audit layer records as `phase: 'preview'`.

**Step 8 — Client re-sends with `nonce: "wnc_…"`.** Steps 2-6 re-run. This time `route_action` takes the `execute_with_nonce` branch. `NonceManager#validate_and_consume!` ([`nonce_manager.rb:40-56`](../lib/wild_admin_tools_mcp/guard/nonce_manager.rb)) checks the nonce exists, is not expired, is not already consumed, and that action/identity/parameters still match. On any mismatch, the client sees only `'nonce_invalid'`; the internal reason (`nonce_action_mismatch`, `nonce_parameter_mismatch`, …) is in the audit record only (Decision 8 in [`006-AT-ADEC`](006-AT-ADEC-safety-architecture-decisions.md)). Successful validation consumes the nonce single-use, then `executor.execute` runs. `Executor::Base#execute` ([`base.rb:27-40`](../lib/wild_admin_tools_mcp/executor/base.rb)) calls `run_with_snapshots` — capture before, call adapter's `retry_job!`, capture after — and returns a `Result.new(status: :success, before_snapshot: …, after_snapshot: …)`. `ResponseFormatter.success_hash` ships both snapshots back to the client and the audit record persists them under `before_snapshot`/`after_snapshot`.

---

## 4. Capability-gate integration

The integration is a thin Ruby-level boundary; there is no IPC or HTTP layer. From the Gemfile ([`Gemfile:7-13`](../Gemfile)):

```ruby
if ENV['USE_LOCAL_CAPABILITY_GATE'] == 'true'
  gem 'wild-capability-gate', path: '../wild-capability-gate'
else
  gem 'wild-capability-gate',
      git: 'https://github.com/jeremylongshore/wild-capability-gate',
      branch: 'main'
end
```

The gem is required at runtime — declared in the gemspec ([`wild-admin-tools-mcp.gemspec:22`](../wild-admin-tools-mcp.gemspec)) as `add_dependency 'wild-capability-gate', '~> 0.1'`. The host application instantiates a gate object and assigns it via `WildAdminToolsMcp.configure { |c| c.gate = MyGate.new }`. From there, `GateClient` is the *only* consumer; everything funnels through `gate.evaluate(caller:, capability:, context:)` and inspects `result.allowed?`.

| Concern | Where it lives | Behavior |
|---------|---------------|----------|
| Namespace contract | [`gate_client.rb:13`](../lib/wild_admin_tools_mcp/identity/gate_client.rb) | All capabilities are `:"admin_tools.#{action_name}"` |
| Gate-nil failure | [`gate_client.rb:11`](../lib/wild_admin_tools_mcp/identity/gate_client.rb) | Raises `GateError, 'Gate is not configured'` |
| Unexpected exception | [`gate_client.rb:24-25`](../lib/wild_admin_tools_mcp/identity/gate_client.rb) | Re-wrapped as `GateError` carrying `original_error` |
| Outer catch | [`authenticated_pipeline.rb:33-37`](../lib/wild_admin_tools_mcp/identity/authenticated_pipeline.rb) | `rescue GateError` → `session.with_gate_result('denied')` |
| Health probe | [`gate_health_check.rb:10-26`](../lib/wild_admin_tools_mcp/identity/gate_health_check.rb) | Synthetic capability evaluation; a *denied* response is healthy, only exceptions are unhealthy |

The adversarial spec [`spec/safety/gate_failure_spec.rb`](../spec/safety/gate_failure_spec.rb) is the readable contract. Three branches matter for an on-call engineer:

- **Gate explicitly denies** (line 34-46) → response `status: 'denied'`, `reason: 'gate_denied'`, audit record created.
- **Gate raises `GateError`** simulating timeout (line 48-63) → identical response, identical audit.
- **Gate raises arbitrary `StandardError`** (line 65-80) → identical response, identical audit. This is the "the gate gem crashed inside its own `evaluate`" branch — bug, deploy mismatch, anything — and the contract is the same: deny-and-audit.

The uniform-response invariant (lines 118-132) asserts that the structured-content key set is identical for gate-deny and anonymous-reject responses, by design. No information leakage about whether the caller exists, whether the gate is unreachable, or whether the capability is recognized.

---

## 5. Failure modes and blast radius

### What breaks when a privileged action is misclassified as safe

If someone edits `config/action_policy.yml` to mark a destructive action as `operation: read`, the policy loader catches it at startup. [`PolicyConfig::ActionValidator#validate_confirmation_consistency`](../lib/wild_admin_tools_mcp/guard/policy_config.rb#L185-L193) refuses any combination where `operation: read` is paired with `requires_confirmation: true` (or any non-`false` value), and conversely any `mutate` / `mutate_destructive` without `requires_confirmation: true`. The server raises `ConfigurationError` and refuses to start; there is no degraded boot. Validation is exhaustive — all errors are accumulated in `@errors` before raising, so a single restart surfaces every problem ([`policy_config.rb:31-38`](../lib/wild_admin_tools_mcp/guard/policy_config.rb)).

If a misclassification slips past validation (suppose `operation: read` on a real mutation but with `requires_confirmation: false` correctly set, intentionally lying), the consequences cascade:

1. `Guard::Pipeline#route_action` ([`pipeline.rb:37-45`](../lib/wild_admin_tools_mcp/guard/pipeline.rb)) sends `read` operations directly to `executor.execute`, skipping the two-phase nonce flow entirely.
2. `BlastRadiusEnforcer#check` ([`blast_radius_enforcer.rb:10-18`](../lib/wild_admin_tools_mcp/guard/blast_radius_enforcer.rb)) short-circuits to `allowed` for any operation matching `READ_OPERATIONS` — the cap becomes purely informational.
3. `Executor::Base#run_with_snapshots` ([`base.rb:52-60`](../lib/wild_admin_tools_mcp/executor/base.rb)) skips both `capture_before_snapshot` and `capture_after_snapshot` for non-mutating operations.

The audit record would still be produced (recorder is unconditional), but with no before/after snapshots and no nonce. Mitigation depends on the operator never lying in the policy file — the gem trusts its YAML. The realistic defense is the cross-reference matrix in [`007-TQ-STND-safety-cross-reference-matrix.md`](007-TQ-STND-safety-cross-reference-matrix.md) plus a policy-file review gate in deploy.

### What breaks when MCP transport fails mid-action

The two-phase flow makes a mid-action failure largely harmless:

- **Preview phase fails** (transport dies between client request and server response, or after `executor.preview` returns). The audit record persists with `phase: 'preview'`. The nonce lives in the in-memory store and expires on its TTL (default 30s, clamped 10-120s by [`NonceManager::MIN_TTL` / `MAX_TTL`](../lib/wild_admin_tools_mcp/guard/nonce_manager.rb#L15-L17)). No state in the host Rails app was mutated.
- **Execute phase fails between nonce validation and adapter mutation.** The nonce was consumed (`@store.consume!` runs before `executor.execute`, [`two_phase_flow.rb:27-28`](../lib/wild_admin_tools_mcp/guard/two_phase_flow.rb#L27-L28)) but the `Adapters::JobAdapter#retry_job!` call may or may not have reached Sidekiq. The audit record will land via the `rescue StandardError => e` block in `Audit::Recorder#record` ([`recorder.rb:29-31`](../lib/wild_admin_tools_mcp/audit/recorder.rb)) which appends an *error* record before re-raising. State of the underlying Rails resource is recoverable only by operator inspection — the gem cannot distinguish "Sidekiq received the retry" from "transport dropped the response".
- **Execute phase fails inside the adapter.** `Executor::Base#execute` ([`base.rb:36-39`](../lib/wild_admin_tools_mcp/executor/base.rb)) re-raises as `AdapterError` carrying the original. The audit record captures `phase: 'error'`, `error_message: "<class>: <msg>"`, and any `before_snapshot` that was already captured ([`recorder.rb:52-65`](../lib/wild_admin_tools_mcp/audit/recorder.rb)).

### Server-restart effects

Restart wipes the nonce store (in-memory `NonceStore`) and the rate-limiter sliding windows (in-memory `@windows` hash, [`rate_limiter.rb:14`](../lib/wild_admin_tools_mcp/guard/rate_limiter.rb)). Operators expecting a pending confirmation lose it and must re-run the preview. Rate-limit budgets reset to zero, which means the first request post-restart cannot be rate-limited by historical usage. Audit records survive only if the host uses `JsonLinesStore` — `MemoryStore` is documented in [`013-OD-OPNS-operator-deployment-guide.md:113`](013-OD-OPNS-operator-deployment-guide.md) as test-only.

### Error classes (canonical taxonomy from [`errors.rb`](../lib/wild_admin_tools_mcp/errors.rb))

`Error` (base) · `ActionNotFoundError` · `ValidationError` · `AdapterError` · `ConfigurationError` · `AuthenticationError` · `GateError`. Every executor error eventually surfaces as `AdapterError` with `original_error` preserved for forensics. `GateError` is the only one that flows into the deny-with-audit path; the rest propagate to `ToolHandler.execute`'s `rescue StandardError` block ([`tool_handler.rb:15-17`](../lib/wild_admin_tools_mcp/server/tool_handler.rb)) and become an `error` response with the message verbatim.

---

## 6. Trade-off analysis

### Decision A: Mandatory dry-run with server-issued nonce vs. optional `dry_run:` flag

| Field | Detail |
|-------|--------|
| Chosen | Every mutating action is split into `preview` and `execute`. Execute is only callable with a valid nonce returned from preview. ([`two_phase_flow.rb`](../lib/wild_admin_tools_mcp/guard/two_phase_flow.rb), Decision 1 in `006-AT-ADEC`) |
| Alternative | An optional `dry_run: true` parameter, evaluated inside each handler |
| Why chosen | Optional dry-run is the worst kind of safety control: it works in tests, then gets skipped at 3 AM. Mandatory two-phase is *structurally* impossible to bypass — the executor has no code path that runs without a nonce-validated invocation |
| Cost | Every action requires two round-trips. Every executor needs both a `preview_*` and `execute_*` method ([`cache_executor.rb:21-80`](../lib/wild_admin_tools_mcp/executor/cache_executor.rb)). Server holds in-memory nonce state. Test surface roughly doubles |
| When it breaks | If a future executor implements `execute` such that *no preview state difference exists* (e.g., a `set_flag_to_value` where preview and execute touch the same code), the nonce binding loses meaning. Mitigated by the convention that `preview` returns `estimated_affected` and never mutates |

### Decision B: In-process gate library vs. remote gate service

| Field | Detail |
|-------|--------|
| Chosen | `wild-capability-gate` is an in-process Ruby gem ([`Gemfile:7-13`](../Gemfile), `010-AT-ADEC`) |
| Alternative | Out-of-process gate (HTTP, gRPC) shared across services |
| Why chosen | No network failure modes to model; no circuit breaker; `evaluate` is a normal method call. Simplifies the fail-closed contract — only two failure modes (`nil` or `raise`), both handled in [`gate_client.rb:11,24-25`](../lib/wild_admin_tools_mcp/identity/gate_client.rb) |
| Cost | The gate's grant decisions are co-located with the Rails app. Distributed services that want shared capability decisions need to ship their own gate (or build an HTTP wrapper). Gate upgrades require redeploying the host app |
| When it breaks | Multi-app deployments needing centralized policy. The current contract makes a remote gate possible by replacing the object assigned to `WildAdminToolsMcp.configuration.gate`, but the latency and timeout machinery would need to be added by the new gate implementation, not this gem |

### Decision C: JSON Lines audit store vs. SQLite or remote sink

| Field | Detail |
|-------|--------|
| Chosen | `Audit::JsonLinesStore` for production; `MemoryStore` for tests ([`audit/store.rb`](../lib/wild_admin_tools_mcp/audit/store.rb), `008-AT-ADEC`) |
| Alternative | SQLite for indexed queries; remote sink (e.g., Splunk, OpenTelemetry) |
| Why chosen | Append-only by construction (`File.open(@path, 'a') { |f| f.puts(line) }`, [`store.rb:62-67`](../lib/wild_admin_tools_mcp/audit/store.rb#L62-L67)); zero schema migrations; `jq`-friendly; consistent with `wild-capability-gate`'s `Audit::JsonLinesWriter` pattern |
| Cost | `find(id)` and `recent(limit:)` scan the whole file ([`store.rb:79-97`](../lib/wild_admin_tools_mcp/audit/store.rb)). Operators must rotate the file themselves; no built-in compression or retention. No indexed queries — fine for forensic review, useless for analytics |
| When it breaks | File grows unbounded without logrotate. A single corrupt line silently skips on read (`rescue JSON::ParserError, ArgumentError` returns nil, [`store.rb:108-109`](../lib/wild_admin_tools_mcp/audit/store.rb)) — operator gets no warning |

### Decision D: Granular nonce errors internal, generic `nonce_invalid` external

| Field | Detail |
|-------|--------|
| Chosen | Client always receives `'nonce_invalid'`; audit records get the specific internal reason (`nonce_not_found`, `nonce_expired`, `nonce_already_used`, `nonce_action_mismatch`, `nonce_identity_mismatch`, `nonce_parameter_mismatch`). [`nonce_manager.rb:75-77`](../lib/wild_admin_tools_mcp/guard/nonce_manager.rb#L75-L77), Decision 8 in `006-AT-ADEC` |
| Alternative | Return the granular reason to the client for better UX |
| Why chosen | Distinguishing "not found" from "expired" from "already used" gives an attacker an oracle: existence, validity window, consumption status of any nonce. The generic response collapses the channel; the audit trail still gives operators the forensic detail |
| Cost | Clients cannot show a precise error to operators ("your nonce expired 14 seconds ago" vs. "this was already used"). The recovery path is the same — re-preview — so the UX hit is small |
| When it breaks | Multi-step workflows where the client wants to *correct* a parameter-mismatch nonce silently. Not a regression in v1 because there is no such workflow |

---

## 7. Operator playbook

### Deploy

The host Rails app declares the gem in its Gemfile (production form is git, dev form is path; see [`013-OD-OPNS-operator-deployment-guide.md:25-33`](013-OD-OPNS-operator-deployment-guide.md)). On boot the host configures three adapters + the gate + the audit store via `WildAdminToolsMcp.configure { … }`, then loads the policy with `Guard::PolicyConfig.load('config/action_policy.yml')`, then builds the pipeline and server with `ServerFactory.build_pipeline` + `ServerFactory.create`. The server is hosted inside whatever process the host chooses — stdio subprocess (the bundled `exe/wild-admin-tools-mcp` script), Puma worker, dedicated daemon.

**Boot sequence will fail loudly if:** `config/action_policy.yml` is missing or invalid YAML (`PolicyConfig.load` raises `ConfigurationError` with every accumulated error); any adapter is nil (`Configuration#validate!` raises); the gate is nil and any action is invoked (`GateClient` raises `GateError` → deny-with-audit). There is no degraded boot. Two-line restart: fix the config, restart the process.

### Smoke test (from `013-OD-OPNS-operator-deployment-guide.md:170-193`)

1. List tools — expect exactly three: `manage_background_jobs`, `manage_cache`, `manage_feature_flags`.
2. Read action — `manage_background_jobs(action: "list_queues")` returns `status: "success"` immediately. Confirms identity + gate + executor for the easiest path.
3. Preview a mutate — `manage_background_jobs(action: "retry_job", job_id: "<real-id>")` returns `status: "preview"` with `metadata.nonce` starting with `wnc_`.
4. Execute — re-send with the nonce. Returns `status: "success"` with `before_snapshot` and `after_snapshot`. The nonce is now consumed; replaying it returns `status: "denied"`, `reason: "nonce_invalid"`.
5. Gate health — call `Identity::GateHealthCheck.new(gate_client: gate_client).check`. Returns `{ status: 'healthy', gate_configured: true }` when the gate responds (deny or allow).

### Inspect MCP requests

Audit records are the source of truth. With `JsonLinesStore`:

```bash
tail -F log/admin_tools_audit.jsonl | jq 'select(.outcome != "success")'
jq 'select(.outcome == "denied") | {action, denial_reason, caller_id}' log/admin_tools_audit.jsonl
jq 'select(.action == "discard_jobs_by_filter")' log/admin_tools_audit.jsonl
```

The record schema is in [`audit/record.rb:7-24`](../lib/wild_admin_tools_mcp/audit/record.rb): `id`, `timestamp`, `caller_id`, `action`, `category`, `parameters` (sanitized), `phase` (`preview`/`execute`/`denied`/`error`), `confirmation_nonce`, `gate_result`, `outcome`, `denial_reason`, `before_snapshot`, `after_snapshot`, `duration_ms`, `error_message`, `server_version`.

### Roll back / recover

There is nothing to roll back inside this gem itself — it is a stateless library. What rolls back is the action it performed on the host app, and **the gem provides the audit data, not the rollback machinery**:

- For `retry_job` / `retry_jobs_by_filter`: the before snapshot has `job_id, status, queue, error_class` ([`state_capture.rb:44-46`](../lib/wild_admin_tools_mcp/executor/state_capture.rb)). Operator uses Sidekiq directly to undo (push back to failed set or discard).
- For `invalidate_cache_*`: there is no rollback. Cache is gone; the application re-populates it on next read. The before snapshot has `byte_size` and a SHA256 `value_hash` for evidence of *what* was cleared.
- For `delete_flag` / `toggle_flag`: operator re-creates the flag via Flipper directly. Before snapshot has full state including percentage and per-actor grants.

To stop *all* admin tooling immediately: set the gate to deny all `admin_tools.*` capabilities (this is the supported kill switch — every action goes through the gate; deny means deny). Restarting the gem process is *not* an emergency stop; the next-boot server will resume serving the same policy.

---

## 8. Recommendations for v2

**Brutal items first.**

1. **The nonce store is process-local memory.** Fine for single-process stdio deployments, immediately broken for HTTP/SSE deployments behind a load balancer. The two-phase flow assumes preview and execute land on the same process. There is no documented warning of this; an operator scaling horizontally will silently break the safety model. Either document it as a hard constraint in `013-OD-OPNS` or design a `NonceStore` adapter interface (Redis, SQL) before v2 ships any non-stdio transport. The same constraint applies to `RateLimiter`'s in-memory `@windows`.

2. **The rate limiter has no global write-lock.** [`rate_limiter.rb:18-26`](../lib/wild_admin_tools_mcp/guard/rate_limiter.rb) takes `@creation_mutex` only when allocating a new `SlidingWindow`. Once a window exists, two threads racing through `check_window` may both observe `window.allow?` returning true at the threshold. `SlidingWindow` may have its own internal mutex (referenced in the class-level comment) but the rate-limiter doesn't bound the cross-window decision. Worth re-auditing under load.

3. **`JsonLinesStore.recent`/`find` load the whole file** ([`store.rb:73-90`](../lib/wild_admin_tools_mcp/audit/store.rb)). At even modest audit volumes — say, 10K records — `File.readlines(@path).last(limit)` reads everything. Replace with reverse-streaming (`File.open` + read from end) before any operator surface depends on it.

4. **The category extraction in `Audit::Recorder#extract_category`** ([`recorder.rb:77-88`](../lib/wild_admin_tools_mcp/audit/recorder.rb)) uses regex on action names. Easy to forget when adding actions. Move the category onto the action policy YAML (it's already organized by `action_categories:`) and read it back from `PolicyConfig`.

5. **`StateCapture#snapshot_category`** is also regex-based ([`state_capture.rb:27-32`](../lib/wild_admin_tools_mcp/executor/state_capture.rb)). Same fix — let each executor declare its snapshot kind explicitly. The current pattern is fragile to action-name evolution and silently returns `nil` for unrecognized actions, suppressing snapshots without alerting.

6. **No structured logger** anywhere in `lib/`. Failures inside the recorder's `rescue` clause re-raise but the only persistence is the JSONL audit. Adding a `Logger` interface that operators can wire to their log pipeline would close a real observability gap.

7. **v2 priorities from [`016-PP-PLAN-v2-expansion-roadmap.md`](016-PP-PLAN-v2-expansion-roadmap.md)** look right: deployment-status read-only first, then audit query/export. Console proxying should remain "may not be implementable safely" — the roadmap is honest about this and v2 should not water down the position under pressure.

---

## Brief report

The audit is complete and written to `/home/jeremy/000-projects/wild/wild-admin-tools-mcp/000-docs/020-AT-AUDT-appaudit-2026-05-28.md` (~3,600 words). The gem is unusually well-structured for a v1: pipeline composition is clean, every safety claim has a corresponding adversarial spec, and the ADR set (`003`-`019`) maps 1:1 to the code. Real strengths: fail-closed gate integration, mandatory two-phase nonce with parameter-binding, before/after snapshot capture at the executor base.

**Cross-repo issues worth surfacing:**

- The in-memory `NonceStore` and `RateLimiter` windows constrain `wild-admin-tools-mcp` to single-process deployments. Any HTTP/SSE transport rollout in `wild-capability-gate` or the wider wild ecosystem must include a `NonceStore` adapter contract here first.
- `wild-capability-gate` v2's tiered capability scheme (per [`016-PP-PLAN-v2-expansion-roadmap.md:120-122`](016-PP-PLAN-v2-expansion-roadmap.md)) is a hard blocker for console-proxying and user-management features in this gem.
- The `extract_category`/`snapshot_category` regex coupling is a small but real ecosystem hygiene issue — could become a shared convention violation if the introspection sibling copies the pattern.
