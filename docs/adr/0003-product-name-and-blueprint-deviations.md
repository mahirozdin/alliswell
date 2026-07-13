# ADR-0003 — Product name "AllisWell" & deliberate blueprint deviations

- **Status:** Accepted
- **Date:** 2026-07-14
- **Related task:** OPH-001, OPH-002

## Context

The blueprint used the working title "Open Productivity Hub" with `open_productivity_*`
identifiers and an `apps/mobile` folder name. The repository lives in a folder named
**AllisWell** ("all is well" — everything under control), which is a distinctive, brandable name.
The blueprint is explicitly *not law*; deviations must be recorded.

## Decision

1. **Product name: AllisWell** (descriptor: "Open Productivity Hub").
   - npm scope: `@alliswell/*` · database: `alliswell` · Flutter org: `com.alliswell`.
   - Custom URL scheme: `alliswell://task/{taskId}`.
   - Google Calendar extended property keys: `alliswell_task_id`, `alliswell_workspace_id`
     (replaces `open_productivity_*` from BLUEPRINT §7.1).
2. **`apps/app` instead of `apps/mobile`** — the Flutter app targets desktop and web too;
   "mobile" would be misleading.
3. **Linux added** as a sixth Flutter target — near-zero cost, natural fit for a self-host,
   open-source audience. Support tier: community/best-effort.
4. **Redis 8** (AGPL, OSI-approved again as of 8.0) instead of an unspecified Redis version.
5. **Schema additions** over BLUEPRINT §10 — see ADR-0004 (`sort_order`, `snoozed_until`,
   `actual_minutes` on tasks; FK policy; auth/idempotency tables).

## Consequences

- All future code must use the `alliswell` identifiers above; do not reintroduce
  `open_productivity_*` keys.
- BLUEPRINT.md stays the product source of truth; where identifiers differ, this ADR wins.
