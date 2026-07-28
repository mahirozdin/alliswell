# ADR-0016 — In-app URL routing (`alliswell://`) and how widgets act on data

- **Status:** Proposed
- **Date:** 2026-07-28
- **Related task:** OPH-189 (routing), OPH-188 (widget actions) — feedback round 10 #4D/#4C
- **Related:** [ADR-0003](0003-product-name-and-blueprint-deviations.md) (the scheme was
  minted there, for calendar mapping), [ADR-0010](0010-home-screen-widgets-architecture.md)
  (widget architecture), [ADR-0015](0015-alarm-delivery-and-reminder-profiles.md) (the App
  Group action queue this reuses)

## Context

`alliswell://` has existed since ADR-0003, but only as a **marker**: the string we write
into an Apple Calendar event's URL field so the backend can map an event back to a task.
Nothing in the app ever *consumed* it.

Meanwhile three surfaces started producing URLs that only make sense if something consumes
them:

- the home-screen widgets tap through with `.widgetURL(alliswell://open)` (iOS) and
  `HomeWidgetLaunchIntent(alliswell://open)` (Android) — shipped in OPH-131/133;
- notes embed attachments as `alliswell://file/{id}` (OPH-156);
- calendar events carry `alliswell://task/{id}` (ADR-0003), which a user can tap in
  Apple Calendar.

Feedback round 10 hit the consequence head-on. Tapping the widget shows
**`No route for alliswell://open/`**, because the raw URL reaches go_router's location
matcher; and the error screen's own "Home" button navigates to **`/`**, which is not a
route either (the sections are `/home`, `/inbox`, `/projects`, `/notes`, `/files`), so the
recovery path produces a second error. Underneath both: the scheme is **not registered
with either OS** — `CFBundleURLTypes` is absent from `ios/Runner/Info.plist` and there is
no deep-link `intent-filter` in `AndroidManifest.xml`.

Separately, OPH-188 wants widget buttons that **complete a task without opening the app**.
That is a *write* triggered from outside the app, and it must not be confused with
navigation.

The constraint that shapes everything below: **a URL is untrusted input.** It can arrive
from a calendar event synced from someone else's invite, from a note another device wrote,
from a link in an email. It must never be able to change data.

## Decision

**1. `alliswell://` becomes a real, closed navigation contract — and only navigation.**

| URL | Resolves to | Producer |
| --- | --- | --- |
| `alliswell://open` | `/home` | widgets (tap anywhere) |
| `alliswell://task/{ulid}` | `/tasks/{ulid}` | widget rows, calendar events (ADR-0003), notifications |
| `alliswell://file/{ulid}` | `/files` (with that file selected) | note embeds (OPH-156) |
| anything else | **nothing** — ignored, logged, app opens at its normal start | — |

Resolution lives in one **pure function**, `awRouteForUri(Uri) → String?`
(`apps/app/lib/src/core/deep_link.dart`), unit-tested as a table. IDs are validated as
ULIDs before they become a route; a malformed or unknown URL resolves to `null` and the app
opens normally rather than showing an error. Unknown URLs are **not** an error state — they
are a no-op, because the sender may be a newer version of the app.

**2. The auth redirect wins, and the destination survives it.** A deep link that arrives
while signed out goes to `/login`, and the pending destination is replayed after sign-in.
Deep links never bypass `computeAuthRedirect`.

**3. `/` is a real route** that redirects to `/home` when signed in and `/login` otherwise,
and `GoRouter.errorBuilder` is ours: an `AwErrorState` (DESIGN §4) whose action goes to
`AppSection.home.path`. **No user-facing recovery button may point at a path that is not a
route** — the round-10 bug was the router's own default doing exactly that.

**4. Writes never travel over URLs. They travel over App Intents into an App Group queue.**

`alliswell://complete?id=…` is **explicitly not part of the table above** and must never
be added. A widget button that completes a task uses the mechanism OPH-182 already built
for AlarmKit: a signed `AppIntent` compiled into both the app and the extension target,
which appends to the App Group queue (`AWAlarmActionQueue`, capped) and is drained by Dart
on handler registration and on every foreground. The Android equivalent is
`HomeWidgetBackgroundIntent` → the Dart `widgetCallback` entry point.

Both paths converge on **`TaskStore`** — the same optimistic-row + outbox transaction the
UI uses. There is no second write path to the database, so offline behaviour, conflict
policy and sync are inherited rather than reimplemented.

## Alternatives considered

- **Let the widget write through a URL (`alliswell://complete?id=…`) and parse it in the
  router.** Shortest path, and it is what a lot of `home_widget` samples do. Rejected: it
  makes every producer of a URL — including a calendar event synced from an external
  account — able to mutate the user's data by being tapped. The blast radius of a URL
  should be "we navigated somewhere unexpected", never "a task was completed".
- **Universal Links / App Links instead of a custom scheme.** Verified HTTPS links are the
  better long-term surface for *shared* links (they survive when the app is not installed).
  Rejected for this round: they require a hosted `apple-app-site-association` +
  `assetlinks.json` per deployment, and AllisWell is **self-hosted** — every instance would
  need its own domain association, which is exactly the kind of setup burden ADR-0001 says
  we do not impose. Revisit if we ever ship shareable public links.
- **Handle the raw URL inside `redirect` without a resolver function.** Rejected: routing
  policy that cannot be unit-tested is how this bug survived a release. The existing
  `computeAuthRedirect` is a pure, tested function for exactly this reason; the URL resolver
  follows the same pattern.
- **Keep go_router's default error screen and just add a `/` route.** Fixes the second
  error but not the first, and leaves an untranslated, unthemed screen in a product whose
  CI enforces no-hardcoded-strings.

## Consequences

**Easier.** Every surface that wants to point at something inside the app now has one
answer, and a new destination is one row in a table plus one test. Notifications, widgets,
calendar events and note embeds stop each inventing their own navigation. The widget row
can finally deep-link to its own task (blocked today on Android because the row record
drops the task id — OPH-188 fixes that first).

**Harder / new obligations.**

- The scheme must be registered per platform (iOS `Info.plist`, Android manifest, macOS
  Runner). A missing registration fails **silently** — the OS simply does not launch us —
  so the device pass must include "tap the widget" on both platforms.
- Two entry points into the app now exist (route + intent queue). Both must survive a cold
  start; the queue is capped and drained idempotently, and a queue that grows without being
  drained is a bug worth logging.
- `alliswell://complete` becoming tempting is a real risk. It is written here as forbidden
  so a future task has to argue with this ADR rather than quietly add it.

**Follow-ups.** Universal/App Links for shareable links (v2). A `alliswell://note/{id}`
row when notes gain external producers. Deciding whether an unknown-but-well-formed URL
should surface a one-line "this link needs a newer version" hint instead of a silent no-op.
