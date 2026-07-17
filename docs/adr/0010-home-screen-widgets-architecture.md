# ADR-0010 — Home-screen / desktop widgets: native views over an App-Group snapshot

- **Status:** Accepted
- **Date:** 2026-07-17
- **Related task:** Epic 12 (OPH-130…136)
- **Related:** feedback round 5 (user request: iOS/Android/macOS home-screen
  widgets in three sizes that stay in sync with tasks, summarize the Home buckets
  in a scroll, carry an Apple-Calendar-style date header at the largest size, and
  offer quick-add + quick-complete like Apple Reminders); docs/WIDGETS.md (the
  binding research/design plan); BLUEPRINT §12.8, §15.6; docs/DESIGN.md §8;
  ADR-0003 (`alliswell://task/{id}` scheme reused for widget deep links)

## Context

The app must gain **home-screen / desktop widgets** on the platforms that have
that surface (iOS, iPadOS, Android, macOS). Requirements: three sizes; the widget
mirrors Home's chronological buckets (Overdue → No date → Today → This week → This
month) in a scroll; the largest size shows an Apple-Calendar-style date header
(day-of-week name + day number, optional month/week strip); and quick-add +
tap-to-complete work **from the widget without opening the app** (Apple Reminders
behavior). The widget must **stay in sync** with task data.

Three hard platform facts shape everything (full citations in docs/WIDGETS.md):

1. **A widget runs in a separate process/sandbox and cannot read the app's drift/
   SQLite replica.** Data must cross a shared container.
2. **A widget is an OS App-Extension target**, not something a Flutter plugin
   package can vend. Unlike the EventKit bridge (a federated SwiftPM plugin,
   pbxproj untouched), widgets **require committed Xcode targets + `project.pbxproj`
   edits + entitlements** in `ios/` and `macos/`, and a native receiver in
   `android/`.
3. **iPhone's largest home-screen widget is `systemLarge` (4×4, ~2/3 screen).**
   There is **no 4×6 / full-screen home-screen widget on iPhone** in WidgetKit —
   the only size above 4×4 is `systemExtraLarge` (~8×4 landscape), **iPad + macOS
   only**. The user's "4×6 / full screen" tier therefore cannot exist on iPhone.

## Decision

1. **Bridge with the `home_widget` package** (Dart ↔ native). It wraps App Groups
   (iOS/macOS) and SharedPreferences (Android) behind one API — `setAppGroupId`,
   `saveWidgetData`, `getWidgetData`, `updateWidget`, `registerInteractivityCallback` —
   and provides the background-intent plumbing (`HomeWidgetBackgroundWorker.run`
   on iOS, `HomeWidgetBackgroundIntent.getBroadcast` on Android). New dependency.
