# Architecture Decision Records

Deliberate, hard-to-reverse decisions are recorded here. When a decision changes, don't edit the
old ADR — supersede it with a new one and cross-link.

**When to write an ADR** (AGENTS.md rule 6): new dependency category, schema redesign, protocol or
API contract change, security-relevant choice, deviation from BLUEPRINT.md.

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-stack-and-monorepo.md) | Stack & monorepo baseline | Accepted |
| [0002](0002-license-agpl-3.0.md) | AGPL-3.0 license | Superseded by [0024](0024-license-polyform-noncommercial.md) |
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
| [0031](0031-note-versioning.md) | Note versioning: server-owned history, coalesced at the head | Accepted |
| [0032](0032-api-keys.md) | API keys: plain Bearer, one workspace, no scopes in v1 | Accepted |
| [0033](0033-markdown-is-the-only-note-format.md) | Markdown is the only thing a note is made of | Accepted — supersedes [0028](0028-markdown-document-model-and-renderer.md) §1 |
| [0034](0034-pdf-export-rasterizes-what-it-cannot-typeset.md) | The PDF exporter draws what it cannot typeset | Accepted — extends [0028](0028-markdown-document-model-and-renderer.md) §3 |
| [0035](0035-api-docs-are-generated.md) | The API reference is generated from the routes | Accepted — amends [0032](0032-api-keys.md) §4 |
| [0036](0036-landing-multi-entry-enterprise-page.md) | The enterprise page is a Vite entry, not generated markdown | Accepted |
| [0037](0037-android-exact-alarms-are-declared-not-begged-for.md) | Android exact alarms are declared, not begged for | Accepted |
| [0038](0038-server-to-device-delivery.md) | Server→device delivery: a hint everywhere, the clock only on the web | Accepted — amends [NOTIFICATIONS.md](../NOTIFICATIONS.md) §0 for the web |
| [0039](0039-a-service-worker-is-the-one-thing-dart-cannot-be.md) | A service worker is the one thing Dart cannot be | Accepted — narrows [AGENTS.md](../../AGENTS.md) rule 3 |
| [0040](0040-attachment-target-registry.md) | `files.target_type` is a registry, not a list | Accepted — revises [0011](0011-attachments-r2-s3-storage.md) §3 |
| [0041](0041-an-extension-that-wrote-data-must-be-present-to-serve-it.md) | An extension that wrote data must be present to serve it | Accepted — revises the loader's failure policy (EE-002) |
| [0042](0042-layered-verification-and-the-loop-contract.md) | Layered verification, a machine-picked next task, and the loop contract | Accepted |
| [0043](0043-the-deploy-runs-on-a-runner-on-the-server.md) | The deploy runs on a runner on the server, started from the overlay's private repository | Accepted |
| [0044](0044-shared-workspaces-sync-together.md) | Shared workspaces sync together; a person's lists are their own work — `owned`, the task scope, and three seam additions (write refusals, described deletions, reminder audiences) | Accepted |
| [0045](0045-rate-limits-count-who-is-asking.md) | Rate limits count who is asking — a verified access token is its user, credential endpoints count per IP + account under a per-IP ceiling, and every 429 carries `RATE_LIMITED` + `retryAfter` | Accepted |
| [0046](0046-the-app-follows-a-team-address.md) | The app follows a team's address — an invitation's `server` is trusted only as a sibling of the server already in use, and moving to the team's address keeps the session | Accepted |
| [0047](0047-oauth-client-id-metadata-documents.md) | The MCP authorization server accepts client ID metadata documents beside registration — an https `client_id` is fetched behind an SSRF fence, mapped to an ordinary client row, and shown with its host on the consent page | Accepted |
| [0048](0048-docx-export-own-ooxml-writer.md) | Word export is our own OOXML writer, drawn with the PDF's style — `note_docx.dart` zips hand-written parts with `archive`; colours, sizes and margins live once in `note_print_style.dart` for both writers; exports stay client-side | Accepted |
| [0049](0049-mcp-consent-social-sign-in-and-second-factor.md) | The MCP consent page offers Google / Apple through a server-side OIDC form_post redirect bound by a signed state + nonce and a pinned audience; it never creates an account, and both consent paths now ask for the second factor and run the sign-in policy | Accepted |
| [0050](0050-apple-calendar-read-back-on-device.md) | Apple Calendar read-back runs on the device with Google's semantics — time only onto `scheduled_*` via the store/outbox, content-based echo from the link signature (1-minute tolerance), a deleted event suppresses that task in that calendar on that device only (replica v38), deletion believed only after url recovery and a mass-vanish guard; one thin `readEvents` in Swift | Accepted |
| [0052](0052-importing-from-other-apps.md) | Todoist and TickTick exports are parsed on the server (one route, `dryRun` = the preview) and written through the domain layer one item per transaction; an `import_ledger` keyed by the source's id or, for Todoist, a date-free fingerprint makes re-imports skip and never resurrect; batches of `maxItems`; imported tasks never arm urgent alarms; no MCP tool | Accepted |
| [0053](0053-task-when-and-duration.md) | Three task times are never merged: `start_at` is "when" (the day a task enters Today, stored as local midnight, picked as a day) beside `due_at` (alarm, Overdue) and `scheduled_*` (calendar drag); the plan-day rule files Home, widgets, AI context and the MCP today view; "when" is per occurrence, duration is a series field; calendar blocks are `estimated_minutes` long (default 30, clamped to the day) | Accepted |

> Rows 0024–0027 were missing until 2026-08-10 (OPH-242): four ADRs had landed
> without an index line. 0028 was held as a **reserved** row while OPH-246 was
> open, so the number could not be reused — this round had already corrected two
> documents that gave the share decision that number. It landed on 2026-08-10.
>
> **It happened again.** Rows 0031 and 0032 were missing until 2026-08-18
> (OPH-274) — the same drift, two rounds after it was first corrected, which
> says the correction was a fix and not a guard. An ADR nobody can find from
> the index is an ADR the next agent re-litigates.

Template: [template.md](template.md)
