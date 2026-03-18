# Contributing to wild-admin-tools-mcp

Thank you for your interest in contributing. This project is currently maintained internally, but we welcome security reports and feedback.

## Current Status

This repository is in **Phase 0 — planning and scaffolding**. No application code exists yet.

## Before Contributing

1. Read `CLAUDE.md` for project context and conventions
2. Read `000-docs/003-TQ-STND-safety-model.md` for safety requirements
3. Read `000-docs/005-AT-ADEC-threat-model.md` for security considerations

## Safety Rules

These are **non-negotiable** when contributing to this codebase:

1. **Never bypass the capability gate** — All operations require gate authorization
2. **Never skip dry-run support** — Every action must support preview mode
3. **Never skip confirmation for destructive ops** — Two-phase confirmation is mandatory
4. **Never skip audit logging** — Every invocation must produce before/after audit records
5. **Never accept arbitrary code as input** — Tool parameters are data, not code
6. **Never exceed blast radius caps** — Per-action limits are enforced, not advisory
7. **Prefer restrictive defaults** — When uncertain, deny access

## Development Setup

```bash
bundle install              # Install dependencies
bundle exec rspec           # Run test suite
bundle exec rubocop         # Lint
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Ensure all tests pass: `bundle exec rspec`
4. Ensure no lint errors: `bundle exec rubocop`
5. Update documentation if applicable
6. Submit a pull request with clear description

## Security Contributions

If your contribution addresses a security issue, please coordinate with maintainers privately before submitting a public pull request. See `SECURITY.md` for details.

## Code of Conduct

Please review and follow our `CODE_OF_CONDUCT.md`.

## Questions?

For questions about contributing, open a GitHub issue with the `question` label.
