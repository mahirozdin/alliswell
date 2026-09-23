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
| Midnight rollover (Android) | ✅ **OPH-334:** the background turn ends by republishing the snapshot from the replica (`publishWidgetFromReplica`), and `WidgetMidnightWorker` asks for that turn at the next local midnight — the six-hourly OPH-321 worker alone could leave yesterday's buckets up until morning. Not exact under Doze, by design. Like every Android background turn it is a broadcast to `home_widget`'s receiver, which only exists since OPH-341 |
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
far-future or recurring item cannot flood it.)

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

The shape as built (`v: 4`, `WidgetSnapshot.toJson()` in `widget_snapshot.dart`;
the Swift `AWSnapshot` and the Kotlin readers mirror it). The revisions below say
when each field arrived and why:

```jsonc
{
  "v": 4,                                   // schema version
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
                   "priority": "high", "time": "11:30", "projectColor": "#2563EB" } ],
      "more": 2 }                           // "+N" — count minus the rows carried (12 max)
    // … noDate, today, thisWeek, thisMonth; empty buckets are omitted …
  ],
  "lists": [ … ],                           // v4 — what a widget can be set to
  "views": { … }                            // v4 — one per project in `lists`
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

- **What it counts, exactly:** tasks that are **overdue** plus tasks **due today**,
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
| **4×2 medium** | none — the rows need the height | 4 rows with bucket labels + counts (3 when the widget is set to a project: its name takes a line) | "+" in a narrow trailing column; per-row complete |
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
never writes a task's title: every row, the lock screen's `next` and every project's
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
