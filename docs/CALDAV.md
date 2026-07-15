# CALDAV.md — Apple CalDAV connector design (OPH-079, v2 scope)

> **Status: design only. Nothing here is built.** This is the plan an agent picks up when the
> CalDAV connector is scheduled (BLUEPRINT §7.3 Level 3). It is written now because the choice
> it documents — asking users for an iCloud app-specific password — is the most
> security-sensitive thing AllisWell would ever do, and that decision deserves writing down
> *before* someone is halfway into the code (AGENTS.md rule 10).
>
> Related: [ADR-0003](adr/0003-product-name-and-blueprint-deviations.md) (mapping keys),
> [ADR-0006](adr/0006-google-oauth-token-crypto-and-mirror-queue.md) (token crypto, queue),
> [ADR-0007](adr/0007-google-inbound-sync-and-conflict-policy.md) (the sync shape this reuses).

## 1. Why a CalDAV connector at all

EventKit (OPH-077/078) is an **on-device** bridge: it syncs Apple calendars for the person
holding an iPhone or a Mac. That leaves a real hole:

- the **web** app, **Windows**, **Linux** and **Android** users whose calendar lives in iCloud;
- any **headless** flow — a task changed by another device, by the API, or by the mirror queue
  while no Apple device is awake.

Google's integration is server-side and therefore always-on (Epic 08). Apple has no equivalent
public API. CalDAV is the only server-side path to iCloud, which is exactly why it is worth the
trouble — and exactly why it is v2, not v1: the credential model is bad enough (§3) that it
must not be the *first* Apple experience a user meets.

## 2. Scope

**In:** connect an iCloud account, discover calendars, mirror tasks → events, consume remote
changes, the same two-way conflict policy as Google.

**Out (v2 too):** other CalDAV servers as a supported product (Fastmail, Nextcloud, Radicale
will very likely work — the protocol is standard — but only iCloud is *tested* and only iCloud
is claimed); scheduling/invitations (RFC 6638); VTODO sync (AllisWell tasks are not VTODOs —
see §7); free/busy.

## 3. The security problem — read this before writing any code

**An iCloud app-specific password is not an OAuth token.** The difference is not academic:

| | Google (Epic 08) | iCloud app-specific password |
| --- | --- | --- |
| Scope | calendar only, granted per-scope | **the whole service the credential can reach** |
| Expiry | access token ~1 h, refresh rotates | **never expires** |
| Revocation | per-app, by the user, at any time | per-password, at appleid.apple.com |
| Server sees | tokens, never the password | a **long-lived account credential** |
| If our DB leaks | attacker gets calendar access until revoked | attacker gets a live iCloud credential |

Consequences that are **binding** on the implementation:

1. **Encrypt at rest with the ADR-0006 machinery** — `src/lib/crypto.js`, AES-256-GCM under
   `CALENDAR_TOKEN_KEY`. No new crypto. Unlike a channel token (OPH-074) this **cannot** be
   hashed: we must replay it on every request, so it is reversible by construction. That is
   precisely why the rest of this list exists.
2. **Never log it, never return it, never echo it.** Same posture as
   `serializeAccount` today: the serializer must have no code path that can reach the
   ciphertext, let alone the plaintext.
3. **The UI must tell the truth, in the user's words** — not a shrug-emoji disclaimer. The
   connect screen states: this password is stored on *your own server*; it can be revoked at
   appleid.apple.com at any time; use an app-specific password and **never** your Apple
   account password; and if you self-host on someone else's machine, they can read your
   calendar. This is a §12-style plain-language warning, no jargon (feedback round 1: no
   technical concepts in end-user UI — but a security decision the user is *making* is not
   jargon, it is informed consent).
4. **Fail closed on a placeholder key.** Production already refuses a placeholder
   `CALENDAR_TOKEN_KEY` when Google is configured; extend that guard to the CalDAV
   connector being enabled.
5. **Verify before storing.** A connect attempt must complete discovery (§4) successfully
   before anything is persisted — never store a credential we have not proven works, or the
   user gets a silently broken account and a live password sitting in a database for nothing.
6. **Disconnect must be honest.** We cannot revoke an app-specific password from our side
   (no API). Disconnect NULLs the ciphertext and the UI must tell the user the second half of
   the job is theirs: revoke it at appleid.apple.com. Anything less implies a revocation we
   did not perform.

**Recommendation:** ship the connector **disabled by default**, behind an explicit
`CALDAV_ENABLED=true`, so a self-hoster opts into holding this class of secret deliberately.

## 4. Protocol

### 4.1 Discovery

iCloud is `https://caldav.icloud.com` over TLS, Basic auth: Apple ID + the 16-character
app-specific password. A 401 with credentials the user swears are correct almost always means
they pasted their *account* password — say so in the error, it is the single most common
failure.

