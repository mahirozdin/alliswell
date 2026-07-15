# ADR-0008 — Your calendar, in AllisWell: external events as a read-only sync entity

- **Status:** accepted (2026-07-16)
- **Tasks:** OPH-082 (server), OPH-083 (app)
- **Builds on:** [ADR-0007](0007-google-inbound-sync-and-conflict-policy.md) (the feed this reuses)

## Context

Epic 08 shipped two-way Google sync and the product lead connected his real
account, then said: *my calendar's events didn't show up*. Correct — and
deliberate. `lib/inbound.js` answers `ignore` for any event that is not ours:
*"A foreign event in the user's calendar is none of our business (v1)."*

That line was never questioned because BLUEPRINT §7.2 only ever describes task
mirroring — external events appear nowhere in the spec, not even in the v2
parking lot. But AllisWell has a **Calendar tab** and a Home view that §12 calls
"the single chronological view where everything shows". A calendar that doesn't
show your meetings is half a product: "what does my day look like" cannot be
answered from tasks alone. The spec had a hole, not the code.

The pointed part: **we already fetch this data and throw it away.** The OPH-075
worker pulls the account's whole event feed with a `syncToken` on every pass;
foreign events flow through `applyProviderEvent` and are dropped. The webhook →
dirty → incremental pipeline is already built and proven against real Google.

## Decisions

1. **Store them in the replica, as a read-only sync entity** (`external_event`)
   — the product lead's call, taken over "fetch from Google when the month view
   opens". Reasons: the app is local-first by construction (AGENTS.md §4:
   screens never call REST, they watch the replica), so a fetch-on-view calendar
   would be the one screen that breaks offline and the one screen with a
   spinner; it also re-fetches on every pan, burning Google quota for data the
   sync already carried. Cost, accepted: the user's calendar contents live in
   their own self-hosted MySQL — which already holds the OAuth tokens that can
   read that calendar, so this widens the blast radius of a database dump but
   does not create a new class of secret.

2. **Read-only, enforced at the protocol — for free.** `sync/push` dispatches
   through an `ENTITIES` registry and answers `SYNC_UNSUPPORTED_ENTITY` for
   anything absent from it, so simply not registering `external_event` IS the
   enforcement; no new code, no new error code. (A dedicated `SYNC_READONLY_*`
   code was considered and dropped: it would add a branch to buy a nuance no
   client can act on differently.) Pull emits snapshots and tombstones like any
   other entity. Editing someone's meeting from a task app is a different
   feature with a different risk profile; v1 displays, it does not touch.

3. **Two feeds, two sync tokens.** `timeMin`/`timeMax` are incompatible with
   `syncToken` (verified in Google's events.list reference), so a sync cannot be
   windowed by time — Google's model is "synchronise the whole collection".
   `singleEvents` *is* compatible, and here the two consumers want opposite
   things:
   - the **task mirror** needs `singleEvents=false`: it must SEE a recurrence
     master to answer `time_conflict` when a user turns our block into a weekly
     standup (ADR-0007 §8, tested);
   - the **calendar display** needs `singleEvents=true`: a grid shows instances,
     and expanding RRULE ourselves is the bug farm CALDAV.md §6 already refuses.

   One feed cannot be both. So the existing feed is left exactly as it is, and
   external events get their own list call with `singleEvents=true` and their own
   cursor (`external_sync_token`). Cost: one extra HTTP request per sync pass —
   not per event — on a pipeline that already exists. Both are driven by the same
   webhook/dirty/sweep trigger.

4. **The window is applied when storing, not when fetching.** Because `timeMin`
   is unavailable, the first full sync transfers the entire calendar history
   (paginated) — that is Google's design, not a choice. We keep only what a
   calendar view can plausibly show (`EXTERNAL_EVENT_WINDOW`: 31 days back,
   400 days forward, evaluated per pass) so neither MySQL nor the phone's
   replica carries a decade of history. An event that moves into the window
   arrives as an ordinary change and gets stored; one that moves out is deleted.

5. **Our own events never become external events.** Anything carrying
   `alliswell_task_id` is skipped: it is already a task, and showing both would
   duplicate every mirrored block on the very screen this feature exists for.

6. **Deriving is pure** (`lib/external-events.js`), like `desiredEventForTask`
   and `reconcileProviderEvent` before it: Google event → row or "skip, and
   why". The worker only executes. This is now the third pure decision function
   in the calendar stack and the pattern should hold for the fourth.

## Consequences

- The Calendar tab and Home can finally answer "what does my day look like",
  offline, with meetings and tasks side by side.
- Deleting the Google account (disconnect) must drop its external events —
  they are a cache of someone else's system, not our records. The FK to
  `calendar_accounts` cascades.
- The first sync after this ships re-reads the whole calendar once
  (`external_sync_token` starts null). That is intended and self-limiting.
- Not in v1: editing external events, declined/all-day nuances beyond a flag,
  free/busy transparency rules, and multiple calendars per account (we sync the
  chosen `default_calendar_id` only — the same calendar we mirror into).
