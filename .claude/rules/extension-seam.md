---
paths:
  - "apps/api/src/lib/ee.js"
  - "apps/api/src/lib/ee-license.js"
  - "apps/api/src/plugins/entitlements.js"
  - "apps/api/src/routes/ee.js"
  - "apps/app/lib/src/features/ee/**"
  - "apps/api/test/fixtures/ee-overlay*/**"
---
# The extension seam — critical path

A private extension (checked out at `ee/`, never committed here) plugs into the core through
this seam. A break here takes down a paying deployment the core's suites never run.

- **K1 extra:** `npm run verify:task -- apps/api/test/unit/ee-seam.test.js
  apps/api/test/unit/ee-status.test.js apps/api/test/unit/ee-lock.test.js`. With the extension
  checked out, run its `verify:batch` too; push the core first.
- **Invariants:** core work does not change CE behaviour; the seam stays neutral. The
  extension's design never enters a public doc or commit — the core only says "the
  extension", plus a registry id (`check:no-ee`). An extension that wrote data must be present
  to serve it: otherwise every non-`/health/*` request is a 503 `EXTENSION_UNAVAILABLE`
  (ADR-0041).
- **Traps (docs/LESSONS.md `extension-seam`):**
  - The seam rests on ORDER: the loader runs after the infrastructure plugins, before the
    routes. Registries are app-scoped; module-level ones collide between two test apps.
  - In capability discovery a 404 (an older server) equals an empty list: "off", not an error.
  - ADR numbers clash between the two repos → name the repo when citing one; core `0002` is the
    AGPL ADR.
- **Detail:** [ARCHITECTURE §3b](../../docs/ARCHITECTURE.md#3b-enterprise-overlay-seam-ee-002),
  [ENTERPRISE.md](../../docs/ENTERPRISE.md).
