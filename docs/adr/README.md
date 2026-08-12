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
| [0015](0015-alarm-delivery-and-reminder-profiles.md) | Alarm delivery: AlarmKit-first, two alarm instants, user-owned reminder profiles | Accepted |
| [0016](0016-in-app-url-routing-and-widget-actions.md) | In-app URL routing (`alliswell://`) — navigation only; widget writes go through App Intents | Accepted |
| [0017](0017-swipe-to-delete-package.md) | `flutter_slidable` for the reveal-then-tap delete affordance | Accepted |
| [0018](0018-quick-links-user-scoped-sync-entity.md) | Quick Links: the first user-scoped sync entity | Accepted |
| [0019](0019-ai-provider-architecture.md) | AI provider architecture: two tracks (MCP connector + BYOK), adapters not SDKs | Accepted |
| [0020](0020-recurring-tasks-and-materialization.md) | Recurring tasks: a clamped RRULE subset, materialized as real rows | Accepted |
| [0021](0021-calendar-mirror-v2.md) | Calendar mirror v2: every task is on the calendar, and it is not a setting | Accepted |
| [0022](0022-remote-mcp-server.md) | Remote MCP server: hand-rolled Streamable HTTP behind our own OAuth 2.1 | Accepted |
| [0023](0023-stt-and-share-intent-dependencies.md) | On-device STT + share-intent: two plugins behind seams, a second iOS extension | Accepted — §3 amended by [0029](0029-share-extension-notifies-instead-of-redirecting.md) |
| [0024](0024-license-polyform-noncommercial.md) | PolyForm Noncommercial license | Accepted — supersedes [0002](0002-license-agpl-3.0.md) |
| [0025](0025-firebase-optional-and-credential-hygiene.md) | Firebase is optional; credential hygiene | Accepted |
| [0026](0026-social-sign-in.md) | Social sign-in | Accepted |
| [0027](0027-attachment-capture-image-picker.md) | Attachment capture: `image_picker` for the photo library and the camera | Accepted |
| [0028](0028-markdown-document-model-and-renderer.md) | Markdown: the note model (split by intent), our own renderer over the `markdown` package, and how far diagrams go | Accepted |
| [0029](0029-share-extension-notifies-instead-of-redirecting.md) | The share extension notifies and the app drains, instead of redirecting | Accepted — amends [0023](0023-stt-and-share-intent-dependencies.md) §3 |
| [0030](0030-external-document-handles.md) | Owning somebody else's file: durable handles, an in-repo plugin, and where writing is refused | Accepted |

> Rows 0024–0027 were missing until 2026-08-10 (OPH-242): four ADRs had landed
> without an index line. 0028 was held as a **reserved** row while OPH-246 was
> open, so the number could not be reused — this round had already corrected two
> documents that gave the share decision that number. It landed on 2026-08-10.

Template: [template.md](template.md)
