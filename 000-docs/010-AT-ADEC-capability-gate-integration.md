# 010-AT-ADEC — Capability Gate Integration

## Status

Accepted

## Context

The admin tools MCP server must integrate with `wild-capability-gate` to enforce capability-based authorization. The gate controls which callers can perform which administrative operations.

## Decision

### In-process library, not remote service

`wild-capability-gate` is consumed as a local Ruby gem (in-process library), not a remote HTTP service. This means:

- No network latency or timeout concerns for gate calls
- No circuit breaker needed for gate availability
- The gate's `evaluate` method **never raises** — it returns `EvaluationResult.denied(reason: :evaluation_error)` on any internal error

### GateClient wrapper

A thin `GateClient` class wraps the gate's `evaluate` method:

- Maps action names to capability names: `admin_tools.{action_name}`
- Updates `SessionContext` with gate evaluation results
- Raises `GateError` if the gate is nil/unconfigured

### Fail-closed behavior

If the gate is unavailable (nil, unconfigured, or raises unexpectedly):

1. **Gate nil:** `GateClient` raises `GateError` → `AuthenticatedPipeline` catches → denies with `gate_denied`
2. **Gate error:** `GateClient` wraps in `GateError` → `AuthenticatedPipeline` catches → denies with `gate_denied`
3. **Gate denies:** Normal deny flow with audit record

In all cases, an audit record is created documenting the denial.

### Capability naming convention

Capabilities are namespaced: `admin_tools.{action_name}`

Examples:
- `admin_tools.inspect_job`
- `admin_tools.retry_job`
- `admin_tools.delete_flag`

### AuthenticatedPipeline orchestration

The full call flow:

```
AuthenticatedPipeline.call(action_name, params, request_context, nonce:)
  1. IdentityExtractor → SessionContext (reject anonymous)
  2. GateClient → updated SessionContext (reject denied/errored)
  3. AuditedPipeline → Guard::Pipeline → Executor (normal flow)
```

### Health check

`GateHealthCheck` probes the gate with a synthetic evaluation to verify it's configured and responsive. A denied result is healthy (the gate responded); only errors are unhealthy.

## Rationale

- **In-process simplicity:** No network failure modes to handle beyond the gate gem itself
- **Fail-closed default:** Unavailable gate means denied, not bypassed
- **Layered pipeline:** Identity → Gate → Audit → Guard → Executor creates clear separation of concerns
- **Consistent audit:** Every denial path produces an audit record

## Consequences

- `wild-capability-gate` must be available as a gem dependency (path reference for dev, published gem for production)
- Gate configuration files (`capabilities.yml`, `grants.yml`) must exist and be maintained alongside the admin tools configuration
- Adding new actions requires adding corresponding capability definitions in the gate configuration
- The `admin_tools.` prefix convention must be maintained across all action names
