# ADR-0059 — CalDAV connector: iCloud and any CalDAV server, two-way, from the server

- **Status:** Accepted
- **Date:** 2026-10-17
- **Related task:** OPH-380
- **Related:** [CALDAV.md](../CALDAV.md) (the OPH-079 design this builds),
  [ADR-0003](0003-product-name-and-blueprint-deviations.md) (mapping keys),
  [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (secret crypto, queue),
  [ADR-0007](0007-google-inbound-sync-and-conflict-policy.md) (the conflict matrix),
  [ADR-0008](0008-external-calendar-events.md) (the user's own events, read-only),
  [ADR-0021](0021-calendar-mirror-v2.md) (what mirrors), [ADR-0047](0047-oauth-client-id-metadata-documents.md)
  (the SSRF fence), [ADR-0050](0050-apple-calendar-read-back-on-device.md) (EventKit read-back).

## Context

Google Calendar is mirrored by the server, so it works on every platform. Apple Calendar is
mirrored by EventKit on the device, so a person on the web, Android, Windows or Linux whose
calendar lives in iCloud gets nothing, and neither does the self-hoster on Linux + Nextcloud.
CALDAV.md (OPH-079) designed a server-side connector and left seven questions open. This ADR
answers them and records what was built.

## Decision

1. **Protocol.** Discovery = `PROPFIND` current-user-principal (RFC 6764 well-known first for a
   bare host) → calendar-home-set → the home's calendars (VEVENT collections only; no component
   set = all). Inbound = RFC 6578 `sync-collection` (paged on 507) → `calendar-multiget` for
   changed hrefs whose etag is not the link's (echoes are never fetched). Outbound = `PUT
   If-None-Match: *` at a **deterministic href** `<calendar>/alliswell-<taskId>.ics` to create
   (a 412 there is adoption, not a duplicate), GET → merge our fields → `PUT If-Match` to
   update (no PATCH exists; foreign properties — alarms, colour, location, X-APPLE-* — are
   kept), `DELETE If-Match` to remove (412 → local is canonical, delete the fresh one). The
   etag of every write is stored; a server that omits `ETag` is asked by `PROPFIND getetag`.
2. **One provider value.** Every CalDAV account uses the existing `apple_caldav` enum value in
   `calendar_accounts`, `calendar_event_links` and `calendar_external_events`; a new
   `caldav_kind` column says `icloud` or `generic`. No ENUM `MODIFY` migration (MariaDB and
   rollback risk); the API serializes `provider: 'caldav'` + `server`, so the misleading
   internal name never reaches a public surface. New columns: `encrypted_app_password`,
   `caldav_kind`, `caldav_server_url`, `principal_url`, `calendar_home_url`,
   `calendar_display_name`. `default_calendar_id` holds the calendar's path,
   `provider_event_id` the event href, `provider_event_uid` the task id.
3. **The event.** UID = task id; DTSTART/DTEND in UTC (no VTIMEZONE to get wrong);
   `URL:alliswell://task/<id>` (ADR-0003); `X-ALLISWELL-TASK-ID`/`-WORKSPACE-ID`; SEQUENCE.
   No DESCRIPTION marker — four recovery paths already exist (link table, X-prop, URL, href,
   then a ULID-shaped UID), always checked against the account's workspace. Title and block
   come from `desiredBlockForTask`, the provider-neutral half `desiredEventForTask` now encodes
   for Google, so the two mirrors cannot drift.
4. **Same semantics as Google.** The reconcile (`applyProviderEvent`, `lib/inbound.js`) is
   shared through a small provider adapter (`provider`, `calendarId`, `eventUid`,
   `deleteEvent`, `pushTask`): a drag writes `scheduled_*`, never `due_at`; a user delete keeps
   the task and leaves the `provider_deleted_local_exists` tombstone with
   `calendar_mirror_suppressed_at`; both-changed is last-write-wins; a series is flagged. A
   **foreign etag seen by the mirror before it writes** runs that reconcile first, so a drag
   made between two polls is applied rather than overwritten. A 404 member in the sync report
   is the CalDAV spelling of `cancelled`; a full listing treats unlisted linked hrefs the same
   way (tombstones excepted).
5. **Sync-token rejection** is matched on the DAV precondition `valid-sync-token` **or any 4xx
   (except 401/404) to a non-empty token** — never on one status code: RFC 6578 prescribes
   none, and Radicale answers 403 where Google answers 410. The cure is Google's: resync from
   an empty token.
6. **Credentials** (CALDAV.md §3, binding): AES-256-GCM under `CALENDAR_TOKEN_KEY`
   (`lib/crypto.js`, no new crypto); discovery must succeed **before** anything is stored;
   the serializer has no path to the ciphertext; disconnect nulls it and the app tells the
   user to revoke the password at appleid.apple.com (we cannot). A 401 flips the account to
   `error` (reconnect) instead of retrying.
7. **Network policy.** Hand-rolled HTTP on `node:http(s)` — `fetch` cannot take a custom DNS
   lookup — with, per request and per redirect hop: https only; a **host policy** (iCloud:
   the configured iCloud host and `pNN-caldav.icloud.com`; generic: the host the user typed),
   so Basic auth is never sent to another host and an off-host redirect is refused; the
   ADR-0047 blocklist at connect time (shared now as `lib/net-guard.js`) and for IP literals;
   a 15 s timeout, a 10 MB ceiling, 2 requests in flight per host, and 429/503 retried while
   obeying `Retry-After`. `CALDAV_ALLOW_PRIVATE_HOSTS=true` lifts the https and address rules
   for a LAN Nextcloud — and lets every user of that instance reach the LAN; SELF-HOSTING.md
   says so.
8. **Off by default.** `CALDAV_ENABLED=false`: holding calendar passwords is an admin's
   deliberate choice. With it on, production refuses a placeholder `CALENDAR_TOKEN_KEY`.
   While off, nothing mirrors or syncs, connect answers 503 `CALDAV_NOT_ENABLED`, and status
   and disconnect keep working so a password is never stranded.
9. **Polling.** CalDAV has no push: the existing calendar sweep (`CALENDAR_SYNC_SWEEP_SEC`,
   300 s) enqueues every active CalDAV account; an empty sync-collection is one small REPORT.
10. **The user's own events** are cached for display exactly like Google's (ADR-0008); a
    repeating one is expanded by `ical.js` inside the existing window (cap 500 instances per
    resource), each instance id `sha1(href)#<original start>`, and instances the series no
    longer produces are tombstoned.
11. **Where it is offered.** The iCloud option only off Apple devices (on an iPhone or Mac the
    EventKit card is the iCloud path, and an app-specific password is asked only in sessions
    without an Apple device); generic CalDAV everywhere; an existing account's status and
    disconnect everywhere; hidden in shared workspaces like Google. One CalDAV account per
    user per workspace (reconnecting the same identity updates the password; another is 409).
12. **No double mirror on Apple devices.** When the server mirrors the workspace into iCloud,
    the device's EventKit mirror deletes the events it created and stands down, and its card
    says why; the flag is persisted for offline launches and rewritten on every status load.
13. **Rule 12.** Public API: status, calendars, choose and disconnect accept API keys, as
    Google's do; **connect is session-only** — it stores a long-lived third-party credential
    and opens a standing outbound channel, and a leaked key must be able to do neither. MCP:
    no tool (MCP.md): calendar connections are set up in the app and the connector never
    handles a calendar password — Google has no MCP tool either.
14. **VTODO is not built.** VTODO carries one LAST-MODIFIED for every field, so honest
    field-level conflict handling (BLUEPRINT §6.5) needs its own design, and "AllisWell as a
    CalDAV server" may serve DAVx5/Thunderbird users better. CALDAV.md §9 specifies both; the
    owner chooses.

### Dependencies (a new category — RFC 5545 and WebDAV XML)

- **`ical.js` 2.x** (MPL-2.0, ESM, no dependencies): folding, escaping, TZID resolution
  (embedded VTIMEZONEs; bare TZIDs fall back to the runtime's IANA data via `lib/time.js`;
  floating time is the account owner's zone) and RRULE/EXDATE/RECURRENCE-ID expansion.
- **`fast-xml-parser` 5.x** (MIT) for multistatus parsing, namespace prefixes stripped (Radicale
  writes the default namespace, Nextcloud `d:`, iCloud upper case). Any body with a DTD is
  refused before parsing, so no declared entity can expand.
- **`tsdav` was rejected:** it is `fetch`-based (the guarded lookup cannot apply) and brings
  far more surface than five verbs.

### Testing

Two layers (CALDAV.md §7.4): an in-process fake (`test/helpers/fakecaldav.js`) for the
documented contract plus the iCloud quirks (partition home, PUT without ETag, 403
`valid-sync-token`, 429 `Retry-After`, an off-host redirect), and a **real Radicale 3.8.3** in
docker (compose service and a CI `docker run` step) for the protocol end to end. Real iCloud and
real Nextcloud are the owner's manual checks (DEVICE-CHECKS.md); until then public copy says
"tested against Radicale".

## Consequences

- Positive: an iCloud or Nextcloud calendar works from the web, Android, Windows and Linux,
  two-way, with Google's rules — and generic CalDAV comes with it for free.
- Positive: the shared reconcile and `desiredBlockForTask` keep Google and CalDAV from
  drifting; the SSRF fence now has one copy.
- Negative: this server can hold live iCloud credentials. Mitigated by off-by-default,
  encryption, verify-before-store, the host policy and honest disconnect copy — but a database
  plus key leak would hand them over until the user revokes them.
- Negative: polling, not push — a change in the calendar lands within one sweep (≈5 min).
- Negative: connecting re-runs the workspace backfill, so a connected Google account also gets
  one converging PATCH per task in the window.
- Unproven until the owner's check: iCloud's X-property survival, partition behaviour and its
  sync-token rejection status. The design does not depend on any of them.

## Alternatives considered

- **A new `caldav` provider enum value:** an ENUM `MODIFY` on three tables for a name — the
  serializer already hides the internal value.
- **ctag polling instead of sync-collection:** a full listing every poll; iCloud, Nextcloud and
  Radicale all support RFC 6578.
- **Retiring EventKit for iCloud users on Apple devices:** EventKit needs no password at all,
  so on an Apple device it stays the iCloud path; only a server-side iCloud account retires it.
