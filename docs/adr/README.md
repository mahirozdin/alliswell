# Architecture Decision Records

Deliberate, hard-to-reverse decisions are recorded here. When a decision changes, don't edit the
old ADR — supersede it with a new one and cross-link.

**When to write an ADR** (AGENTS.md rule 6): new dependency category, schema redesign, protocol or
API contract change, security-relevant choice, deviation from BLUEPRINT.md.

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-stack-and-monorepo.md) | Stack & monorepo baseline | Accepted |
| [0002](0002-license-agpl-3.0.md) | AGPL-3.0 license | Accepted |
| [0003](0003-product-name-and-blueprint-deviations.md) | Product name "AllisWell" & blueprint deviations | Accepted |
| [0004](0004-ids-timestamps-schema-conventions.md) | ULID ids, UTC timestamps, schema conventions | Accepted |
| [0005](0005-alliswell-glass-design-system.md) | "AllisWell Glass" design system (permanent visual language) | Accepted |
| [0006](0006-google-oauth-token-crypto-and-mirror-queue.md) | Google OAuth flow, token encryption & the mirror queue | Accepted |
| [0007](0007-google-inbound-sync-and-conflict-policy.md) | Google inbound sync: push channels, echo suppression & two-way conflict policy | Accepted |
| [0008](0008-external-calendar-events.md) | External calendar events as a read-only sync entity | Accepted |

Template: [template.md](template.md)
