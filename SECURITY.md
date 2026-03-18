# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in `wild-admin-tools-mcp`, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. Email security concerns to the maintainer privately
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Any suggested mitigations

### What to Expect

- Acknowledgment within 48 hours
- Initial assessment within 7 days
- Regular updates on remediation progress
- Credit in the security advisory (if desired)

## Security Model

This project implements a mutation-aware safety model documented in `000-docs/003-TQ-STND-safety-model.md`. Key security properties:

### Enforced Boundaries

1. **Mutation-bounded** — Only allowlisted actions can execute, with enforced blast radius caps
2. **Dry-run first** — Every action supports preview mode that shows what would change without executing
3. **Two-phase confirmation** — Destructive actions require explicit confirmation with nonce
4. **Audited** — Every invocation logged with before/after state snapshots, identity, parameters, outcome
5. **Gate-required** — Mandatory capability gate integration for all operations

### Threat Model

Ten mutation-specific threat categories are formally evaluated in `000-docs/005-AT-ADEC-threat-model.md`:

1. Unintended mutation
2. State corruption
3. Cascading failures
4. Privilege escalation
5. Parameter injection
6. Audit bypass
7. Replay attacks
8. Confirmation bypass
9. Rate limit bypass
10. Rollback abuse

### Security Defect Definition

A security defect is any behavior that:
- Executes a mutation outside the action allowlist
- Bypasses dry-run enforcement
- Skips two-phase confirmation for destructive actions
- Omits before/after state snapshots in audit trail
- Bypasses capability gate checks
- Exceeds blast radius caps
- Skips audit logging

## Responsible Disclosure

We follow responsible disclosure practices. If you report a vulnerability:
- We will work with you to understand and resolve the issue
- We will credit you in the security advisory (unless you prefer anonymity)
- We ask that you give us reasonable time to address the issue before public disclosure
