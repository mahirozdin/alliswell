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

## File storage (attachments)

S3/R2 credentials live only on the server (`STORAGE_S3_*`, never committed).
Clients receive single-object, single-verb presigned URLs that expire
(`STORAGE_PRESIGN_TTL_SEC`, default 1 h); URLs are never logged, synced or
exported. Storage keys are opaque (`ws/{workspaceId}/{fileId}` — no filenames,
no PII). Uploads only become visible after the server verifies the object
against its declaration; mismatches are deleted. Bytes are never served from
the app origin, and download content types are pinned server-side. Details:
[docs/ATTACHMENTS.md](docs/ATTACHMENTS.md) §9.