2. **The widget renders a minimal, app-produced JSON snapshot — not the DB, not a
   Flutter render.** A pure `groupTasksForWidget` (sibling of `groupTasksForHome`,
   fully unit-tested) projects the open-task + event streams into buckets; a
   serializer writes a **small** JSON snapshot of exactly what the widget shows
   (date-header fields, each bucket's top *N* rows with `{id, title, done,
   projectColorHex, timeLabel}`, and per-bucket counts). Labels are **already
   localized by the app** (Epic 11 / ADR-0009) so the native widget carries no
   translation bundle. Keep the snapshot in single-digit KB (App-Group
   `UserDefaults` is memory-mapped and the widget extension has a ~30 MB budget).
3. **Native views for the interactive tiers (SwiftUI on Apple, Jetpack Glance on
   Android), NOT `renderFlutterWidget`.** Interactivity (`Button/Toggle(intent:)`,
   Glance `actionRunCallback`) requires real native controls; a rasterized Flutter
   image cannot host per-row buttons. `renderFlutterWidget` is reserved, if ever,
   for a non-interactive rich tier.
4. **Quick-complete / quick-add run through the local-first store.** Widget taps
   fire an `AppIntent` (iOS 17+/macOS 14+) or a Glance action (Android) →
   `home_widget` background isolate → a `@pragma('vm:entry-point')` Dart callback →
   `TaskStore.complete()` / `TaskStore.create()` (the SAME optimistic-write +
   outbox path the UI uses, so widget edits sync to the server) → `updateWidget`.
   **Pre-iOS-17 floor: deep link only** — the tap opens the app at
   `alliswell://task/{id}` (ADR-0003) / `alliswell://add`, gated `@available(iOS
   17, *)`.
5. **Freshness = foreground push + a light self-refresh timeline.** After every
   relevant drift write, while the app is foreground, call `updateWidget` — these
   reloads are **budget-exempt** (Apple), so the widget stays in lock-step for
   free; app-intent taps on the widget are exempt too. A sparse WidgetKit timeline
   (`.after`/midnight rollover) and an Android WorkManager midnight job re-bucket
   Today/Overdue when the app never opens, staying inside Apple's 40–70 reloads/day.
6. **Size mapping, with the iPhone ceiling documented as a constraint:**
   | User tier | Apple family | Android | iPhone reality |
   | --- | --- | --- | --- |
   | 4×2 (~⅓) | `systemMedium` | 4×2 cells | ✅ |
   | 4×4 (~⅔) | `systemLarge` | 4×4 cells | ✅ (iPhone max) |
   | 4×6 / full | `systemExtraLarge` (iPad/macOS only) | true 4×6 (resizable) | ❌ → degrades to `systemLarge` |
   `supportedFamilies: [.systemMedium, .systemLarge, .systemExtraLarge]` (iPhone
   filters out extraLarge automatically). Android widgets are user-resizable, so
   the three are *defaults*, built as responsive `SizeF` layouts.
7. **App Group id `group.com.alliswell.alliswell`**, byte-identical across the
   Dart `setAppGroupId`, both iOS entitlements (Runner + extension), and both
   macOS entitlements (DebugProfile + Release). macOS needs App-Sandbox +
   `com.apple.security.application-groups`; entitlements are edited **directly in
   the plist files** (Flutter guidance), and the `<TeamID>.group.…` vs `group.…`
   form is decided once and used consistently (macOS `home_widget` does not add
   the team prefix for you).
8. **Platform scope:** iOS, iPadOS, Android, macOS get widgets. **Web, Windows,
   Linux have no home-screen-widget surface in scope** (Windows Widgets Board is a
   separate niche API, deferred) — the feature hides itself there, like the Apple
   calendar card does off-Apple platforms.
9. **Privacy:** the snapshot carries task titles and lives in the sandbox-
   protected App-Group container. A **"Private widget"** option (reusing the
   Epic-07 privacy ethos) renders counts/placeholders instead of titles for users
   who don't want content on a glanceable surface. Documented in §15.6.

## Alternatives considered

- **`renderFlutterWidget` (rasterize the Flutter UI to a PNG in the shared
  container).** One UI, pixel-identical to the app. Rejected as the primary path:
  a bitmap **can't be interactive** (no per-row complete/add buttons), doesn't get
  native Dynamic Type / dark-mode adaptation, and re-renders on every change.
  Kept only as a possible non-interactive rich tier.
- **Read the drift DB from the extension.** Impossible: separate sandbox; the
  containing app may not even be running. App Groups are the sanctioned bridge.
- **Ship widgets as a Flutter plugin package (as EventKit was).** Impossible: a
  plugin package cannot vend an App-Extension target. This is the deliberate
  deviation from the "no pbxproj surgery" pattern — recorded here so the committed
  `project.pbxproj`/entitlements diffs read as intentional, not accidental.
- **Honor a real 4×6 on iPhone.** Not offered by WidgetKit; cannot be built.
  Delivered as far as the platform allows (extraLarge on iPad/Mac, true 4×6 on
  Android, `systemLarge` ceiling on iPhone).

## Consequences

- New committed native surface in `ios/` (Widget Extension target, entitlements,
  SwiftUI + `AppIntent` shared with Runner), `macos/` (same, sandboxed), and
  `android/` (Glance provider + receiver + XML). `project.pbxproj` is now
  load-bearing — `flutter analyze`/`flutter test` do **not** compile Swift/Kotlin,
  so every native task is gated on a real `flutter build ios`/`apk`/`macos` and a
  device pass (the EventKit lesson, STATE "Blocked / notes").
- **macOS is gated on the inherited signing gap** (STATE: no macOS dev cert →
  `flutter build macos` fails today). OPH-135 ships the code but its device
  verification waits on the same cert as EventKit — not a blocker for iOS/Android.
- **Epic 12 depends on Epic 11 (i18n):** the snapshot writer needs the i18n facade
  to emit localized bucket/date labels. Ordering is i18n first, widgets second.
- `groupTasksForWidget` + the serializer are the only fully green-testable pieces;
  they carry the correctness weight (buckets, truncation, localization, "writes &
  updates on change"). The native layers are verified by build + device.
- Reuses the `alliswell://` scheme (ADR-0003) for widget deep links — the app's
  `onOpenURL`/router must accept `task/{id}` and a new `add` route.
- Establishes docs/WIDGETS.md as the binding widget plan (the NOTIFICATIONS.md /
  CALDAV.md analog) and DESIGN §8 as the widget visual spec.
