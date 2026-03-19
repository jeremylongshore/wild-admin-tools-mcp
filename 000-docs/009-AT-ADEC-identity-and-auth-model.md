# 009-AT-ADEC — Identity and Authentication Model

## Status

Accepted

## Context

The admin tools MCP server must know who is making each request and reject anonymous callers before any action reaches the guard pipeline. Identity must flow through the entire call chain so audit records reflect the real caller.

## Decision

### SessionContext value object

An immutable `Data.define` carries identity through the pipeline:

- `caller_id` — unique identifier for the calling principal
- `caller_type` — classification (user, service, agent)
- `authenticated` — boolean, true only when identity was successfully extracted
- `gate_result` — updated after capability gate evaluation
- `capabilities` — list of granted capabilities for this session

### IdentityExtractor

Extracts caller identity from a request context hash. Supports multiple key conventions:

- `caller_id`, `user_id`, `client_id` (symbol or string keys)
- `caller_type` / `type` for classification

Returns an anonymous `SessionContext` for nil, empty, or whitespace-only identities.

### Anonymous rejection

Anonymous requests are rejected immediately — before the capability gate, before the guard pipeline, before any executor. An audit record is still created for every rejection.

## Rationale

- **Fail early:** Anonymous rejection before gate evaluation avoids wasting gate resources on invalid requests
- **Immutable context:** `Data.define` ensures identity cannot be modified after extraction
- **Multiple key support:** MCP clients may use different conventions for caller identification
- **Audit coverage:** Even rejected anonymous requests produce audit records for security monitoring

## Consequences

- Callers must provide identity in the request context hash — there is no anonymous access path
- The `IdentityExtractor` must be extended if new identity formats are needed (e.g., JWT, OAuth tokens)
- The `SessionContext` is intentionally simple — it does not validate credentials, only extract and carry identity
