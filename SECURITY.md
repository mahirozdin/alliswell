# Security Policy

## Supported versions

AllisWell is pre-release (0.x). Only the latest `main` is supported with security fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

- Preferred: GitHub **Private Vulnerability Reporting** ("Report a vulnerability" on the Security tab).
- Or email: **mahirozdin@bubiapps.com** (subject: `[SECURITY] AllisWell`).

Include reproduction steps, affected component (`apps/api`, `apps/app`, infra), and impact.
You will get an acknowledgement within 72 hours. Please allow a reasonable disclosure window
before publishing.

## Security design baseline

For contributors — the standing rules (BLUEPRINT §15.3, enforced through reviews):

- Passwords: argon2id. Sessions: short-lived JWT + rotating refresh tokens stored **hashed**,
  with family-based reuse detection.
- Calendar OAuth tokens encrypted at rest (AES-256-GCM, key from env, never committed).
- All input Ajv-validated; SQL only through knex bindings (no string interpolation).
- Notes render with XSS-safe pipelines; web builds ship CSP.
- Notification payloads contain IDs only, never task content.
- Rate limiting globally and stricter on auth endpoints.
- Secrets live in `.env` (gitignored); `.env.example` carries placeholders only.
