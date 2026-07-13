# ADR-0001 — Stack & monorepo baseline

- **Status:** Accepted
- **Date:** 2026-07-14
- **Related task:** OPH-001…OPH-007

## Context

The product (BLUEPRINT.md) requires: one client codebase for iOS/Android/Web/macOS/Windows,
a JavaScript-only Node.js backend (owner constraint, TypeScript explicitly forbidden), MySQL,
realtime multi-device sync, and an AI-agent-friendly repository.

## Decision

- **Monorepo** with npm workspaces: `apps/api` (backend) + `apps/app` (Flutter). Flutter is not an
  npm workspace; it is managed by pub.
- **Backend:** Node.js ≥ 22, ESM JavaScript, **Fastify 5** (schema-first validation via Ajv,
  excellent plugin model, fastest mainstream Node framework), **knex + mysql2** (SQL-first, no ORM
  magic — agents and contributors can read every query), **ioredis**, **Socket.IO** (+ Redis
  adapter) for realtime, **BullMQ** for jobs, **pino** for logs, **Vitest** for tests,
  ESLint flat config + Prettier for style. `scripts/check-no-ts.sh` enforces the TypeScript ban in CI.
- **Client:** single **Flutter** codebase targeting all six platforms; Riverpod, go_router, dio,
  drift (local replica), flutter_secure_storage, flutter_local_notifications, flutter_quill
  (editor candidate).
- **Infra:** Docker Compose with MySQL **8.4** (current LTS line) and **Redis 8**.

## Alternatives considered

- **Express/NestJS:** Express lacks schema-first validation; NestJS is TypeScript-centric —
  conflicts with the JS-only rule.
- **Prisma/Sequelize ORM:** codegen and abstraction hide SQL; knex keeps SQL visible and
  migration-first, which suits MySQL requirements and AI-driven maintenance.
- **Separate web app (Vue 3):** blueprint allowed it as fallback; one Flutter codebase wins for
  maintenance cost while Flutter Web quality is acceptable for an app-like (not content) product.
- **Postgres:** technically attractive, but MySQL is a hard product constraint.

## Consequences

- Single language per layer (JS / Dart) keeps the contributor story simple.
- No TypeScript means we lean on Ajv schemas + JSDoc + tests for safety; CI guards the policy.
- Flutter Web bundle size / SEO limits are acceptable (productivity app behind login).
