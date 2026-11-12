# WIDGETS — Home-screen / desktop widgets (binding research & design plan)

> Plan for **Epic 12 (OPH-130…136)**, built out in **Epic 32 (OPH-333…OPH-341)**.
> This is the researched, citation-backed
> source of truth for AllisWell's home-screen widgets, the way
> [NOTIFICATIONS.md](NOTIFICATIONS.md) is for reminders and [CALDAV.md](CALDAV.md)
> is for the iCloud connector. Architecture decision: [ADR-0010](adr/0010-home-screen-widgets-architecture.md).
> Visual spec: [DESIGN.md §8](DESIGN.md). Product spec: [BLUEPRINT.md §12.8, §15.6](BLUEPRINT.md).
>
> Researched 2026-07-17 (feedback round 5) against Apple WidgetKit docs, Android
> App Widgets / Jetpack Glance docs, the `home_widget` package, and the stock/
> competitor widgets we are targeting. Platform baseline at time of research:
> iOS/iPadOS 26, macOS 26 (Tahoe); feature floors iOS 16 (accessory), **iOS 17 /
> macOS 14 (interactivity)**, iOS 18 (Control Center). `home_widget` v0.9.3.
>
> **Revised against the code 2026-09-23 (OPH-339).** §0 is what is built. Where the
> research proposed one path and a different one shipped (Glance vs RemoteViews, a
> quick-add intent vs a deep link), the section says what shipped and why.

## 0. Implementation status (2026-09-23)

