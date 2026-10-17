# ADR-0057 — Voice capture: Siri / Shortcuts intents in the app, Android launcher shortcuts

- **Status:** Accepted
- **Date:** 2026-10-17
- **Related task:** OPH-376
- **Related:** [ADR-0016](0016-in-app-url-routing-and-widget-actions.md) (`alliswell://` only navigates; writes
  from outside go through App Intents into a mailbox), [ADR-0029](0029-share-extension-notifies-instead-of-redirecting.md)
  (the share mailbox drained on bind and resume), [ADR-0054](0054-offline-quick-add-grammar.md)
  (the offline quick-add parser).

## Context

The 2026-10-16 research found people building workarounds just to add a task by voice without
opening an app ("Hey Siri, add …"). AllisWell had a widget complete intent and a share target,
but no voice entry. The owner asked for iOS/macOS App Intents with an "Add task" intent whose text
goes through the OPH-373 parser ("yarın 9'da kira" gets its date), ideally "Show today", and on
Android whatever actually works in 2026.

Constraints:

- The parser, `TaskStore` + outbox, tag and series creation, and alarm scheduling all live in
  Dart. Nothing in Swift can create a task the app would treat as its own.
- Starting Flutter headless from an intent crashed before (LESSONS ios-native: a
  `LiveActivityIntent` always runs in the app).
- ADR-0016: a URL is untrusted input and never writes; `alliswell://add` takes no parameters.
- Private widget mode: task titles must not sit in the App Group.
- Android, October 2026: the built-in-intent catalogue has no task or note creation intent (the
  `CREATE_THING`-style intents went in the 2023 narrowing); Google Assistant is being replaced by
  Gemini on phones from 2026-09-04, and Gemini's use of `shortcuts.xml` capabilities is not
  documented; AppFunctions needs Android 16+, is an experimental preview, and only curated apps
  reach Gemini.

## Decision

1. **iOS and macOS intents run in the app and bring it forward.** `AWAddTaskIntent` and
   `AWShowTodayIntent` (`apps/app/ios/Shared/AWAppShortcuts.swift`) are plain `AppIntent`s with
   `openAppWhenRun = true`, compiled into the iOS Runner and the macOS Runner only (never a widget
   extension), with an `AppShortcutsProvider` (`AWAppShortcuts`) that gives Siri, Spotlight and
   the Shortcuts app their phrases. `perform()` only parks the request; Dart, now in front,
   creates the task. A task added in the background would not arm its alarm until the app next
   ran, which an alarm-grade product cannot accept.
2. **A small mailbox carries the words.** `UserDefaults.standard` key `aw_capture_pending`
   (`[{id, kind: add|today, text?, at}]`, cap 32 entries, 500 characters), read-and-clear over
   the `alliswell/capture` channel (`take`; `changed` wakes a warm app). Standard defaults, not
   the App Group: the intent runs in the app process, and dictated text has no business in a
   container widgets read. Not a URL (ADR-0016), not the AlarmKit action queue (it carries
   ids only).
3. **One capture rule.** `capture_inbox.dart` drains on bind, every resume, the `changed` signal
   and the workspace arriving; it waits for a workspace before it takes, so a request made while
   signed out stays parked. Each `add` goes through `awParseQuickAdd` + `createCapture`, the
   exact rule of the Inbox quick-add bar: dateless → Inbox; dated → open with the quick-add
   defaults and the derived reminder. HomeShell confirms with a SnackBar ("Added: …", with
   "Open"). `today` opens `/home?day=<today>`, the location a widget event row opens.
4. **Availability iOS 16 / macOS 13.** The Runner keeps its iOS 15 / macOS 12 minimum; the bridge
   is not availability-gated. A String parameter cannot appear in an App Shortcut phrase, so
   Siri asks "What's the task?" / "Görev ne?" after the phrase.
5. **Localized by the system.** `ios/Shared/{en,tr}.lproj/AppShortcuts.strings` (phrases, each
   naming `${applicationName}`) and `Localizable.strings` (titles, dialog, summary). Both Runner
   projects gain `tr` in `knownRegions`. `INAlternativeAppNames` "All is well" helps Siri hear
   the name. Wiring is `ios/scripts/wire_app_shortcuts.rb` (idempotent, both projects).
6. **Android: static launcher shortcuts only.** `res/xml/shortcuts.xml` declares "New task"
   (`alliswell://add` → the create sheet) and "Today" (`alliswell://open` → Home), localized in
   `values` / `values-tr`. Long-press the icon, or pin one. No App Actions capability, no
   AppFunctions, no `AUTO_SEND` or `CREATE_NOTE` filter.
7. **Rule 12:** no MCP or public API change — creating a task already exists as MCP
   `create_task` and REST `POST /tasks`; this adds only a client entry point.

## Alternatives considered

- **Background intent in the app (`openAppWhenRun = false`).** Rejected: no Dart, so no alarm
  until the next launch, and a headless Flutter start from an intent already crashed once.
- **An App Intents extension with a Swift parser writing to the replica or the API.** Rejected:
  a second parser means a parity burden forever, and the extension cannot arm Dart's alarms or
  use the outbox; it would also need the session in the extension.
- **Write by URL (`alliswell://add?title=…`).** Rejected by ADR-0016: any link could put words
  into the task list.
- **A spoken Siri summary for "Show today".** Rejected: it needs a Swift reader of the replica or a
  titled snapshot in the App Group, which private widget mode forbids.
- **Android App Actions (`<capability>` in `shortcuts.xml`).** Rejected: no built-in intent fits
  task creation, Assistant is leaving phones, and Gemini support is undocumented — shipping it
  would promise a voice path nobody can verify.
- **Android AppFunctions.** Rejected for now: Android 16+, experimental, curated apps only.
- **`AUTO_SEND` ("note to self") or the Android 14 `CREATE_NOTE` notes role.** Rejected: no current
  Google assistant emits `AUTO_SEND`, an exported filter that writes silently lets any app
  inject tasks, and the notes role is the stylus / lock-screen notes app, not task capture.

## Consequences

- iPhone and Mac: "Hey Siri, add a task in AllisWell" (TR "AllisWell'e görev ekle"), the
  Shortcuts app and Spotlight all add a task, offline too; the app comes to the front for it.
- The Swift cannot be compiled on Linux: the owner builds it in Xcode and runs the Siri checks
  (DEVICE-CHECKS "Siri ve kısayollar"). If `AppShortcut(intent:phrases:shortTitle:systemImageName:)`
  turns out to be iOS 17 only, raise the three types to iOS 17 / macOS 14 or drop the two
  arguments.
- Adding `tr` to the Runner bundles enables the per-app language picker in iOS Settings; the
  Flutter UI keeps its own language setting.
- Android users get two launcher shortcuts; by voice, the path is "Hey Google, open AllisWell".
  Revisit when Gemini documents an app-capability API for task creation.
- The Android Today shortcut opens plain Home (a static XML cannot hold today's date), while iOS
  selects today — a small platform difference.

## Sources

- Apple: App Intents, `AppShortcutsProvider`, `AppShortcut`, `INAlternativeAppNames`.
- Google: App Actions built-in intents reference; Assistant → Gemini transition notice (2026);
  Android AppFunctions (Android 16, experimental).
