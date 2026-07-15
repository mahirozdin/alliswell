# ADR-0007 — Google inbound sync: push channels, echo suppression and the two-way conflict policy

- **Status:** accepted (2026-07-15)
- **Tasks:** OPH-074…076 (Epic 08, BLUEPRINT §7.2 steps 6-10)
- **Builds on:** [ADR-0006](0006-google-oauth-token-crypto-and-mirror-queue.md) (outbound half)

## Context

OPH-070…073 made task changes flow **out** to Google. The return path is where
a calendar integration earns or loses its trust: it decides what happens when
the user drags our event, deletes it, turns it into a weekly standup — or does
any of that at the same moment the task changes on a phone that was offline.

Google's contract shapes the mechanics: notifications carry no body and no
change data (only headers), channels expire and are never auto-renewed, and
sync tokens can be invalidated at any time. Everything below follows from
"the notification tells you *that* something changed, never *what*".

## Decisions

1. **The channel token is stored as a keyed digest, never in plaintext.**
   Google echoes our `token` back in `X-Goog-Channel-Token`; it is the only
   thing separating a real notification from anyone who guesses a channel id.
   We generate it, hand it to Google once, and persist only
   HMAC-SHA256(`channel:` + token) in `calendar_accounts.webhook_channel_token_hash`
   — a renewal mints a fresh token, so the plaintext is never needed again.
   This is the `refresh_tokens` posture (Epic 03) applied to a second secret;
   the comparison is constant-time. A database dump cannot forge a push.

2. **Webhook responses are chosen to control Google's retries, not to hide.**
   Unknown/retired channel → `200` (nobody can act on it, and a retry will not
   make the channel exist — we cannot even call `channels.stop` without the
   account it belonged to, so it dies at expiry). Bad token → `401`
   `GOOGLE_WEBHOOK_INVALID_TOKEN`, which Google treats as a message failure
   rather than retrying. `X-Goog-Resource-State: sync` is the channel-opened
   handshake and is acknowledged without marking anything dirty. The route
   accepts any content type with an empty body — Fastify's JSON parser would
   otherwise 400 the bodyless POST Google actually sends.

3. **Dirty flag + compare-and-clear, not "sync inline in the webhook".** The
   receiver must answer fast and the notification carries nothing worth
   reading, so it stamps `sync_dirty_at` and enqueues. The worker clears that
   marker only if it is still the one it started with — a notification that
   lands mid-sync keeps its announcement and earns its own pass.

4. **Echo suppression is etag-based.** Every outbound write stores the etag
   Google answered with. An event arriving on the sync feed with that same
   etag is our own change coming back, and is ignored. This is what stops
   mirror ⇄ sync from looping, and it is why the mirror job now records
   `etag`/`last_provider_updated_at` on insert *and* patch. Timestamps alone
   could not do this job: our write and the user's are milliseconds apart.

5. **A calendar block means scheduling.** When a foreign edit moves our event,
   we write `scheduled_start_at`/`scheduled_end_at` — never `due_at`. Dragging
   a block says "I'll do it then", not "the deadline moved". §7.1 derives from
   `scheduled_*` first, so the event then stays exactly where the user dropped
   it instead of snapping back. Corollary: a *cosmetic* foreign edit (colour,
   description) must be compared against the **derived** window, not against
   the columns — otherwise recolouring a due-derived event would silently pin
   the task to a schedule it never had. Only time fields are applied; a
   renamed event is left to the next mirror pass (§7.1 owns the title).

6. **Deleting our event stops the mirror; it never deletes the task and never
   resurrects the event.** The user deleted a calendar entry, not a task —
   both "recreate it" (a fight they cannot win) and "delete the task" (data
   loss) are wrong. So: `calendar_mirror_enabled = false`, and the link row
   survives as a `provider_deleted_local_exists` tombstone recording why. The
   mirror job skips those rows; re-enabling the mirror recreates through the
   normal 404 path. The flag must be written **before** the task write, which
   announces itself to the mirror queue.

7. **`conflict_status` records the last reconcile, and `none` means
   converged.** Both sides changed since the last pass → §6.5 last-write-wins
   on the wall clock, the loser's change is dropped, and the link is flagged
   `local_changed_provider_changed`. A subsequent clean outbound write resets
   it to `none`, which is honest: once both sides agree again, there is no
   conflict left to report. The full matrix lives in `src/lib/inbound.js` as a
   pure function, so it is testable without Google or a database — the same
   shape as `desiredEventForTask` on the outbound side.

8. **Times we cannot represent are flagged, not guessed at.** Turning our
   block into a recurring series (many instants, one task), or an event with
   unusable boundaries, answers `time_conflict`: the task is left alone and
   the calendar is left alone. This is also what keeps the worker's error
   handling honest — anything that *throws* is infrastructure, which is what
   BullMQ's retries are for. All-day events are the exception we do map:
   `start.date` → midnight in the task's timezone, honouring Google's
   exclusive `end.date`.

9. **No public webhook address → poll.** `GOOGLE_WEBHOOK_URL` is optional
   because Google demands public HTTPS with a trusted certificate, which a
   self-hoster on localhost or behind NAT cannot offer. Without it we open no
   channel and the sweep (`CALENDAR_SYNC_SWEEP_SEC`, default 5 min) syncs
   those accounts instead — the poll *is* their notification. The same sweep
   renews channels a day before they lapse and retries dirty accounts, and it
   is safe on every API instance at once because enqueues dedupe per account.

10. **Channel renewal creates before it stops.** A new channel goes live
    before the old one is retired, so no change slips through the gap; the
    overlap costs a duplicate notification, which an idempotent sync absorbs.
    Renewal keys off the `expiration` Google *answered* with, never off the
    ttl we requested.

11. **One job runner, and a per-deployment BullMQ keyspace.** Both directions
    now share `src/queue/runner.js` (BullMQ with Redis, inline chain without,
    dedupe by job key in either) rather than duplicating the mechanics per
    queue. Building the second queue exposed a real defect in the first:
    every deployment used BullMQ's default keyspace, so two AllisWell
    instances on one Redis would consume each other's jobs — and because each
    has its own MySQL, the thief finds no task, returns quietly, and the job
    is *lost* rather than misrouted. The keyspace is now namespaced by
    `REDIS_KEY_PREFIX` (default `alliswell`). ADR-0006's known limit — two
    instances of the *same* deployment racing on one task — still stands and
    is still absorbed by converge-on-current-state.

## Consequences

- Inbound sync works for every self-hoster, not only publicly-reachable ones —
  at the cost of one cheap incremental call per account per sweep for the
  polling half.
- An account whose sync genuinely breaks gets stuck **loudly** (`last_error`
  on the status endpoint) rather than silently dropping changes. Recovering is
  a reconnect.
- Provider-driven task writes are ordinary writes: a sync revision, a reminder
  reconcile, and every replica hears about them within a socket round-trip
  (§6.2, OPH-057). Attribution is the user who connected the account.
- A 410 costs a full resync but no local wipe: `calendar_event_links` is keyed
  by event id, so every event reconciles itself on the way through.
- Not covered in v1: importing foreign calendar events as tasks, honouring a
  renamed event, per-instance recurring mapping, and surfacing
  `conflict_status` in the UI (the column is populated and waiting).
