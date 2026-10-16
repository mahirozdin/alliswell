# ADR-0050 — Apple Calendar read-back on the device

- **Status:** Accepted
- **Date:** 2026-10-16
- **Related task:** OPH-369

## Context

The Apple mirror (OPH-078) wrote tasks into the user's chosen EventKit calendar and never
read them back: a block dragged in Apple Calendar was overwritten by the next outbound pass.
Google has had the return path on the server since OPH-076 (ADR-0007): a moved or resized
event writes the task's `scheduled_start_at`/`scheduled_end_at`, a deleted event stops the
mirror (ADR-0021 §3), both-sides edits are settled by last-write-wins (BLUEPRINT §6.5).

Apple publishes no server API, so the Apple half can only run where the calendar lives —
on the iPhone or Mac. The constraints: the native plugin must stay thin (Swift cannot be
compiled or tested in CI or on the Linux dev machine, LESSONS `ios-native`); writes go
through the local-first stores and outbox (AGENTS §4); EventKit has no etag and no push to a
backgrounded app; its identifier changes on an iCloud move (LESSONS `calendar`); iCloud and
CalDAV keep whole seconds.

## Decision

1. **Same semantics as Google** (`lib/inbound.js`), decided purely in Dart
   (`features/calendar/apple/apple_read_back.dart`), executed by `AppleMirrorEngine`:
   - Only time flows back, onto `scheduledStartAt`/`scheduledEndAt` via `TaskStore.update`
     (replica row + outbox) — never `dueAt`, never title or notes. The server then mirrors
     the new block to Google like any other edit.
   - The event is compared with the block §7.1 derives, not the raw columns.
   - A recurring event, or one whose end is not after its start, is flagged and nothing is
     written on either side.
   - An all-day event maps to local midnight → the midnight after its last day (Google's
     exclusive `end.date`), whether EventKit reports the end as 23:59:59 or the next midnight.
   - Both sides changed → last-write-wins on `EKEvent.lastModifiedDate` against the task's
     `updatedAt` (now carried on the `Task` model). If either is missing the task wins —
     the replica/server is canonical (AGENTS §6).
2. **Echo suppression is content-based.** The link's existing signature
   (`title|startIso|endIso`) already holds the times we last wrote; an event showing them
   (within one minute — iCloud truncates to seconds, a real drag moves by five) is our own
   write. No new "written" columns.
3. **Deleting the event suppresses that task in that calendar, on that device.** New nullable
   `apple_event_links.suppressed_at` (replica v38). The task is never deleted and the event
   never recreated there; choosing a different calendar is a fresh request and recreates it.
   It is NOT written to the synced `tasks.calendar_mirror_suppressed_at`: Google mirroring
   and other devices' calendars stay as they are, and no sync field changes.
4. **Deletion is believed only after checks.** A link's calendar missing from `calendars()`
   (or no calendars at all) is "unreachable", not "deleted". A missing event is looked up
   again by its `alliswell://task/{id}` url within ±90 days of the last-written window and
   re-linked if found. If more than three AND more than half of the checked events vanish
   in one pass (iCloud sign-out, a store resync), nothing is suppressed that pass. A build
   whose native side cannot read back answers `null`, never `[]`.
5. **Ordering.** Read-back runs before the outbound pass in the same serialised job. On
   apply the link's signature is updated FIRST, then the task is written, and the applied
   tasks are skipped by that pass's outbound reconcile (their task objects are stale). The
   task write's own replica emit then reconciles to a no-op, so an all-day event stays
   all-day.
6. **Triggers are foreground only:** a full read-back on the first pass and every app
   resume (macOS: window activation), plus a one-event look before every outbound update so
   a fresh drag is not overwritten by a pulled change (a miss there never suppresses).
   Passes are serialised and coalesced in the engine. No `EKEventStoreChanged` channel and
   no background read.
7. **Native change:** one method, `readEvents(ids)`, in the shared
   `AlliswellEventkitPlugin.swift` (macOS symlinks to it) — returns
   id/calendarId/url/startMs/endMs/isAllDay/hasRecurrence/lastModifiedMs for each id
   EventKit still resolves (after `refresh()`), and omits the rest. No policy in Swift.
8. **Rule 12:** no new entity, field or operation. The read-back is a device-only EventKit
   bridge writing `scheduledStartAt`/`scheduledEndAt`, which MCP `update_task` and the
   public API already expose; Apple Calendar has no server presence to expose.

Public copy stays "mirrored one way for now" and the `check:docs` APPLE_CLAIMS gate stays
on until the owner confirms the loop on a device (docs/DEVICE-CHECKS.md).

## Alternatives considered

- **Write the deletion to `tasks.calendar_mirror_suppressed_at`.** Rejected: it would stop
  the Google mirror and every other device's Apple mirror because one calendar on one
  device lost an event, and the column means "the provider deleted it" on the server.
- **Store the written times in new columns.** Rejected: the signature already holds them.
- **An `EKEventStoreChanged` event channel.** Rejected for v1: more Swift that cannot be
  built here, and the store only notifies a running app — resume covers the same moments.
- **Compare exact instants.** Rejected: every iCloud round-trip of a task whose time carries
  milliseconds would read as a drag and pin it to `scheduled_*`.

## Consequences

- Apple users get the Google loop on the device: drag/resize in Calendar → the task's
  scheduled block (and the "Moved in calendar — Reset" row ADR-0007 added) follows.
- The read-back cannot run while the app is closed; an edit waits for the next foreground.
- Clock skew between devices can pick the wrong winner in a simultaneous edit — the risk
  Google's path accepts too.
- A far iCloud re-identification outside the ±90-day window would read as a deletion;
  re-picking the calendar resets it.
- The Swift is unverified until an Xcode build and the device check in DEVICE-CHECKS.md.
