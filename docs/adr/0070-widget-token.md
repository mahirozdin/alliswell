# ADR-0070 — Widget identity: a non-rotating, read-only widget token

- **Status:** Accepted
- **Date:** 2026-11-12
- **Related task:** OPH-457, OPH-458, OPH-459, OPH-460, OPH-462, OPH-463, OPH-464 (issue #50)
- **Related:** [ADR-0010](0010-home-screen-widgets-architecture.md) §5,
  [ADR-0032](0032-api-keys.md) (the key pattern this copies),
  [ADR-0038](0038-server-to-device-delivery.md) §8,
  [ADR-0069](0069-urgent-alarm-device-is-a-server-flag.md) §6 (device ↔ session family),
  [ADR-0071](0071-shared-keychain-group-after-first-unlock.md) (where the token is kept);
  contract: [WIDGETS.md §3.2](../WIDGETS.md#32-widget-self-fetch-contract-ios-50)

## Context

Issue #50 asks that the home-screen widget follow changes made on another device "with the app
not open (backgrounded **and swiped away**)". The ADR-0010 revision of 2026-11-12 gave the snapshot
three day views, so the date moves at midnight, but the data still ages from the last time the app
ran. On iOS no app code runs after a force-quit: `BGAppRefreshTask` is not scheduled and a silent
push is discarded. Both stay off in this round (ADR-0038 §8). What still runs is the widget
extension's own timeline, and a WidgetKit extension may make a network request while it builds one.

The extension needs an identity to call the server with. What exists does not fit:

- **The access JWT** lives 15 minutes (`AUTH_ACCESS_TTL_SEC`); the widget would answer 401 a
  quarter of an hour after the app closed.
- **A refresh family of its own** would rotate. Several widget instances and the lock-screen
  accessories build timelines in parallel, two `/auth/refresh` calls on one family burn the whole
  family (reuse detection), and the widget would sign itself out for good. The extension would also
  need a rotation lock written in Swift.
- **An API key** (`awk_`) can write, is bound to one workspace, and is a user-managed credential
  shown in Settings; a device must not mint one silently.

## Decision

1. **A separate token class, `aww_`.** Opaque random value with the `aww_` prefix, returned
   **once** by `POST /api/v1/widget-tokens {deviceId}` and stored only as an HMAC-SHA256 hash
   with its own domain separator (`widget:`; `hashWidgetToken` in `lib/tokens.js`, the
   `hashApiKey` pattern of ADR-0032). Table `widget_tokens`: `id, user_id (FK users, cascade),
   device_id, session_family_id, token_hash, created_at, expires_at, last_used_at, revoked_at`,
   `UNIQUE(user_id, device_id)`. No push columns (WidgetKit push is not in this round).
2. **Minting needs a session.** The route takes a session JWT only: `app.rejectApiKeys` (a key
   cannot mint a credential), the `deviceId` must be one of the caller's `notification_devices`
   rows, and the token records the minting session's `family_id`. Minting again for the same
   device revokes the previous token in the same transaction (one live token per device).
3. **Scope is one endpoint, read-only.** Only the new `app.authenticateWidget` decorator accepts an
   `aww_` bearer, and only `GET /api/v1/widget/snapshot` uses it. `app.authenticate` is **not
   changed**: an `aww_` value is not `awk_`, so it goes to `jwtVerify` and fails with
   `AUTH_INVALID_TOKEN` on every other route, `/auth/refresh` included, where no `refresh_tokens`
   row matches and no family is touched. The rate bucket is the token hash (ADR-0045), 30 requests
   an hour; `last_used_at` is written at most once a minute.
4. **It never rotates.** Life is 90 days from minting. The app re-mints in the foreground when
   fewer than 30 days remain, or when the extension has marked it invalid. There is no refresh
   call, so there is no family race and no lock (the refresh-lease idea is void for the widget).
5. **Revocation.** Explicit: removing the device (`DELETE /notification-devices/:id`), sign-out,
   sign-out everywhere, revoking a session, a password change, account deletion (cascade).
   Implicit and race-free: `authenticateWidget` also requires that the minting family still has a
   **live** row (`refresh_tokens.family_id = session_family_id`, not revoked, not rotated, not
   expired). Rotation keeps the family id and commits the new row in the same transaction, so an
   app refresh never makes a widget request fail; every event that kills the family (reuse
   detection, password change, session revoke) kills the widget token with it. The effective life
   is therefore the shorter of 90 days and the family's (`AUTH_REFRESH_TTL_DAYS` since the app last
   refreshed). Every refusal is one 401 `AUTH_WIDGET_TOKEN_INVALID`; the reason is not disclosed.
6. **The response carries no words.** The server groups but never localises: bucket keys, raw
   instants and a `timeStyle`, never a label or a formatted date. Labels and date patterns come from
   what Dart wrote to the App Group. With `private=1` (also the default) no `title` field is sent
   at all.
7. **Grouping has two implementations locked to one fixture.** The rules (buckets, the +7/+30
   limits, events, `openToday`, `next`, 12 rows + `more`, project views, `timeStyle`) are Dart's;
   `apps/api/src/lib/widget-grouping.js` is a second implementation, and both `flutter test` and
   Vitest run `apps/app/test/fixtures/widget_grouping_cases.json` case by case (the
   recurrence/fold/project-match pattern: change one side alone and the other fails). **DESIGN §8
   W9 is revised:** *Dart defines the rule; the server is a second implementation locked to the
   same fixture; native code still carries no rule.* Swift picks a day and a snapshot, never a
   bucket.
8. **REST only (I-12).** `/widget-tokens` and `/widget/snapshot` are device infrastructure: the
   task data they show is already readable through REST and MCP, and minting a credential has no
   place in MCP. They enter the OpenAPI document like every route.

## Alternatives considered

- **Share the access JWT or give the widget a refresh family** — rejected for the reasons in the
  context: 15 minutes of life, or a rotation race that signs the widget out.
- **Compile the Dart grouping to JS** (`dart compile js`) — one implementation, but it drags
  `easy_localization`, `intl` and the task model into a fragile build step. The fixture costs less.
- **Grouping in Swift** — a third copy in the one language that has no test in CI on Linux, and a
  direct breach of W9.
- **A 30-day sliding token renewed every 7 days** (the first research draft) — more mints for the
  same safety; the family check already bounds a token whose app is gone.

## Consequences

- **Easier:** a swiped-away iPhone widget refreshes within WidgetKit's budget (typically every
  15–60 minutes; no minute guarantee). Session handling and the refresh chain are untouched.
- **Harder:** a new auth surface on a critical path (`.claude/rules/auth.md` lists its files and
  test); a second grouping implementation that must be kept equal by the fixture.
- **Leak impact, accepted:** a stolen `aww_` value reads that user's widget view (titles unless
  private, at most 30 days ahead) until it expires, the device is removed or the session ends. It
  cannot write, reach MCP, AI or account routes.
- **Self-hosters** get the same path; nothing new in `.env`.
- **Follow-ups (candidates):** WidgetKit push over direct APNs (needs the owner's `.p8`); the macOS
  widget's self-fetch.
