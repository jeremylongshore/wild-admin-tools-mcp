# Telemetry Emission Hook Interface — wild-admin-tools-mcp

**Document type:** Architecture decision
**Filed as:** `018-AT-ADEC-telemetry-emission-hook-interface.md`
**Status:** Active (interface defined, not yet wired)
**Last updated:** 2026-03-19

---

## Purpose

This document defines the interface for emitting usage events from wild-admin-tools-mcp to wild-session-telemetry. The interface is designed as an optional hook: admin-tools-mcp operates fully without telemetry, and telemetry is a subscriber that receives events when present. There is no hard dependency between the two repos.

---

## Design Principles

1. **Optional, not required.** Admin-tools-mcp must function identically whether or not a telemetry subscriber is attached. No telemetry failure may affect pipeline behavior.
2. **Fire-and-forget.** Event emission is asynchronous from the pipeline's perspective. The hook call must not block the pipeline or add latency to action execution.
3. **Privacy-preserving.** Telemetry events carry action metadata, not raw parameter values. The event schema is intentionally sparse to prevent PII from leaking into telemetry infrastructure.
4. **Structured, not log-scraped.** Events are emitted as structured data through a defined interface, not extracted from audit log files by an external parser.

---

## Hook Points

Three points in the pipeline emit telemetry events:

| Hook Point | Location | Event Type | Fires When |
|------------|----------|-----------|------------|
| After audit record creation | `Audit::Recorder#record` | `action.completed` | Every pipeline invocation (success, denial, error, preview) |
| After gate evaluation | `Identity::AuthenticatedPipeline#authorize_via_gate` | `gate.evaluated` | Every gate check (allowed, denied, errored) |
| After rate limit check | `Guard::Pipeline#check_rate_limit!` | `rate_limit.checked` | Every rate limit evaluation (allowed, exceeded) |

### Hook invocation pattern

```ruby
# Conceptual — not yet wired in v1
module WildAdminToolsMcp
  module Telemetry
    class HookEmitter
      def initialize(subscriber: nil)
        @subscriber = subscriber
      end

      def emit(event)
        return unless @subscriber

        @subscriber.receive(event)
      rescue StandardError
        # Telemetry failures are swallowed — they must never
        # affect pipeline behavior. Logged to stderr for operator
        # visibility, not raised.
      end
    end
  end
end
```

The `subscriber` is any object that responds to `receive(event)`. If nil, no events are emitted. If the subscriber raises, the exception is swallowed.

---

## Event Schema

All events share a common envelope:

```json
{
  "event_type": "action.completed",
  "timestamp": "2026-03-19T14:30:00.000Z",
  "caller_id": "service-account-ops",
  "action": "retry_job",
  "outcome": "success",
  "duration_ms": 42.5,
  "metadata": {}
}
```

### Field definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event_type` | string | Yes | One of: `action.completed`, `gate.evaluated`, `rate_limit.checked` |
| `timestamp` | ISO 8601 string | Yes | UTC timestamp of the event |
| `caller_id` | string | Yes | Caller identity (same as audit record `caller_id`) |
| `action` | string | Yes | Action name from the allowlist |
| `outcome` | string | Yes | Result of the operation: `success`, `denied`, `error`, `preview`, `rate_limited` |
| `duration_ms` | float | No | Wall-clock duration of the operation in milliseconds |
| `metadata` | object | No | Event-type-specific metadata (see below) |

### Event-type-specific metadata

**`action.completed`:**
```json
{
  "category": "background_jobs",
  "operation": "mutate",
  "phase": "execute",
  "denial_reason": null,
  "blast_radius_count": 3,
  "confirmation_used": true
}
```

**`gate.evaluated`:**
```json
{
  "gate_result": "allowed",
  "capability_checked": "admin_tools.retry_job"
}
```

**`rate_limit.checked`:**
```json
{
  "rate_result": "allowed",
  "current_count": 7,
  "limit": 10,
  "window_seconds": 60
}
```

---

## Privacy Constraints

The following data is explicitly excluded from telemetry events:

| Excluded | Reason |
|----------|--------|
| Raw parameter values | May contain PII (user IDs, email addresses in flag scopes) |
| Before/after snapshot data | Contains system state that may include sensitive values |
| Nonce values | Security-sensitive tokens that should not leave the server |
| Error stack traces | May contain file paths, internal state, or parameter values |
| Adapter-specific identifiers | Job IDs, cache keys, flag names (specific resource references) |

Telemetry events carry **action names and outcomes only** — enough for usage analysis and pattern detection, not enough to reconstruct what specific resources were affected. Detailed forensics use the audit trail directly, not telemetry.

---

## Integration Pattern

```
                        wild-admin-tools-mcp
                               |
                     [HookEmitter.emit(event)]
                               |
                     [subscriber.receive(event)]
                               |
                    wild-session-telemetry
                               |
                    [ingest, aggregate, export]
```

The integration is a one-way push. Admin-tools-mcp pushes events to the telemetry subscriber. It never queries telemetry. It never waits for telemetry acknowledgment. If the subscriber is absent, events are silently dropped.

### Wiring the subscriber

When wild-session-telemetry provides a Ruby client, it will be configured in the admin-tools-mcp initialization:

```ruby
# Conceptual — configuration when telemetry is available
telemetry_client = WildSessionTelemetry::Client.new(endpoint: ENV['TELEMETRY_ENDPOINT'])
emitter = WildAdminToolsMcp::Telemetry::HookEmitter.new(subscriber: telemetry_client)

# Pass emitter to pipeline construction
# (pipeline integration point TBD when telemetry repo is active)
```

---

## Implementation Status

| Component | Status |
|-----------|--------|
| Event schema | Defined in this document |
| HookEmitter interface | Defined (conceptual, not coded) |
| Hook points identified | 3 points identified in pipeline |
| Subscriber interface | `receive(event)` — any object responding to this method |
| Wiring in pipeline | Not yet implemented |
| wild-session-telemetry client | Not yet available (repo not in active development) |

This interface is ready to implement when wild-session-telemetry enters active development. No code changes are needed in admin-tools-mcp until then — the audit trail captures all the raw data that telemetry will eventually consume.
