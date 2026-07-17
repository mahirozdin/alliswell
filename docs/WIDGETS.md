# WIDGETS — Home-screen / desktop widgets (binding research & design plan)

> Plan for **Epic 12 (OPH-130…136)**. This is the researched, citation-backed
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

## 0. Implementation status (2026-07-17)

| Piece | Status |
| --- | --- |
| Dart snapshot core (`groupTasksForWidget`, `WidgetSnapshot`, `WidgetBridge`) | ✅ **done + unit-tested** (OPH-130) |
| Android widget — rendering + tap-to-open | ✅ **written, `flutter build apk` green** (OPH-133); RemoteViews (not Glance) |
| iOS widget — SwiftUI + timeline | 🟡 **Swift written** (`apps/app/ios/AllisWellWidget/`), awaiting the Xcode target + device — see that folder's `SETUP.md` (OPH-131) |
| In-widget complete / quick-add (App Intents / Glance actions) | ⏳ deferred — background isolate + device (OPH-132, shared Android bit) |
| macOS widget | ⏳ deferred — blocked on the macOS signing gap (OPH-134) |
| Configurable list, accessory tier, private-widget, WorkManager midnight | ⏳ deferred (OPH-135) |
| Device visual/QA pass (all sizes, light+dark, sync) | ⏳ needs a real device/emulator |

The Dart core is the single source of truth both native widgets render; it's the
only fully unit-testable piece, and it's done. The native layers are verified by
build (`apk` green; iOS awaits its Xcode target) — the on-device *visual* pass is
tracked like the notification/EventKit device passes.

## 1. What we are building

A single glanceable surface that mirrors **Home**: the user's tasks bucketed
chronologically, an Apple-Calendar-style date header at the larger sizes, and
Apple-Reminders-style **quick-add** + **tap-to-complete** that work without
opening the app. It must **stay in sync** with task data at all times.

