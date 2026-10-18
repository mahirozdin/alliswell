---
paths:
  - "apps/api/migrations/**"
  - "apps/api/src/db/collation.js"
  - "apps/api/src/db/migration-dirs.js"
---
# Migrations — critical path

A migration that reaches production cannot be taken back; the batch's net comes too late.

- **K1 extra:** `npm run verify:task` runs migrate → rollback → migrate by itself when a
  migration changes. Name the integration suite of the tables you touched as well.
- **Invariants:** I-02 (MySQL through knex), I-08 (append-only; `YYYYMMDDHHMMSS_verb_subject.js`,
  ESM `export async function up/down(knex)`; never edit an applied one). IDs are ULID
  `CHAR(26)`, timestamps UTC `DATETIME(3)` (ADR-0004). Every `up` has an honest `down`.
- **Traps (docs/LESSONS.md `migrations`):**
  - A new column's default applies to every existing row: a `false`-default suppression flag
    suppresses all of them — name the flag so today's behaviour is the default.
  - Production is MariaDB: `utf8mb4_0900_ai_ci` exists only in MySQL 8. Never pin a
    collation in a migration — `resolveCollation(knex)`; the `api-mariadb` CI job catches it.
  - When a canonical format changes, the migration recomputes `content_hash` with the new
    signature; keep the old column, so `down()` stays true.
- **Detail:** [ARCHITECTURE §4](../../docs/ARCHITECTURE.md#4-data-layer),
  [ADR-0004](../../docs/adr/0004-ids-timestamps-schema-conventions.md).