| Piece | Status |
| --- | --- |
| Dart snapshot core (`groupTasksForWidget`, `WidgetSnapshot`, `WidgetBridge`) | ✅ **done + unit-tested** (OPH-130) |
| Android widget — rendering + tap-to-open | ✅ **built** (OPH-133): an `AppWidgetProvider` (`TasksWidgetProvider`, via `home_widget`'s `HomeWidgetProvider`) drawing **RemoteViews** — a header over a scrollable collection (`TasksWidgetService`). Not Glance: `androidx.glance` is only in the build because `home_widget` depends on it |
| iOS widget — SwiftUI + timeline | ✅ **shipping.** The Xcode target exists (`AllisWellWidgetExtension` in `Runner.xcodeproj`) and the `.appex` is embedded by the Runner build; verified rendering on an iPhone 17 Pro Max Home Screen 2026-08-10 (OPH-131, OPH-253) |
| Header clock (date · clock · count) | ✅ **done + measured** (OPH-253). Android `TextClock`, free. iOS bakes minute entries against a byte budget — ~115 min / ≈13 reloads a day on a full list, and the clock **hides rather than lie** when a reload is deferred. Numbers and the traps in [DESIGN §31](DESIGN.md) |
| In-widget complete (App Intents) | ✅ **iOS ships it (round 15, OPH-233):** a widget-process `AWWidgetCompleteIntent` stamps the shared snapshot + queues the completion — see §4's warning about LiveActivityIntent. ✅ **Android since OPH-341** — OPH-188 wired it (a row's circle is a broadcast, `ACTION_ROW` → `complete`, that runs the Dart callback without launching the app), but the receiver that broadcast is addressed to was never declared, so until OPH-341 the tap reached nothing (§4) |
| Quick-add "+" | ✅ **both platforms (OPH-333):** `alliswell://add` opens the app ON the Home create sheet — a deep link, not an intent (a widget cannot take a title). iOS: closes the date header on large/extraLarge, a narrow trailing column on medium; Android: closes the header. The router turns the link into a one-shot request Home consumes — see `core/deep_link.dart` |
| macOS widget | 🟡 **code complete, one account step away (OPH-335):** the SwiftUI source is shared with iOS (macOS 14+); the app ↔ widget bridge is live in the app (`AWMacWidgetBridge` — `home_widget` has no macOS side, so the app answers `alliswell/widget` itself and drains the widget's taps); the target is added by `macos/scripts/add_widget_extension.rb`, verified on a copy, and waits for the account holder to sign the extension's own bundle id — `macos/AllisWellWidgetMac/SETUP.md` |
| Per-widget list | ✅ **both platforms, built (OPH-336):** each placed widget shows the whole list (the default — unconfigured widgets are unchanged) or one project. The app writes every list into the snapshot (`lists` + `views`, §3.1) and the filter is Dart's (`filterTasksForWidgetList`); native code only picks an id. iOS 17+/macOS 14+: `AppIntentConfiguration` (`AWWidgetConfigIntent`, a searchable project list); iOS 16 keeps the unconfigurable widget under the same kind. Android: `TasksWidgetConfigureActivity`, `configuration_optional` on 12+ (long-press → reconfigure) |
| Lock screen (iOS 16+) | ✅ **built (OPH-336):** `accessoryRectangular` — the next task (`next` in the snapshot: overdue first, dateless last) with its bucket and time in words; `accessoryCircular` — today's open count, a tick at zero. They follow the widget's list setting. iOS only — the families do not exist on macOS |
| Density, private widget | ✅ **built (OPH-337):** Settings › General › Widget. **Compact** tightens the gaps and the type (iOS: 4 → 1 pt between rows, `.footnote` → `.caption`, one more row on large/extraLarge; Android: row padding 2 → 0 dp, 14 → 13 sp) — the circle you tap keeps its size (DESIGN §8 W4). **Private widget** is applied in the snapshot, not in native code: no task title is written to the App Group / SharedPreferences at all — rows, the lock screen's `next` and every project view carry "Private task" instead (§9) |
| Calendar events (snapshot v5) | ✅ **built, both platforms (+ macOS by the shared Swift):** the whole list carries the user's own calendar events beside the tasks, under Home's rules (§3.1 v5). An event row has no circle — a calendar glyph instead — and its tap opens Home with the event's day selected (`alliswell://day/<yyyy-MM-dd>`). Android: `ACTION_ROW` → `openDay`, never `complete`; iOS: `AWEventRowView`, a `Link`, no `AWWidgetCompleteIntent`. Device pass on the owner's list (DEVICE-CHECKS) |
| Midnight rollover (Android) | ✅ **OPH-334:** the background turn ends by republishing the snapshot from the replica (`publishWidgetFromReplica`), and `WidgetMidnightWorker` asks for that turn at the next local midnight — the six-hourly OPH-321 worker alone could leave yesterday's buckets up until morning. Not exact under Doze, by design. Like every Android background turn it is a broadcast to `home_widget`'s receiver, which only exists since OPH-341 |
| Day views (snapshot v6) | ✅ **built (OPH-437, OPH-438, OPH-451; ADR-0010 revision 2026-11-12):** the snapshot carries today and the next two days as full views, and each iOS timeline entry draws its own day — after midnight the list, the counter and the lock screen's `next` are the new day's without the app running. Past the last day the widget shows a stale line instead of an old list (§3.1 v6). The app also writes the snapshot on its way to the background. With the app swiped away the iOS widget fetches its own days (next row) |
| Self-fetch (iOS, swiped-away app) | ✅ **built (Epic 37, OPH-458…464; §3.2, ADR-0070/0071):** the WidgetKit extension fetches `GET /widget/snapshot` with a read-only `aww_` token from the shared Keychain group, stores the answer beside Dart's snapshot and keeps Dart's while it is newer or a local change is pending. A change made elsewhere shows within one WidgetKit reload (typically 15–60 min, no minute guarantee). Android and macOS unchanged; WidgetKit push and macOS self-fetch are candidates (TASKS backlog) |
| Device visual/QA pass (all sizes, light+dark, sync) | 🟡 **iOS `systemLarge` done** — light + dark, English + Turkish, and a minute-boundary pixel diff proving only the clock's digits move (`screenshots/ios/12-widget.png`, `13-widget-dark.png`; recipe in [SCREENSHOTS §6](SCREENSHOTS.md)). It found and fixed a clipped header. Android, the other families, and every Epic 32 surface are on the owner's device list (STATE, "Kullanıcıdan bekleyen") |

The Dart core is the single source of truth both native widgets render; it's the
only fully unit-testable piece. The native layers are verified by build (`flutter
build ios` / `apk`, `swiftc -typecheck` for the macOS target) and by **structural
tests that read the native files** — `widget_clock_native_test`, `widget_lists_test`,
`widget_private_test`, `android_background_receiver_test` — so deleting a rule from
Swift, Kotlin or the manifest fails a test. The on-device *visual* pass is tracked
like the notification/EventKit device passes.

## 1. What we are building

A single glanceable surface that mirrors **Home**: the user's tasks bucketed
chronologically, an Apple-Calendar-style date header at the larger sizes,
Apple-Reminders-style **tap-to-complete** that works without opening the app, and a
**quick-add "+"** that opens the app on the create sheet — a widget cannot take
typed text (OPH-333). It must **stay in sync** with task data at all times.

The buckets are exactly Home's, reused from the tested `groupTasksForHome`
philosophy (a sibling pure function `groupTasksForWidget`): **Overdue → No date →
Today → This week → This month**, scrollable inside the widget. ("This month"
replaces Home's "Next 30 days" tail — a widget is a glanceable agenda and the user
asked for a monthly horizon. As built, the horizon is a rolling 30 days like Home's
(`kWidgetHorizonDays`): This month is +7…+30, and anything later is dropped, so a
far-future or recurring item cannot flood it.) Since OPH-372 a task is filed the way Home
files it: **today = due today, or its "when" day has come** (and it is not overdue). A task
with a "when" and no deadline sits on its "when" day, not under No date. The rule is
`taskPlanDay` (ADR-0053).

## 2. Platform support & the size/family mapping (READ FIRST)

Widgets exist only where the OS has that surface: **iOS, iPadOS, Android, macOS**.
**Web, Windows and Linux are out of scope** (no home-screen-widget API in our
reach — Windows' Widgets Board is a separate niche surface, deferred). The widget
code hides itself on unsupported platforms, exactly as the Apple calendar card
does off-Apple.

**The user asked for three sizes: "4×2" (~⅓ screen), "4×4" (~⅔ screen), "4×6 /
full screen." Here is what the platforms actually allow:**

| User tier | Apple `WidgetFamily` | iPhone | iPad | macOS | Android (cells / dp) |
| --- | --- | --- | --- | --- | --- |
| **4×2 (~⅓)** | `.systemMedium` (4×2) | ✅ | ✅ | ✅ | 4×2 · `targetCell 4×2` / ~250×110 dp |
| **4×4 (~⅔)** | `.systemLarge` (4×4) | ✅ **(iPhone max)** | ✅ | ✅ | 4×4 · ~250×250 dp |
| **4×6 / full** | `.systemExtraLarge` (~8×4 landscape) | ❌ **does not exist on iPhone** | ✅ | ✅ | ✅ true 4×6 · ~250×410 dp |

> **Hard constraint — the user's "4×6 / full-screen widget" cannot exist on
> iPhone.** WidgetKit's largest iPhone home-screen size is `systemLarge` (4×4).
> The only family above it, `systemExtraLarge`, is a **wide ~8×4 landscape block
> that appears on iPad and macOS only** — it is compiled in and silently filtered
> out on iPhone. So: on **iPhone** the "largest" widget is `systemLarge`; the
> "full" tier is delivered as **`systemExtraLarge` on iPad/macOS** and as a **true
> resizable 4×6 on Android**. This is a platform limit, not a scope cut — we
> deliver the wish as far as each platform physically allows.

Apple sizes are **fixed** (three per surface); Android widgets are **user-
resizable**, so the three Android sizes are *defaults* — built as ONE layout, a
header over a scrollable RemoteViews collection that fills whatever size the widget
is resized to (no per-size `Map<SizeF, RemoteViews>`), not three pixel-perfect ones. Declare Android 12+ `targetCellWidth/
Height` (cells) **and** legacy `minWidth/minHeight` dp (`70·n − 30` rule) with
`resizeMode="horizontal|vertical"` + sensible `minResize*`/`maxResize*`.

**Lock-screen / StandBy** accessory families (`accessoryCircular/Rectangular/
Inline`, iOS 16+) are a separate, tiny surface, not one of the three main sizes.
OPH-336 ships two: `accessoryRectangular` (the next task) and `accessoryCircular`
(today's open count). They are iOS-only — the SDK marks them unavailable on macOS.

## 3. Data bridge — app → widget

The widget is a **separate process with its own sandbox** and **cannot open the
drift/SQLite replica**. The sanctioned bridge is a shared container:

- **iOS/macOS:** an **App Group** (`group.com.alliswell.alliswell`) shared
  `UserDefaults(suiteName:)` (small snapshots) and/or container file (blobs).
- **Android:** **SharedPreferences** the widget process reads.

`home_widget` wraps both on iOS and Android; it has **no macOS side**, so on a Mac
the app answers the same calls on its own channel (`MacWidgetHost` ↔
`AWMacWidgetBridge`, OPH-335). As built (`widget_host.dart`, `widget_bridge.dart`):

```dart
// main(): the entry point for every background turn and widget tap
HomeWidget.registerInteractivityCallback(widgetCallback);

// WidgetBridge.publish — on every change to open tasks, projects, the date
// format and the widget settings (widgetSyncProvider), and at the end of every
// background turn (publishWidgetFromReplica):
await host.configure();          // HomeWidgetHost: setAppGroupId(group.com.alliswell.alliswell)
await host.save('aw_widget_snapshot', jsonEncode(snapshot.toJson()));
await host.requestUpdate();      // updateWidget(iOSName: 'AllisWellWidget', androidName: 'TasksWidgetProvider')
```

The WidgetKit provider and the Android `RemoteViews` provider read the same key back
and render it. **The widget never computes buckets or touches the DB** — the app
owns that.

### 3.1 The snapshot contract

Keep it **small** (single-digit KB — App-Group `UserDefaults` is memory-mapped and
the widget extension has a ~30 MB budget). Serialize only what renders, with
**already-localized** strings (Epic 11):

The shape as built (`v: 6`, `WidgetSnapshot.toJson()` in `widget_snapshot.dart`;
the Swift `AWSnapshot` and the Kotlin readers mirror it). The revisions below say
when each field arrived and why:

```jsonc
{
  "v": 6,                                   // schema version
  "generatedAt": "2026-07-17T09:00:00Z",
  "locale": "tr",
  "date": { "weekday": "Cuma", "day": "17", "month": "Temmuz" },
  "strings": { "allCaughtUp": "…", "addTask": "…", "openToday": "5 açık",
               "upNext": "…", "chooseList": "…" },   // every native word, pre-localized
  "clockFormat": "HH:mm",                   // v3 — the header clock's pattern
  "density": "compact",                     // v4 — absent = normal
  "openToday": 5,                           // v2 — absent/0 = hide the badge
  "next": { "id": "01H…", "title": "…", "bucket": "overdue", "label": "Gecikmiş", "time": "10 Tem" },
  "buckets": [
    { "key": "overdue", "label": "Gecikmiş", "count": 14,
      "items": [ { "id": "01H…", "title": "Teklifi bitir", "done": false,
                   "priority": "high", "time": "11:30", "projectColor": "#2563EB" },
                 { "id": "evt…", "title": "Standup", "done": false, "priority": "none",
                   "time": "09:00–09:15", "kind": "event", "day": "2026-07-17" } ], // v5
      "more": 2 }                           // "+N" — entries past the rows carried (12 max)
    // … noDate, today, thisWeek, thisMonth; empty buckets are omitted …
  ],
  "lists": [ … ],                           // v4 — what a widget can be set to
  "views": { … },                           // v4 — one per project in `lists`
  "days": [ … ]                             // v6 — today + 2 days, each a full view
}
```

The first version (OPH-130) carried a top-level `counts` map and a top-level
`more`; neither shipped in that form — each bucket carries its own `count` and
`more`.

**Rev. 2026-07-28 (feedback round 10 #4B — OPH-187): schema `v: 2`.** One field is
added at the top level:

```jsonc
  "openToday": 5,                 // overdue + due-today, open tasks only; omitted/0 → hide
```

- **What it counts, exactly:** tasks that are **overdue** plus tasks in the **Today**
  bucket (due today, or "when" reached; OPH-372),
  in a planning status. Snoozed and muted tasks **count** (they are still open
  work). Dateless tasks do **not** (they belong to every day, so they would inflate
  every day). Completed-today rows do not count — they are done.
- **Why it is a field and not a native sum:** the native side must never carry
  product logic; the rule above is decided once, in the pure Dart snapshot builder,
  and unit-tested there (DESIGN §8 W9).
- **The native side must tolerate its absence.** During an app update a v1 snapshot
  and a v2 widget (and the reverse) coexist for a while; a missing `openToday` hides
  the badge rather than blanking the widget.
- **Row `id` is not optional decoration.** It is already in the contract above, but
  the Android factory dropped it — without it there is no per-row completion and no
  per-row deep link. Any consumer that discards `id` is a bug (OPH-188).

**Rev. 2026-09-23 (OPH-336): schema `v: 4`** (v3 was OPH-253's `clockFormat`). Three
optional fields, added **beside** the v3 ones — the whole list stays at the top level
where it always was, so an unconfigured widget and a pre-v4 widget read exactly what
they read before:

```jsonc
  "next": { "id": "01H…", "title": "Teklifi bitir", "bucket": "overdue",
            "label": "Gecikmiş", "time": "10 Tem" },     // the lock screen's row
  "lists": [ { "id": "all", "name": "Tüm görevler" },     // what a widget can be set to
             { "id": "01J…", "name": "İş", "color": "#2563EB" } ],
  "views": { "01J…": { "openToday": 2, "openTodayLabel": "2 açık",
                       "next": { … }, "buckets": [ … ] } } // one per project in `lists`
```

- **The filter is Dart's.** `filterTasksForWidgetList` (next to `groupTasksForWidget`)
  decides what a project's list holds, and every view is built by the same function as
  the whole list. Native code picks `views[id]` and draws it; no Swift or Kotlin file
  reads a task's project (a test pins that).
- **Offered lists:** `all` first, then every project a task can be filed under — not
  the archived ones (the task picker's rule) — in the Projects screen's order.
- **An empty project still has a view** (`{"buckets": []}`), so its widget says "all
  caught up". A widget falls back to the whole list only for an id `views` has never
  heard of — a project deleted or archived since it was set up.
- **`next`** is the first open task in the widget's bucket order — overdue, today,
  this week, this month — with dateless tasks last: they are every day's work, so
  nobody's "next" while something dated is open (`nextTaskForWidget`).
- **Each view carries its own `openTodayLabel`**, because `strings.openToday` spells the
  whole list's number.
- New `strings`: `upNext` (the rectangle's heading) and `chooseList` (the Android
  configure screen's title).
- **`density`** (OPH-337): `"compact"` when the user chose tighter rows, absent for
  the default. The "Private widget" setting is NOT a field — it changes what the title
  fields hold (§9).

**Rev. 2026-10-15: schema `v: 5` — calendar events.** The whole list (top-level
`buckets`) carries the user's own calendar events, as Home does. An event is an
ordinary item with two optional fields: `"kind": "event"` (absent = a task, so every
v4 row reads unchanged) and `"day": "yyyy-MM-dd"`, the day its tap opens
(`alliswell://day/<day>` → Home with that day selected; the router turns it into a
one-shot selection, like `add`, written a microtask later because go_router may re-run
`redirect` during a build and Riverpod forbids writes then). `done` is always false,
`priority` is `"none"`, no `projectColor`. Android: a widget tap after process death
(activity kept in recents) arrives in `MainActivity.onNewIntent` before Dart has a router;
the link is kept and re-pushed in `onFlutterUiDisplayed` (task and day links alike).

- **Home's rules, from Home's helper** (`groupTasksForWidget(events:)`, `daysOfEvent`):
  never Overdue, never No date; a finished event is dropped; a running one is filed
  under the first day it touches that has not passed (today); the same 30-day horizon.
  All-day events — and ones already running — sit at the start of their day.
- **`time`:** today — "All day" (localized) or the range ("14:00–15:00"; "–11:00"
  for one that began before today). Later — a short date with the start time; an
  all-day one just the short date. The user's date format, like a task's.
- **Events are the whole list's only.** Project views, `openToday` and `next` stay
  task-based (an event belongs to no project and is not open work). A bucket's
  `count` and `more` include them, because they are rows.
- **Private widget hides event titles too** — an event row carries "Private event" ("Gizli etkinlik"), a task row "Private task".
- **Shared workspaces draw no calendar**: the live app reads `externalEventsProvider`
  (empty there), and the background redraw reads `ExternalEvents` only for a
  one-workspace personal scope, never for a `mine` (organisation) scope.
- **Old readers:** a v4 widget ignores `kind` and draws the event as a task row; its
  circle would queue a completion for an id no task has, which completes nothing.

**Rev. 2026-11-12 (#50, OPH-437/451): schema `v: 6` — per-day views.** Before v6 every iOS
timeline entry drew the one snapshot, bucketed for the day it was written, so after midnight the
widget showed yesterday's Today under today's date until the app ran.

```jsonc
  "strings": { …, "stale": "Liste güncel değil · Güncellemek için aç" },
  "days": [ { "date": "2026-11-12", "header": { … }, "openToday": 3, "openTodayLabel": "3 açık",
              "next": { … }, "buckets": [ … ], "views": { … } },   // day 0 = the top level
            { "date": "2026-11-13", … }, { "date": "2026-11-14", … } ]
```

- **Each day is built by the same Dart code** (`_listData` and the project loop) as the top level,
  with that day's calendar rows. A later day keeps a finished task only if it was completed on or
  after that day's start, so a task done today is not a dimmed row tomorrow.
- **The top-level fields are day 0**, so a v5 extension keeps rendering unchanged.
- **Native code picks a day, never builds one.** `awDayView(for:in:calendar:)`
  (`ios/Shared/AWWidgetDayPick.swift`) returns the entry's local day, `.stale` for a day the
  snapshot does not hold, or `.topLevel` for a v5 snapshot. Stale: the header keeps the entry's
  date, the list becomes `strings.stale`, the counter and `next` are hidden (the circular
  lock-screen widget shows a refresh glyph).
- **A completion from the circle (OPH-451)** is written into the stored snapshot by
  `awMarkSnapshotDone` (`ios/Shared/AWSnapshotModel.swift`), everywhere the task is drawn and by
  the rules Dart wrote it with: a done row in today's views, gone from a later day's, one fewer
  in its bucket's `count` and (overdue/today) in `openToday`, whose words are re-spelled from
  `strings.openTodayPattern` ("{count} açık"); a `next` naming the task moves to the next open
  row in Dart's order. The timeline also reads through the completions still queued for the app,
  so a Dart rewrite before the app pulls the queue cannot put the row back. The circle's spoken
  label is `strings.completeTask` ("Tamamla: {title}").
- **A bucket's `count` is its open rows (OPH-451)** — Home's header rule (OPH-394): today's
  finished row is drawn at the bottom but not counted. `more` still counts every trimmed entry.
- **Size:** `kWidgetSnapshotMaxBytes` = 384 KiB, from a measured 282 425 bytes (300 tasks, 20
  projects, long Turkish titles), locked by a test. The iOS archive budget counts one day's rows.

- **N per bucket is per-size** (§5): medium shows few, large ~8–10, extraLarge
  more. Truncation is honest — show a "+N more" affordance, never silently drop
  (the "no silent caps" ethos).
- `projectColor` is user data (hex allowed here — it's a data value, not UI chrome;
  DESIGN G6 exception). The native side computes readable ink over it, mirroring
  the "Project badge" contrast helper (DESIGN §4).
- Rows' times and dates are pre-formatted by the app in the active locale and the
  user's date format (OPH-174) — no second i18n system. Native code formats exactly
  two things, both of which change while the app is not running: the header's date,
  from the timeline ENTRY's date with the snapshot's `locale` (round 15), and the
  clock's minute, with the snapshot's `clockFormat` (OPH-253). The choices stay the
  app's; only the ticking is native.

### 3.2 Widget self-fetch contract (iOS, #50)

The single agreement between the Dart side (fetch profile, widget token store), the Swift side
(the WidgetKit extension's fetch and snapshot choice) and the API (`/widget-tokens`,
`/widget/snapshot`). When this text and a task brief differ, this text wins; a lane that finds a
real gap edits this section in the same commit as its code. Decisions:
[ADR-0070](adr/0070-widget-token.md) (token), [ADR-0071](adr/0071-shared-keychain-group-after-first-unlock.md)
(Keychain), [ADR-0010](adr/0010-home-screen-widgets-architecture.md) revision of §5.

**iOS only.** Android's background turn runs Dart (§0, midnight rollover) and the macOS widget's
self-fetch is a later candidate: on those platforms nothing below is written or read, and the
mint route is never called.

#### Keychain item — Dart writes, Swift only reads

| Attribute | Value |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `"flutter_secure_storage_service"` — the plugin's default `accountName` (`flutter_secure_storage` 10.3.1, `flutter_secure_storage_darwin` 0.3.2 in `pubspec.lock`) |
| `kSecAttrAccount` | `"aw_widget_token"` — the key, passed through unchanged |
| `kSecAttrAccessGroup` | `"group.com.alliswell.alliswell"` — the plugin's `groupId`, no team prefix |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`first_unlock_this_device`) |
| `kSecAttrSynchronizable` | `false` (the plugin default) |
| `kSecValueData` | the token's UTF-8 bytes, `aww_…` |

- **Dart:** `FlutterSecureStorage(iOptions: IOSOptions(groupId: 'group.com.alliswell.alliswell',
  accessibility: KeychainAccessibility.first_unlock_this_device))`, default `accountName`, key
  `aw_widget_token`. The session (`alliswell_session`) keeps `const FlutterSecureStorage()`.
- **Swift:** `SecItemCopyMatching` with class, service, account, access group,
  `kSecReturnData: true`, `kSecMatchLimitOne`. `errSecItemNotFound` → no token;
  `errSecInteractionNotAllowed` (before the first unlock) → no fetch and nothing written. The
  extension never writes, deletes or logs the item.

#### App Group keys (`UserDefaults(suiteName: "group.com.alliswell.alliswell")`)

| Key | Type | Written by | Meaning |
| --- | --- | --- | --- |
| `aw_widget_snapshot` | String (JSON) | Dart | unchanged — §3.1 v6; chrome (`strings`, `lists`, `clockFormat`, `density`, `locale`) always comes from here |
| `aw_widget_fetch_profile` | String (JSON, below) | Dart | what a fetch needs; **absent = never fetch** |
| `aw_widget_token_state` | String `valid` · `invalid` | Swift writes `invalid` on a 401; Dart writes `valid` after a mint | `invalid` stops fetching until the app re-mints |
| `aw_widget_server_snapshot` | String (JSON envelope, below) | Swift | the last 200 answer; never written over `aw_widget_snapshot` |
| `aw_widget_fetched_at_ms` | Int, UTC ms | Swift | last 200 or 304; no new fetch within 2 minutes of it |
| `aw_widget_fetch_failures` | Int | Swift | failures in a row; 0 after a success |
| `aw_widget_backoff_until_ms` | Int, UTC ms | Swift | no fetch before it |

**Removing a key** means writing the empty string, never a null: `home_widget` 0.9.3 hands a
Dart null to iOS as `NSNull` and `NSUserDefaults` aborts the app on it (#50, PR2-01). Every
reader — Dart and Swift — treats an empty or missing value as absent.

On sign-out, an account switch, or a session the server refused, Dart deletes the device on the
server first where it still can (that revokes the token, ADR-0070), then removes every key above
except `aw_widget_snapshot`, then the Keychain item, then writes `aw_widget_snapshot` empty (no
row, no project, no event: the signed-out state) and asks for a reload — on every widget platform,
since nothing else would write over the person's rows. With the profile gone the extension never
fetches and draws that empty snapshot.
A change of scope or of "Private widget" removes `aw_widget_server_snapshot` right after the new
profile is written — in that order, so a late answer for the old profile is refused or taken back
(step 4 below).

**Fetch profile** (`v: 1`). Dart writes it in the same publish as `aw_widget_snapshot` and again
after every sync push round (so `pendingOutbox` stays current), and only once "Private widget" has
been **read** (fail-closed, the OPH-337 rule):

```jsonc
{
  "v": 1,
  "baseUrl": "https://api.alliswell.space",   // apiBaseUrlProvider as the app uses it, no trailing /; "/api/v1/…" is appended
  "scope": { "workspaceIds": ["01J…"], "mineFor": "01H…" },  // TaskScope.toJson(); mineFor absent when solo
  "private": true,                            // "Private widget" as read
  "locale": "tr",                             // the tag Dart formats rows with
  "patterns": { "time": "HH:mm", "day": "d MMM", "dayYear": "d MMM y", "relativeDays": true },
  "strings": { "bucket.overdue": "Gecikmiş", "bucket.noDate": "…", "bucket.today": "Bugün",
               "bucket.thisWeek": "…", "bucket.thisMonth": "…", "privateTitle": "Gizli görev",
               "privateEvent": "Gizli etkinlik", "allDay": "Tüm gün",
               "today": "Bugün", "tomorrow": "Yarın", "yesterday": "Dün" },
  "pendingOutbox": 0,                          // outbox entries not yet sent to the server
  "localWrittenAtMs": 1762934400000            // when aw_widget_snapshot was last written, UTC ms
}
```

`patterns` are the ICU patterns `awFormatTime` / `awFormatShort(withTime: false)` use for the
user's date format: the system default gives the region's clock and day order, `dayYear` adding
the year for another year, `relativeDays: true`; a chosen format gives its `time` and `short`
(`dayYear` = `day`), `relativeDays: false`.

**Server envelope** (`aw_widget_server_snapshot`):
`{ "fetchedAtMs": Int, "etag": String, "query": String, "body": { …the 200 body… } }`. `query` is
the exact query string sent; an envelope whose `query` differs from the one the current profile
builds is not used, not even for `If-None-Match`.

#### Mint — `POST /api/v1/widget-tokens` (Dart ↔ API)

Session JWT only. Body `{ "deviceId": "<notification_devices.id>" }`. `201`
`{ "token": "aww_…", "deviceId": "…", "expiresAt": "<ISO instant>" }` — the token is shown this
once; minting again for the device revokes the previous one. Errors: `401` (no session), `403
AUTH_APIKEY_FORBIDDEN` (an API key), `404 DEVICE_NOT_FOUND` (not this user's device, or the
caller's own session is not live and bound to it yet; register, retry at the next foreground).
The token is tied to the caller's session family — the access token's `sid` claim — which must be
live and bound to the device (`refresh_tokens.device_id`, set by a sign-in or refresh that names
the device), so a revoked session cannot mint in the minutes its access token still verifies. A
`404` without that code is an older server: no token, no retry
until the next app start. Life 90 days; Dart re-mints in the foreground when fewer than 30 remain
or `aw_widget_token_state` is `invalid`, and after every sign-in (not a restore): a sign-in is a
new family, and the old one may have expired without a sign-out to clear its token.

#### Fetch — `GET /api/v1/widget/snapshot` (Swift ↔ API)

```
GET {baseUrl}/api/v1/widget/snapshot?tz=Europe%2FIstanbul&workspaceIds=01J…,01J…&mine=1&private=1&days=3
Authorization: Bearer aww_…
If-None-Match: "<etag>"            (only with a usable envelope)
```

| Parameter | Rule |
| --- | --- |
| `tz` | required; IANA id (`TimeZone.current.identifier`); day boundaries and every local date use it |
| `workspaceIds` | required; 1–20 comma-separated ULIDs = `scope.workspaceIds`; each must be the token user's membership |
| `mine` | `0` (default) · `1` = `scope.mineFor` present; always the token's own user, never an id |
| `private` | `1` (default, fail-closed) · `0`; `1` sends no `title` key anywhere |
| `days` | `1`–`3`, default `3` |

No `locale` and no `list`: the server sends no words, and every project view is in the body.

**200** — `Cache-Control: no-store`, `ETag: "<hex>"`:

```jsonc
{
  "v": 1,
  "generatedAt": "2026-11-12T08:00:00.000Z",   // server clock; informative only
  "tz": "Europe/Istanbul",
  "days": [
    { "date": "2026-11-12",                     // local day in tz; days[0] = today
      "openToday": 3,                           // always present, 0 = none
      "next": { "id": "01J…", "title": "…", "bucket": "overdue",
                "dueAt": "2026-11-11T09:00:00.000Z", "timeStyle": "day" },   // absent = nothing open
      "buckets": [
        { "key": "overdue", "count": 2, "more": 1,
          "items": [
            { "id": "01J…", "title": "…", "done": false, "priority": "high",
              "dueAt": "2026-11-11T09:00:00.000Z", "timeStyle": "day", "projectColor": "#2563EB" },
            { "id": "01K…", "title": "Standup", "done": false, "priority": "none",
              "kind": "event", "day": "2026-11-12", "dueAt": "…", "endAt": "…",
              "allDay": false, "timeStyle": "range" } ] } ],
      "views": { "<projectId>": { "openToday": 1, "next": { … }, "buckets": [ … ] } } } ]
}
```

- **Same rules as Dart's `buildWidgetSnapshot`, by the shared fixture**
  (`apps/app/test/fixtures/widget_grouping_cases.json`): bucket keys and order `overdue`,
  `noDate`, `today`, `thisWeek`, `thisMonth`, empty buckets left out; at most 12 `items`; `count`
  = open rows; `more` = open entries past the rows, absent at 0; day 0 is seen from now, a later
  day from its first minute and keeps only tasks completed on or after it; `next` and `openToday`
  are task-only; `views` hold every non-archived project of the scope (an empty one as
  `{"openToday": 0, "buckets": []}`), tasks only; events only when `workspaceIds` has one id and
  `mine=0`. Each case holds the replica's rows, a scope, `tz` and `now`; `expected.selected` is
  what the scope selects (status `open`, `scheduled`, `in_progress` or `waiting`, plus tasks
  completed today and not due before today; `mine` = assigned to the user, or created by them
  with nobody assigned), and
  `expected.days` is `buildWidgetServerDays` over it.
- **Order within a bucket:** by instant (a task's `dueAt`, an event's start; an all-day event or
  one already running sits at its day's first minute), finished tasks last, dateless tasks by
  `sortOrder`; a task and an event at the same instant: the event first; any other tie keeps the
  input order — tasks newest id first, then events by start.
- **Item fields:** `id`, `done`, `priority` (events `"none"`), `title` (absent when `private=1`;
  Swift draws `strings.privateTitle` / `privateEvent`), `projectColor` (`#RRGGBB`: a task with a
  project takes the project's, absent when that project is unknown; else the task's own, absent
  when none), `kind: "event"` + `day` (`yyyy-MM-dd`) for events,
  `dueAt` (a task's due instant, an event's start; absent for a dateless task), `endAt` and
  `allDay` (events only), `timeStyle` (absent = no label).
- **`timeStyle` → text** (Swift, profile `patterns` and `locale`, in `tz`): `time` = time(dueAt) ·
  `day` = day(dueAt), or day(`day`) for an all-day event · `allDay` = `strings.allDay` · `range` =
  time(dueAt) + "–" + time(endAt) · `start` = time(dueAt) · `end` = "–" + time(endAt) · `dayTime`
  = with `relativeDays`, the bare time on the view's date, `today`/`tomorrow`/`yesterday` +
  U+00A0 + time on a neighbouring day, else day + ", " + time; without it, day + ", " + time.
  The comma before the time is followed by U+00A0 with `relativeDays`, by a space without it.
  day() uses `dayYear` for a year other than the view's date's, and "neighbouring" is to the
  view's date too. The header (weekday, day, month) is formatted from `date`;
  a bucket's label and `next`'s label are `strings["bucket.<key>"]`; a view's open-count words
  come from the snapshot's `strings.openTodayPattern`.
- **ETag** covers the whole body except `generatedAt`, plus the query: equal ETag, equal days.
  `If-None-Match` equal → **304**, empty body, same headers.

**Errors** (body `{statusCode, code, error, message}`): `400` invalid `tz` (`WIDGET_INVALID_TZ`) or
parameters (`FST_ERR_VALIDATION`) · `401 AUTH_WIDGET_TOKEN_INVALID` for a missing, unknown,
revoked or expired token, a removed device or a dead session family (one code, no reason) · `403
AUTH_WORKSPACE_FORBIDDEN` for a workspace the user is not in · `429 RATE_LIMITED` (30 an hour per
token).

#### The extension's turn (Swift)

1. Load `aw_widget_snapshot` first; with none, keep today's behaviour and do not fetch.
2. Fetch only when all hold: a profile that decodes (with `private`; an empty one is absent); `aw_widget_token_state` is
   not `invalid`; the Keychain item reads; now ≥ `aw_widget_backoff_until_ms`; now −
   `aw_widget_fetched_at_ms` ≥ 2 minutes.
3. One request: `URLSession(configuration: .ephemeral)`, `timeoutIntervalForRequest` 6 s,
   `timeoutIntervalForResource` 8 s, `waitsForConnectivity = false`.
4. `200` → write the envelope and `aw_widget_fetched_at_ms`, failures 0, remove the backoff.
   `304` → refresh `fetchedAtMs` and the stamp, failures 0. `401` → `aw_widget_token_state =
   invalid`. Anything else (400, 403, 429, 5xx, timeout, offline) → failures + 1 and backoff until
   now + min(5 min × 2^n, 2 h), n = the failures before this one. An answer whose profile is no
   longer current (`baseUrl` or query changed while it was out, e.g. "Private widget" turned on)
   writes nothing — no envelope, no stamp, no failure. The profile is read again after the
   envelope is written too: changed by then, the write is removed and counts as nothing.
5. **Choose** (decision K-11): no usable envelope → local; `pendingOutbox > 0` → local; a widget
   completion still queued (`aw_alarm_pending_actions`, `complete`) → local; `localWrittenAtMs ≥
   fetchedAtMs` → local; else the server's days. Both clocks are the device's, which is why the
   envelope's `fetchedAtMs` and not the server's `generatedAt` is compared. Queued completions are
   overlaid as done on whichever wins (`awMarkSnapshotDone`'s rules). A self-fetch never undoes a
   local change. `aw_widget_snapshot` is read after the request, not before it. A server task
   row the app's snapshot does not hold draws a plain circle (no complete intent; the tap opens
   the app): the app has no copy to apply a queued completion to.
6. Reload `.after(min(clock horizon, now + 30 min + 0–300 s))`; the midnight entry at 00:01 + 0–300 s.

## 4. Interactivity — quick-add & quick-complete

**iOS 17+ / iPadOS 17+ / macOS 14+ (the real mechanism):** SwiftUI
`Button(intent:)` / `Toggle(isOn:intent:)` whose action is an **`AppIntent`**;
WidgetKit runs `perform()` **in the background, no app launch**, then reloads.
This is the Reminders "tap the circle to complete" behavior. Configurable widgets
use `AppIntentConfiguration` + `AppIntentTimelineProvider`; plain interactivity
works on a `StaticConfiguration` too. AllisWell ships both under one kind: the
configurable widget on iOS 17+ / macOS 14+ (OPH-336) and the static one on iOS 16,
which steps aside at runtime on 17+ (a `WidgetBundle` has no `else` after
`#available` — measured, see `AllisWellWidget.swift`).

> **The round-15 device lesson (OPH-233): the intent's TYPE decides the
> process.** The widget's circle originally reused `AWCompleteTaskIntent` — a
> **`LiveActivityIntent`**, which iOS always runs IN THE MAIN APP. Every tap
> cold-started a headless Flutter process in the background: the widget showed
> nothing, the half-born process crashed when the user then opened the app
> (never reaching Crashlytics — it dies before Dart), and the queued completion
> only applied on the NEXT clean launch. The widget now has its own plain
> `AppIntent` (`AWWidgetCompleteIntent`, widget target only): it flips `done`
> inside the stored snapshot via JSONSerialization (a Codable round-trip would
> drop fields newer app versions write — the OPH-187 stance), enqueues the real
> completion into `AWAlarmActionQueue`, and reloads the timeline. The app
> drains that queue on its existing foreground observer. `LiveActivityIntent`
> remains correct for the Live Activity's own buttons, where the app is the
> point.

**Android (as built):** a RemoteViews collection — the provider sets one
`setPendingIntentTemplate` and each row two `setOnClickFillInIntent`s (open the task /
complete it). "Complete" becomes a `HomeWidgetBackgroundIntent` broadcast to
`home_widget`'s `HomeWidgetBackgroundReceiver`, which runs the Dart callback in a
background engine without launching the app. (The research's Glance
`actionRunCallback` path was not taken.)

**The Dart side of the bridge (`lib/main.dart`, `widget_callback.dart`):**

```dart
@pragma('vm:entry-point')          // MANDATORY — survives tree-shaking & app-kill
Future<void> widgetCallback(Uri? uri) async {
  // alliswell://refresh-alarms — the six-hourly and midnight turns (OPH-321/334)
  if (uri != null && awIsAlarmRefresh(uri)) return runHeadlessRefresh();
  // alliswell://complete?id=… — the ONLY write a widget makes (TaskStore.complete)
  if (await handleWidgetAction(uri)) await HomeWidget.updateWidget(…);
}
```

Adding is not here: a widget cannot take a title, so the "+" is a deep link that
opens the create sheet (`alliswell://add`, OPH-333).

- iOS: no `HomeWidgetBackgroundWorker`. The circle's `AWWidgetCompleteIntent` runs in
  the widget process and queues into `AWAlarmActionQueue`; the app drains it (the
  round-15 note above). On a Mac the same queue is drained by `AWMacWidgetBridge`.
- Android: `HomeWidgetBackgroundIntent.getBroadcast(context, uri)` addresses the
  receiver **by class**, and `home_widget` 0.9.3's own manifest is empty — so
  `HomeWidgetBackgroundReceiver` has to be declared in OURS. It was not until
  **OPH-341**: the widget circle (OPH-188), the six-hourly refresh (OPH-321) and the
  midnight redraw (OPH-334) were broadcasts to nobody, green in every Dart suite.
  It is declared **non-exported** (every sender is the app's own process; an
  exported one would let any app complete a task by URL — ADR-0016), and
  `android_background_receiver_test` reads the manifest.
- Completing/adding goes through **`TaskStore`** — the same optimistic-write +
  outbox path the UI uses (AGENTS §4 local-first), so a widget edit **syncs to the
  server** and every device converges. This is non-negotiable: the widget must not
  have its own write path.
- **Pre-iOS-17 floor: deep link only.** The tap opens the app at
  `alliswell://task/{id}` (ADR-0003) / `alliswell://add`; gate interactive code
  `@available(iOS 17, *)`. UX lesson from Reminders: the complete hit-target is
  easy to fumble — make it **generous and deliberate**, and animate the row away
  after ~1–2 s so the tap feels acknowledged.

_(Rev. 2026-07-28, feedback round 10 #4C/#4D — OPH-188/189. Two corrections that came
out of using the shipped widget:)_

- **The mechanism already exists; do not build a second one.** Round 9's OPH-182 put
  App Intents into `ios/Shared/AWAlarmShared.swift` compiled into **both** targets and
  added an **App Group action queue** (`AWAlarmActionQueue`, capped, drained by Dart on
  handler registration and on every foreground). That queue is what makes a button work
  while the app is **cold** — pushing straight at a method channel drops exactly the
  press that matters most. Widget completion rides the same rails.
- **Writes do NOT travel as URLs.** The sketch above shows `uri?.host == 'complete'`;
  that shape is fine *inside* the background-intent bridge, where the URL is minted by
  our own signed intent, and forbidden as a **routable** URL. `alliswell://complete?id=…`
  must never appear in the app's URL table — a scheme URL can arrive from a synced
  calendar event or a note written by another device, and a tapped link must never be
  able to mutate data. Contract:
  [ADR-0016](adr/0016-in-app-url-routing-and-widget-actions.md).
- **Tapping through has to land somewhere.** Until round 10 the scheme was registered
  with neither OS (no `CFBundleURLTypes`, no deep-link `intent-filter`) and the app had
  no resolver, so the shipped tap produced `No route for alliswell://open/`. Registration
  + a pure resolver + a real `/` route + our own `errorBuilder` are prerequisites for
  interactivity, not polish (OPH-189 precedes OPH-188).

## 5. Content per size

As built (`awRowBudget` in Swift; Android's list scrolls at every size):

| Size | Date header | List | Actions |
| --- | --- | --- | --- |
| **4×2 medium** | none — the rows need the height | up to 4 rows with bucket labels + counts (3 when the widget is set to a project: its name takes a line), only as many as fit whole in the card's height (`awFitBuckets`, OPH-451; about 3 on a 6.3" iPhone); the rest go to "+N" | "+" in a narrow trailing column; per-row complete |
| **4×4 large** | full: day number · weekday · month, the clock, today's open count, "+" | ~10 rows (11 compact) with labels + counts + "+N" | "+" closes the header; per-row complete |
| **extraLarge (iPad/Mac) · tall Android** | full | ~18 rows (19 compact); Android scrolls | same |
| **Lock screen (iOS)** | — | rectangle: the next task · circle: today's open count | tap opens the task / the app |

The research's **week strip / mini month grid** and a two-column extraLarge were not
built. On **Android** the buckets recompute at local midnight without the app
(OPH-334, through OPH-341's receiver); on **iOS** the header's date rolls over from
the timeline but the buckets wait for the app to run (§6). Empty state: a calm "All
caught up" mirroring Home.

## 6. Freshness & refresh budget

**Apple's budget:** ~**40–70 timeline reloads/day**, dynamic per how often the
widget is viewed. **Exemptions that make our sync free:** the containing app is in
the **foreground**, and **the widget performs an app intent**. Android has no such
budget but `updatePeriodMillis` has a **30-minute floor** and wakes the device.

**Strategy (both platforms):**
1. **Push on write, primary (built):** `widgetSyncProvider`, watched by the app
   shell, republishes the snapshot on every change to the open tasks, the projects,
   the date format and the widget settings — one place, not per screen. While the
   app is foreground these reloads are **budget-exempt** → the widget stays in
   lock-step for free.
2. **Self-refresh, safety net (built):** the iOS timeline carries one entry per
   minute for the header clock, as many as a byte budget allows (OPH-253: up to 240,
   ~115 on a full list), then the next midnights without a clock, and reloads when
   the minute entries run out; the lock-screen families need no clock — one entry and
   a reload at 00:01. On Android, `WidgetMidnightWorker` (a one-time WorkManager job,
   re-armed nightly) and the six-hourly `AlarmRefreshWorker` run the background turn,
   which republishes from the replica (OPH-321, OPH-334 — working since OPH-341).
   **Round 15 (OPH-232):** one entry + one reload was NOT enough — after the
   first midnight the reload re-rendered the same stale snapshot still wearing
   yesterday's date. The iOS timeline now carries **now + the next 4 midnights**
   (still ~1 reload/day of budget), and the **date header renders from the
   ENTRY's date** (`awDate(for:locale:)` — OS date names via the snapshot's
   locale, not product strings, so W9 holds). Buckets stay the app's honest
   snapshot: an aging list under a correct date, never a native guess (W1).
   The Android midnight job, once the open half of this item, is OPH-334.
   **Rev. 2026-11-12 (OPH-437/438/451):** each entry now draws its own day from the v6 `days`
   (§3.1), so the midnight entries show the new day's list, not only its date; the lock-screen
   timeline carries the next midnights too. When the app goes hidden or paused,
   `widgetSyncProvider` writes the last snapshot once more and reloads the timelines — the last
   budget-free write. `home_widget`'s interactivity callback is registered on Android only.
3. Prefer `WidgetCenter.shared.reloadTimelines(ofKind:)` over `reloadAllTimelines()` —
   iOS does (`home_widget`'s `updateWidget(iOSName:)`, the complete intent). The Mac
   bridge reloads all: its extension has one kind.

## 7. Setup — extension targets & files committed to git

A widget is an **App-Extension target**; a Flutter plugin package **cannot** vend
one. So — unlike the EventKit SwiftPM plugin — **`project.pbxproj` edits and
entitlements are unavoidable and committed** (ADR-0010, deliberate deviation).

**iOS (`ios/`):** Xcode ▸ File ▸ New ▸ Target ▸ **Widget Extension**
(`AllisWellWidget`). Add **App Groups** capability (`group.com.alliswell.alliswell`)
to **both** Runner and the extension. Commit: the extension's Swift (widget view,
`TimelineProvider`/`AppIntentTimelineProvider`, the shared `AppIntent`), its
`Info.plist`, `Assets.xcassets`, **both** `.entitlements` and the **`project.pbxproj`**
diff. As built, the extension does **not** link `home_widget` (no Podfile target —
it reads the App Group's `UserDefaults` itself), and its floor is **iOS 16** (the
lock-screen families) while Runner's is 15: on iOS 15 the widget is simply not
offered. Keep the "Thin Binary" build phase last (Flutter guidance).

**macOS (`macos/`, OPH-335):** same, plus **App Sandbox** —
`com.apple.security.application-groups` is in **`DebugProfile.entitlements` AND
`Release.entitlements`**. The App-Group string is **byte-identical** everywhere:
`group.com.alliswell.alliswell` — decided in OPH-335 (the Mac team profile covers
it; no `<TeamID>.` prefix). `home_widget` has no macOS side, so the app answers
`alliswell/widget` itself (`AWMacWidgetBridge`). The target is added by
`macos/scripts/add_widget_extension.rb` (idempotent, verified on a copy) rather than
by hand; `flutter build macos` is green without it, and the one step left — signing
the extension's own bundle id — belongs to the account holder
(`macos/AllisWellWidgetMac/SETUP.md`).

**Android (`android/app/src/main/`, as built):** `kotlin/com/alliswell/alliswell/` —
`TasksWidgetProvider.kt` (the `AppWidgetProvider`), `TasksWidgetService.kt` (the row
collection), `TasksWidgetConfigureActivity.kt` + `WidgetLists.kt` (per-widget list,
OPH-336), `WidgetMidnightWorker.kt` (OPH-334); `res/xml/tasks_widget_info.xml`
(sizing, resize, `configure`, `widgetFeatures`); `res/layout/tasks_widget*.xml` and
`widget_config_row.xml`; and in `AndroidManifest.xml` the provider, its service, the
configure activity **and `home_widget`'s background receiver** (OPH-341). Verify
with a real `flutter build apk` — `flutter analyze`/`flutter test` do **not** compile
Kotlin — and read the MERGED manifest: a declaration the build does not need is one
the build will never miss.

**Verification reality (the EventKit lesson):** `flutter analyze` + `flutter test`
compile **no** Swift/Kotlin. Every native widget task is only proven by a real
`flutter build ios`/`apk`/`macos` **and** a device/simulator pass. The one fully
unit-testable piece is the Dart snapshot core (§8).

## 8. What is (and isn't) unit-testable

- **Green in `flutter test`:** `groupTasksForWidget` and its neighbours
  (`filterTasksForWidgetList`, `nextTaskForWidget`), the snapshot serializer (JSON
  shape, "+N", localized labels, lists/views, the private placeholders), the
  `WidgetBridge` and the background republish (via `FakeWidgetHost`), the
  interactivity callback (`complete` → `TaskStore`; `add` is a deep link, tested in
  `quick_add_link_test`), and the Settings card.
- **Read, not run:** structural tests open the native files and pin what they must
  keep saying — the clock's constants, list selection, density, the lock-screen
  families, the background receiver in the manifest.
- **Only by build + device:** the SwiftUI and RemoteViews drawing, the extension
  targets, App-Intent registration, timeline refresh, the gallery. Record device
  results in STATE like the notification/EventKit passes.

## 9. Privacy

The snapshot carries task **titles** and lives in the sandbox-protected App-Group
container. Offer a **"Private widget"** switch (same spirit as OPH-064 "Private
notifications"): when on, the widget renders **counts and placeholders** ("3
tasks") instead of titles — a glanceable surface others can see over your shoulder
shouldn't leak content by default for users who care. Setting is device-local.

**Built in OPH-337 — and where it is applied is the whole design.** The switch lives
in Settings › General › Widget. When it is on, `buildWidgetSnapshot(hideTitles:)`
never writes a task's title (nor, since v5, a calendar event's): every row, the lock screen's `next` and every project's
view carry the placeholder ("Private task" / "Gizli görev") while ids, times, counts
and project colors stay, so the widget still works. A title written to the App Group
with a "do not show" flag for native code would already have left the app.

- **The live app does not publish until the setting has been read.** Every other
  device-local preference answers its default first and reads storage after; for
  this one that would mean "not private" published once at every start — the titles
  in the App Group for a moment, and for good if the app died in it. So it is an
  `AsyncNotifier` (`WidgetPrivacy`) with no answer until storage has spoken, and
  `widgetSyncProvider` returns without publishing while it has none.
- **The background turn reads the same key** (`kWidgetPrivatePrefKey`), so the
  midnight redraw (OPH-334) hides exactly what the app hides.
- **Project names stay.** They name the list a widget was set to (§3.1, OPH-336) and
  the configuration sheet offers them; the setting's own words promise task titles.
- **Known limit, shared with notification privacy:** device storage degrades to "no
  persistence" rather than throwing (`LocalKv`), so if it cannot be read at all the
  setting reads as never set — the same behaviour OPH-064's switch has.
- Tests read the JSON the host was handed, every string of it (`widget_private_test`).

## 10. Reference apps — what we're stealing (design targets)

- **Apple Reminders:** circular checkbox, **tap-to-complete in place** (iOS 17+),
  completed item fades away; per-instance list; small = count. → our complete UX.
- **Apple Calendar:** **date header (day-of-week name + big day number)**, "Up
  Next", the day's event list, **month grid at large**. → our header + largest tier.
- **TickTick:** breadth-by-intent (today list, calendar, matrix, habits, pomodoro,
  countdown) + always-present **quick-add "+"**. → quick-add; future variants.
- **Todoist:** scrollable task list, tap-circle complete, **in-widget filter
  switcher**, **compact/density** toggle, separate add-task shortcut. → density
  built (OPH-337); the in-widget switcher was not — the per-widget list (OPH-336)
  answers the same need.
- **Things 3:** **configurable-per-instance list**, **This Evening** sub-bucket,
  **+** button whose destination follows the widget's list. → configurable widget
  built (OPH-336); our "+" opens the plain create sheet, not the widget's project.
- **Structured:** day **timeline**, "current + next task with countdown"
  (lock-screen). → the lock-screen rectangle (OPH-336) names the next task, without
  a countdown.
- **Fantastical:** combined calendar **+ tasks under one date header**. → validates
  our header-over-list layout.

## 11. Version-sensitivity flags (encode in tasks)

- **iOS 16 floor:** static + deep-link widgets, accessory (Lock Screen) families.
  No in-widget completion → deep-link fallback.
- **iOS 17 / iPadOS 17 / macOS 14 floor:** interactivity (`Button/Toggle(intent:)`
  + `AppIntent`), `AppIntentConfiguration`/`AppIntentTimelineProvider`. `home_widget`
  interactivity is `@available(iOS 17, *)`.
- **iOS 18:** Control Center / Lock-Screen `ControlWidget` — a *different* surface;
  optional future "quick add from Control Center."
- **iOS 26 / macOS 26 (current):** new "Liquid Glass" system chrome — use
  `.containerBackground` so the OS themes the widget; don't hard-code backgrounds.
- **`systemExtraLarge`:** iPad + macOS only; safe in `supportedFamilies` (filtered
  on iPhone). **Pin `home_widget` (v0.9.3)** and re-verify the Android receiver and
  the macOS bridge against it when it moves. `androidx.glance` is in the build only
  as `home_widget`'s dependency — the widget itself is RemoteViews.

## 12. Sources

WidgetKit families & sizes: <https://developer.apple.com/documentation/widgetkit/widgetfamily>,
<https://developer.apple.com/documentation/widgetkit/supporting-additional-widget-sizes> ·
measured sizes: <https://github.com/simonbs/ios-widget-sizes> ·
interactivity: <https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities> ·
refresh budget: <https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date> ·
App Intents: <https://developer.apple.com/documentation/appintents/appintent> ·
Flutter iOS app extensions: <https://docs.flutter.dev/platform-integration/ios/app-extensions> ·
Flutter macOS (sandbox/entitlements): <https://docs.flutter.dev/platform-integration/macos/building> ·
Android widget sizing: <https://developer.android.com/design/ui/mobile/guides/widgets/sizing> ·
flexible layouts: <https://developer.android.com/develop/ui/views/appwidgets/layouts> ·
collections: <https://developer.android.com/develop/ui/views/appwidgets/collections> ·
Jetpack Glance: <https://developer.android.com/develop/ui/compose/glance/build-ui> ·
`home_widget`: <https://pub.dev/packages/home_widget> ·
interactive `home_widget`: <https://docs.page/abausg/home_widget/features/interactive-widgets> ·
Glance+Flutter: <https://medium.com/@ABausG/jetpack-glance-home-screen-widgets-with-flutter-810c5121422f> ·
Flutter codelab: <https://codelabs.developers.google.com/flutter-home-screen-widgets> ·
Reminders widget (iOS 17 interactive): <https://appleinsider.com/inside/ios-17/tips/how-to-use-interactive-widgets-in-ios-17> ·
Things widgets: <https://culturedcode.com/things/support/articles/2803567/> ·
Todoist Android widgets: <https://www.todoist.com/help/articles/use-a-todoist-widget-on-your-android-device-632pZA> ·
TickTick widgets: <https://help.ticktick.com/articles/7055780404896202752> ·
Structured widgets: <https://help.structured.app/en/articles/330498> ·
Fantastical widgets: <https://flexibits.com/fantastical-ios/help/widgets>