The buckets are exactly Home's, reused from the tested `groupTasksForHome`
philosophy (a sibling pure function `groupTasksForWidget`): **Overdue → No date →
Today → This week → This month**, scrollable inside the widget. ("This month"
replaces Home's "Next 30 days" tail — a widget is a glanceable agenda and the user
asked for a monthly horizon; horizon = end of the current month, capped so
recurring events can't flood it.)

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
resizable**, so the three Android sizes are *defaults* — build one responsive
layout (Android 12+ `RemoteViews(Map<SizeF, RemoteViews>)` / Glance size
handling), not three pixel-perfect ones. Declare Android 12+ `targetCellWidth/
Height` (cells) **and** legacy `minWidth/minHeight` dp (`70·n − 30` rule) with
`resizeMode="horizontal|vertical"` + sensible `minResize*`/`maxResize*`.

**Lock-screen / StandBy** accessory families (`accessoryCircular/Rectangular/
Inline`, iOS 16+) are a separate, tiny surface — a good bonus tier ("next task",
count) tracked under OPH-136, not one of the three main sizes.

## 3. Data bridge — app → widget

The widget is a **separate process with its own sandbox** and **cannot open the
drift/SQLite replica**. The sanctioned bridge is a shared container:

- **iOS/macOS:** an **App Group** (`group.com.alliswell.alliswell`) shared
  `UserDefaults(suiteName:)` (small snapshots) and/or container file (blobs).
- **Android:** **SharedPreferences** the widget process reads.

`home_widget` wraps both:

```dart
// once, in main():
await HomeWidget.setAppGroupId('group.com.alliswell.alliswell'); // iOS/macOS
await HomeWidget.registerInteractivityCallback(widgetCallback);

// after any relevant task change:
await HomeWidget.saveWidgetData<String>('aw_snapshot', jsonEncode(snapshot));
await HomeWidget.updateWidget(
  iOSName: 'AllisWellWidget',
  androidName: 'TasksWidgetProvider',
  qualifiedAndroidName: 'com.alliswell.alliswell.TasksWidgetProvider',
);
```

The native timeline provider / Glance widget reads the same key back and renders
it. **The widget never computes buckets or touches the DB** — the app owns that.

### 3.1 The snapshot contract

Keep it **small** (single-digit KB — App-Group `UserDefaults` is memory-mapped and
the widget extension has a ~30 MB budget). Serialize only what renders, with
**already-localized** strings (Epic 11):

```jsonc
{
  "v": 1,                         // snapshot schema version
  "generatedAt": "2026-07-17T09:00:00Z",
  "locale": "tr",
  "date": { "weekday": "Cuma", "day": "17", "month": "Temmuz" },
  "counts": { "overdue": 3, "today": 5, "week": 12 },
  "buckets": [
    { "key": "overdue", "label": "Gecikmiş",
      "items": [ { "id": "01H…", "title": "Teklifi bitir", "done": false,
                   "time": "11:30", "projectColor": "#2563EB" } ] },
    { "key": "today", "label": "Bugün", "items": [ /* … top N … */ ] }
    // … noDate, week, month …
  ],
  "more": { "today": 2 }          // "+N more" when a bucket is truncated
}
```

- **N per bucket is per-size** (§5): medium shows few, large ~8–10, extraLarge
  more. Truncation is honest — show a "+N more" affordance, never silently drop
  (the "no silent caps" ethos).
- `projectColor` is user data (hex allowed here — it's a data value, not UI chrome;
  DESIGN G6 exception). The native side computes readable ink over it, mirroring
  the "Project badge" contrast helper (DESIGN §4).
- Times/dates are pre-formatted by the app in the active locale (no native
  date formatting → no second i18n system).

## 4. Interactivity — quick-add & quick-complete

**iOS 17+ / iPadOS 17+ / macOS 14+ (the real mechanism):** SwiftUI
`Button(intent:)` / `Toggle(isOn:intent:)` whose action is an **`AppIntent`**;
WidgetKit runs `perform()` **in the background, no app launch**, then reloads.
This is the Reminders "tap the circle to complete" behavior. Configurable widgets
use `AppIntentConfiguration` + `AppIntentTimelineProvider`; plain interactivity
works on a `StaticConfiguration` too.

**Android:** a Glance `Checkbox`/`Button` with `actionRunCallback<T>()` (or a
RemoteViews collection with a `setPendingIntentTemplate` + per-row
`setOnClickFillInIntent`) fires a background broadcast.

**The `home_widget` bridge (both platforms → one Dart callback):**

```dart
@pragma('vm:entry-point')          // MANDATORY — survives tree-shaking & app-kill
Future<void> widgetCallback(Uri? uri) async {
  switch (uri?.host) {
    case 'complete': await taskStore.complete(uri!.queryParameters['id']!); break;
    case 'add':      await taskStore.create(workspaceId, {'title': …});     break;
  }
  await HomeWidget.updateWidget(iOSName: 'AllisWellWidget', androidName: 'TasksWidgetProvider');
}
```

- iOS: the `AppIntent.perform()` calls `HomeWidgetBackgroundWorker.run(url:appGroup:)`;
  the **`AppIntent` .swift must be a member of BOTH the Runner and the Widget
  Extension targets** (the #1 cause of "button does nothing").
- Android: `HomeWidgetBackgroundIntent.getBroadcast(context, uri)`; the
  `es.antonborri.home_widget.HomeWidgetBackgroundReceiver` must be in the manifest.
- Completing/adding goes through **`TaskStore`** — the same optimistic-write +
  outbox path the UI uses (AGENTS §4 local-first), so a widget edit **syncs to the
  server** and every device converges. This is non-negotiable: the widget must not
  have its own write path.
- **Pre-iOS-17 floor: deep link only.** The tap opens the app at
  `alliswell://task/{id}` (ADR-0003) / `alliswell://add`; gate interactive code
  `@available(iOS 17, *)`. UX lesson from Reminders: the complete hit-target is
  easy to fumble — make it **generous and deliberate**, and animate the row away
  after ~1–2 s so the tap feels acknowledged.

## 5. Content per size

| Size | Date header | List | Actions |
| --- | --- | --- | --- |
| **4×2 medium** | compact (day number + weekday) | top 3–4 rows, no bucket labels; Overdue/Today first | one **quick-add "+"** ; rows tap-to-complete |
| **4×4 large** | full (weekday name + big day number) | scrollable bucketed list ~8–10 rows with bucket labels + counts | quick-add row + per-row complete |
| **4×6 / extraLarge** | full + optional **week strip / mini month grid** (Apple-Calendar style) | richest scroll; may split into two columns (tasks ∥ agenda) on extraLarge | quick-add + complete; densest triage |

Buckets recompute at **local midnight** so Today/Overdue roll over even if the app
never opens (§6). Empty state: a calm "All caught up" mirroring Home.

## 6. Freshness & refresh budget

**Apple's budget:** ~**40–70 timeline reloads/day**, dynamic per how often the
widget is viewed. **Exemptions that make our sync free:** the containing app is in
the **foreground**, and **the widget performs an app intent**. Android has no such
budget but `updatePeriodMillis` has a **30-minute floor** and wakes the device.

**Strategy (both platforms):**
1. **Push on write, primary:** after every relevant `TaskStore` mutation, call
   `HomeWidget.updateWidget(...)`. While the app is foreground these reloads are
   **budget-exempt** → the widget stays in lock-step for free. Do it in the store/
   bridge layer, not per screen.
2. **Self-refresh, safety net:** a sparse WidgetKit timeline
   (`TimelineReloadPolicy.after`, entries ≥5 min apart) + a **midnight** entry for
   date rollover; on Android a **WorkManager** (or `AlarmManager` RTC) job at local
   midnight re-pushes. Keep sparse to live within 40–70/day.
3. Prefer `WidgetCenter.shared.reloadTimelines(ofKind:)` over `reloadAllTimelines()`.

## 7. Setup — extension targets & files committed to git

A widget is an **App-Extension target**; a Flutter plugin package **cannot** vend
one. So — unlike the EventKit SwiftPM plugin — **`project.pbxproj` edits and
entitlements are unavoidable and committed** (ADR-0010, deliberate deviation).

**iOS (`ios/`):** Xcode ▸ File ▸ New ▸ Target ▸ **Widget Extension**
(`AllisWellWidget`). Add **App Groups** capability (`group.com.alliswell.alliswell`)
to **both** Runner and the extension. Commit: the extension's Swift (widget view,
`TimelineProvider`/`AppIntentTimelineProvider`, the shared `AppIntent`), its
`Info.plist`, `Assets.xcassets`, **both** `.entitlements`, the **`project.pbxproj`**
diff, and the `Podfile` change that links `home_widget` into the extension. Match
the extension's min-iOS to Runner; keep the "Thin Binary" build phase last (Flutter
guidance).