Three steps, in order:

1. `PROPFIND /.well-known/caldav` (or `/`) → `DAV:current-user-principal`
2. `PROPFIND <principal>` → `CALDAV:calendar-home-set`
3. `PROPFIND <calendar-home>` `Depth: 1` → the calendar collections
   (`DAV:displayname`, `CALDAV:supported-calendar-component-set`, `CS:getctag`,
   `http://apple.com/ns/ical/:calendar-color`)

**The home set comes back on a per-account partition host** (`p34-caldav.icloud.com`,
`p67-…`). It is assigned per account and it is not stable across accounts — hardcoding one
user's host breaks every other user. Persist what discovery returns and re-run discovery when
a request starts failing.

Filter calendars to those whose `supported-calendar-component-set` includes `VEVENT`.

### 4.2 Sync

iCloud supports RFC 6578 collection synchronization — use it, not ctag polling:

- `REPORT` with `DAV:sync-collection`, containing `DAV:sync-token`, `DAV:sync-level` (`1`) and
  `DAV:prop` (ask for `DAV:getetag`).
- **Initial sync** = empty `DAV:sync-token` → every member URL.
- **Incremental** = the token from last time → only what changed.
- Changed members answer with `DAV:propstat` and no `DAV:status`; **deleted** members answer
  `DAV:status` `404 Not Found` and no `DAV:propstat`. That is the CalDAV spelling of Google's
  `status: cancelled`.
- The token is **opaque** — store it verbatim (`calendar_accounts.sync_token`, already
  varchar(500)), never parse it.
- Keep paging until a response returns no more changes.

**Token invalidation:** RFC 6578 defines the `DAV:valid-sync-token` precondition but does
*not* prescribe a status code for violating it (servers in practice answer `403`). So do not
match on a status: treat **any** sync-token rejection as "resync with an empty token". This is
the same shape as Google's `410 → full resync` (ADR-0007), and for the same reason: a full
resync is cheap because `calendar_event_links` is keyed per event and every event reconciles
itself on the way through.

### 4.3 Writes and concurrency

- **There is no PATCH.** Load the resource, change it, `PUT` the whole VEVENT back. Our
  outbound derivation is already whole-event (`desiredEventForTask`), so this costs nothing —
  but the *inbound* side must keep the untouched parts of a foreign VEVENT intact rather than
  rebuilding it from our fields.
- **Create:** `PUT` with `If-None-Match: *` — fails if something is already at that href.
- **Update:** `PUT` with `If-Match: <etag>` — a `412 Precondition Failed` **is** the
  "provider changed it" signal, and maps onto ADR-0007's conflict matrix directly.
- **Delete:** `DELETE` with `If-Match: <etag>`.
- Capture the `ETag` from every response. If a server omits it on write (allowed), re-`GET`
  the href — an unknown etag breaks echo suppression, which is load-bearing (ADR-0007 §4).

### 4.4 Identity of an event

- **href** = the resource URL, our `calendar_event_links.provider_event_id`. Choose it
  ourselves on create: `<calendar-home>/<calendar>/alliswell-<taskId>.ics`.
- **UID** = the iCalendar UID inside the VEVENT, our `provider_event_uid`. Use the task ULID.
- **The AllisWell marker**: ADR-0003 already fixed this for non-Google providers —
  `URL:alliswell://task/{taskId}` in the VEVENT, plus a machine-readable marker in
  `DESCRIPTION`. CalDAV has no `extendedProperties`; `X-ALLISWELL-TASK-ID` is a legal
  X-property and is the better mapping key, but **iCloud may drop unknown X-properties** — so
  the mapping **table** is the source of truth (as always) and the `URL` field is the recovery
  path. Verify X-property survival against real iCloud before relying on it.

## 5. What already fits

`calendar_accounts` / `calendar_event_links` were designed for this in OPH-015 and need **no
redesign**: `provider` already enumerates `apple_caldav`; `provider_event_uid` exists for the
iCal UID next to `provider_event_id` for the href; `etag`, `sync_token`,
`last_provider_updated_at`, `sync_direction` and the `conflict_status` enum all carry over
verbatim.

One append-only migration adds what is genuinely new:

```
calendar_accounts:
  encrypted_app_password   text     -- NOT encrypted_access_token: it is a password,
                                    --   not a token, and the column name should not lie
  principal_url            varchar(500)
  calendar_home_url        varchar(500)  -- the partition host lives here
```

