---
paths:
  - "apps/api/src/lib/push/**"
  - "apps/api/src/plugins/push*.js"
  - "apps/api/src/db/reminder-push.js"
  - "apps/app/lib/src/notifications/**"
  - "apps/app/web/aw_push_sw.js"
---
# Push payload privacy and notification platform behaviour — critical path

What crosses a push provider leaves our control for good; a platform that cannot ring an alarm
fails silently on a phone nobody is watching.

- **K1 extra:** `npm run check:push-payload` and `npm run check:notify-matrix` run by
  themselves when their inputs change.
  - Payload changed on purpose → `node scripts/push/payload.mjs --write`, and say why in the
    commit.
  - Gateway, token path or channel changed → update
    `apps/app/lib/src/notifications/platform_matrix.dart` and run
    `npm run check:notify-matrix -- --write`, so docs/NOTIFICATIONS.md §3 says what the build
    does.
- **Invariants:** payloads carry IDs only, never task content — not even prose inside a
  declared key (BLUEPRINT §8.3, ADR-0038). The visible fallback is the same catalogue sentence
  for everyone; no task title.
- **Traps (docs/LESSONS.md `push`, `notifications-alarm`):**
  - iOS drops an FCM message without a `notification` block; without an APNs key in Firebase a
    token is issued and nothing is ever delivered — no test sees it.
  - There is no "silent" web push: `userVisibleOnly` makes Chrome show a generic card, so
    silence means unsubscribing.
  - An FCM token is a subscription: listen for refresh; on sign-out delete the server record
    first, then the token.
- **Detail:** [NOTIFICATIONS.md](../../docs/NOTIFICATIONS.md), ADR-0015, ADR-0037, ADR-0038,
  ADR-0039.