**macOS (`macos/`):** same, plus **App Sandbox** — add
`com.apple.security.application-groups` to **`DebugProfile.entitlements` AND
`Release.entitlements`** (edit the plists directly). The App-Group string must be
**byte-identical** across Dart `setAppGroupId`, Runner, and extension; decide the
`group.…` vs `<TeamID>.group.…` form once (macOS `home_widget` won't add the team
prefix for you). **Gated on the inherited macOS signing gap** (STATE: no macOS dev
cert → `flutter build macos` fails today), like the EventKit macOS path.

**Android (`android/app/src/main/`):** `kotlin/com/alliswell/alliswell/
TasksWidgetProvider.kt` (Glance `GlanceAppWidget` + `GlanceAppWidgetReceiver`, or
`AppWidgetProvider`), `res/xml/tasks_widget_info.xml` (sizing/resize/period), any
`res/layout/*` (RemoteViews path only), and `AndroidManifest.xml` receivers (the
provider **and** the `home_widget` background receiver). Verify with a real
`flutter build apk` — `flutter analyze`/`flutter test` do **not** compile Kotlin.

**Verification reality (the EventKit lesson):** `flutter analyze` + `flutter test`
compile **no** Swift/Kotlin. Every native widget task is only proven by a real
`flutter build ios`/`apk`/`macos` **and** a device/simulator pass. The one fully
unit-testable piece is the Dart snapshot core (§8).

## 8. What is (and isn't) unit-testable

- **Green in `flutter test`:** `groupTasksForWidget` (bucket boundaries, midnight,
  horizon, event rules — mirror `task_grouping_test`), the snapshot serializer
  (JSON shape, per-size truncation + "+N more", localized labels), the `WidgetBridge`
  (writes + `updateWidget` on task-stream change, via a fake `HomeWidget`), and the
  interactivity callback (`complete`/`add` → fake `TaskStore`).
- **Only by build + device:** the SwiftUI/Glance views, the extension targets,
  entitlements/App-Group wiring, App-Intent registration, timeline refresh, deep
  links. Record device results in STATE like the notification/EventKit passes.

## 9. Privacy

The snapshot carries task **titles** and lives in the sandbox-protected App-Group
container. Offer a **"Private widget"** switch (same spirit as OPH-064 "Private
notifications"): when on, the widget renders **counts and placeholders** ("3
tasks") instead of titles — a glanceable surface others can see over your shoulder
shouldn't leak content by default for users who care. Setting is device-local.

## 10. Reference apps — what we're stealing (design targets)

- **Apple Reminders:** circular checkbox, **tap-to-complete in place** (iOS 17+),
  completed item fades away; per-instance list; small = count. → our complete UX.
- **Apple Calendar:** **date header (day-of-week name + big day number)**, "Up
  Next", the day's event list, **month grid at large**. → our header + largest tier.
- **TickTick:** breadth-by-intent (today list, calendar, matrix, habits, pomodoro,
  countdown) + always-present **quick-add "+"**. → quick-add; future variants.
- **Todoist:** scrollable task list, tap-circle complete, **in-widget filter
  switcher**, **compact/density** toggle, separate add-task shortcut. → density +
  future in-widget switcher (OPH-136).
- **Things 3:** **configurable-per-instance list**, **This Evening** sub-bucket,
  **+** button whose destination follows the widget's list. → configurable widget
  (OPH-136).
- **Structured:** day **timeline**, "current + next task with countdown"
  (lock-screen). → accessory tier idea (OPH-136).
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
  on iPhone). **Pin `home_widget` (v0.9.3) and `androidx.glance`** at build time and
  re-verify the macOS extension plumbing against the pinned versions.

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