`token_expires_at`, `webhook_*` and `sync_dirty_at` stay NULL for this provider: **CalDAV has
no push**. There is no webhook to receive, so inbound sync is polling-only — which is already
a first-class mode, because OPH-074 built it for webhook-less Google installs
(`CALENDAR_SYNC_SWEEP_SEC`). The sweep just treats an `apple_caldav` account as permanently
channel-less.

## 6. What to reuse, and what to generalize

The Epic 08 shape is deliberately provider-shaped, not Google-shaped:

- `src/queue/runner.js` — provider-agnostic already.
- `src/lib/mirror.js` (`desiredEventForTask`) — pure derivation; needs a **serializer split**:
  today it returns a Google event resource. Extract the decision (which time window, which
  title, gone-or-not) from the encoding (Google JSON vs VEVENT/ICS).
- `src/lib/inbound.js` (`reconcileProviderEvent`) — the conflict matrix is already pure and
  provider-neutral **except** that it reads `event.status === 'cancelled'`, `event.etag`,
  `event.updated`, `event.start/end` and `event.recurrence`. Feed it a normalized
  `{id, etag, updated, start, end, recurrence, cancelled, taskId}` and the whole of ADR-0007 —
  echo suppression, scheduling-not-deadline, the four conflict states, the
  provider-deleted tombstone — applies to iCloud unchanged. **Do this normalization first**;
  it is the difference between a connector and a second copy of Epic 08.
- `db/calendar.js` — `getFreshAccessToken` is OAuth-specific; CalDAV needs a sibling that just
  decrypts. Keep the "credential rejected → account `status: error` + `…REAUTH_REQUIRED`"
  behaviour: a revoked app-specific password must surface, not decay silently.

No CalDAV client library is proposed for the same reason ADR-0006 skipped the Google SDK: the
surface is PROPFIND/REPORT/PUT/DELETE plus an iCalendar serializer. An ICS library
(`ical.js`) **is** worth taking — hand-rolling RFC 5545 line folding, escaping and timezone
handling is a bug farm, and unlike HTTP it is not a small surface. That is a new dependency
category → its own ADR when the time comes (AGENTS.md rule 6).

## 7. Open questions — resolve these before implementing

1. **Tasks as VEVENT, not VTODO.** iCloud Reminders are VTODOs in a separate collection.
   AllisWell mirrors tasks as calendar *blocks* (§7.1), so VEVENT is right for the mirror —
   but a user seeing "[Task] …" in Calendar rather than Reminders is a product call worth
   making explicitly, and two-way Reminders sync is a different (larger) feature.
2. **Rate limits are undocumented.** Apple publishes none for CalDAV. Assume they exist:
   respect `Retry-After`, back off on 429/503, and do not let the sweep hammer a partition.
   Measure before choosing a poll interval.
3. **X-property survival** (§4.4) — must be tested against real iCloud, not assumed.
4. **Testing without Apple.** Google's suite runs against an in-process fake
   (`test/helpers/fakegoogle.js`) and real Google is not in CI. Do the same: a fake CalDAV
   server modelling the *documented* contract, plus a manual verification checklist against a
   real iCloud account (like Epic 07's device pass). A real Radicale in CI is a tempting
   middle ground — it proves the protocol, but it is not iCloud, so it cannot prove the
   quirks. Decide deliberately.
5. **Where the warning lives.** §3.3's consent text must be reviewed as *product copy*, not
   left to the implementing agent.

## 8. References

1. [RFC 4791 — Calendaring Extensions to WebDAV (CalDAV)](https://datatracker.ietf.org/doc/html/rfc4791)
2. [RFC 6578 — Collection Synchronization for WebDAV](https://datatracker.ietf.org/doc/html/rfc6578) — `sync-collection`, opaque tokens, 404 for removed members, `DAV:valid-sync-token`
3. [RFC 5545 — iCalendar](https://datatracker.ietf.org/doc/html/rfc5545)
4. [RFC 6638 — Scheduling Extensions to CalDAV](https://datatracker.ietf.org/doc/html/rfc6638) (out of scope; listed so the boundary is explicit)
5. [RFC 4918 — HTTP Extensions for WebDAV](https://datatracker.ietf.org/doc/html/rfc4918) — PROPFIND, multistatus, If-Match/If-None-Match semantics
6. [Apple — Sign in with app-specific passwords](https://support.apple.com/en-us/102654)
7. [Aurinko — Demystifying CalDAV: Apple Calendar integration](https://www.aurinko.io/blog/caldav-apple-calendar-integration/) — partition hosts, "no patching", etag handling
8. [Nylas — iCloud CalDAV settings](https://cli.nylas.com/guides/icloud-caldav-settings) — endpoint, Basic auth, app-specific password requirement
9. [Tasks.org — iCloud CalDAV synchronization](https://tasks.org/docs/caldav_icloud/) — a shipped Android client's account of the same flow
