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
| [0009](0009-localization-i18n-architecture.md) | Localization (i18n): JSON locales, device detection, persisted override | Accepted |
| [0010](0010-home-screen-widgets-architecture.md) | Home-screen / desktop widgets: native views over an App-Group snapshot | Accepted |
| [0011](0011-attachments-r2-s3-storage.md) | Attachments: S3-compatible storage (R2), presigned direct transfer, pull-only sync entity | Accepted |
| [0012](0012-liquid-glass-v2-visual-refresh.md) | "Liquid Glass v2" visual refresh (design round 8) | Accepted |
| [0013](0013-local-first-search.md) | Local-first search with app-owned Turkish folding | Accepted |
| [0014](0014-folders-and-global-files.md) | Folders and the global "Dosyalar" section | Accepted |

Template: [template.md](template.md)
