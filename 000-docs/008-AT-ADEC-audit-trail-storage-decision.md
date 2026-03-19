# 008-AT-ADEC — Audit Trail Storage Decision

## Status

Accepted

## Context

The audit trail must capture every operation — success, denial, error, preview — with before/after snapshots, sanitized parameters, and identity metadata. Storage must be append-only, tamper-evident, and operationally simple.

Options considered:

1. **JSON Lines file** (append-only `.jsonl`)
2. **SQLite database**
3. **External service** (e.g., remote log aggregator)

## Decision

**JSON Lines file** for production, **MemoryStore** for tests.

### Production: `Audit::JsonLinesStore`

- Append-only writes to a `.jsonl` file
- One JSON object per line, one line per audit record
- Thread-safe via Mutex
- File-based: no external dependencies, no schema migrations
- Readable by standard tools (`jq`, `grep`, log shippers)

### Test: `Audit::MemoryStore`

- In-memory array with Mutex for thread safety
- No filesystem dependency in test suite
- Supports `clear!` for test isolation

### Shared interface: `Audit::Store` base class

Both stores implement: `append(record)`, `recent(limit:)`, `find(id)`, `count`

## Rationale

| Criterion | JSON Lines | SQLite | External Service |
|-----------|-----------|--------|-----------------|
| Simplicity | High | Medium | Low |
| No external deps | Yes | Yes (gem) | No |
| Append-only | Natural | Requires discipline | Depends |
| Queryable | Via jq/grep | Via SQL | Via service |
| Log shipper compatible | Excellent | Poor | N/A |
| Operationally simple | Yes | Medium | No |

JSON Lines was chosen because:

- Consistent with `wild-capability-gate`'s `Audit::JsonLinesWriter` pattern
- No additional gem dependencies
- Append-only by design (no UPDATE/DELETE operations)
- Trivially parseable by operators and log infrastructure
- MemoryStore provides clean test isolation without filesystem

## Consequences

- Querying requires reading the file (no indexed lookups) — acceptable for audit review, not for analytics
- File rotation is the operator's responsibility (logrotate or similar)
- No built-in encryption at rest — operators should ensure filesystem-level encryption for sensitive environments
- Future migration to a database or external service is straightforward via the Store interface
