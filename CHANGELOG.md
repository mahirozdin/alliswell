# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added — Epic 19 in progress

- **The Repeat switch, the dialog and the sentence (OPH-207).** Task detail
  gains a **Tekrarla** switch that opens the rule dialog the first time it goes
  on — cancel and it goes straight back off, because a switch that leaves a
  half-configured rule behind is a lie about state. The dialog opens on presets
  (day/week/weekdays/month/year) with everything else one disclosure deeper: day
  of the month (including "the last day"), the Nth weekday, and "the first
  {weekday} after day N" — with a live **"Sonraki 5"** preview that shows the
  clamp honestly (pick the 31st and February reads 28). A configured rule reads
  as one generated sentence per language, never as a form summary. Editing one
  occurrence asks how far the change reaches, defaulting to "this and future" —
  except for a date, where it defaults to "only this one". drift **v14** carries
  `task_series` and the two occurrence columns; the Dart engine is a port pinned
  to the server's by a shared parity fixture that both suites assert.

- **Editing one occurrence asks how far it reaches (OPH-206).** A task edit can
  now carry `seriesScope`: **just this** (the default — nothing else moves),
  **this and future** (the series splits: the old one gets an `until`, a new one
  is born, and the row you were editing keeps its id instead of being replaced),
  or **all** (the template and every live occurrence follow, past ones included —
  but never their status or completion, which is history). It rides an ordinary
  `update` mutation, so it works offline like everything else. Two rules the
  implementation settled: "just this" **keeps** the row in its series (cutting it
  loose would free the slot and let the next sweep duplicate the day), and a
  scoped date edit moves **the time of day**, never the pattern.

- **Recurring tasks, server side (OPH-205).** A new `task_series` entity holds
  the rule and the template; every occurrence it produces is an **ordinary task
  row** carrying `series_id` + `occurrence_date`, materialized into a rolling
  **12-month window** and kept fresh by a daily sweep. That is the whole trick:
  the widget, search, the alarm planner and the calendar mirror handle recurring
  tasks correctly without learning what recurrence is. The engine
  (`src/lib/recurrence.js`) is pure calendar math with the ADR-0020 clamping, and
  is pinned to its Dart preview port by a parity fixture both suites assert.
  Series sync like any other entity, so a repeating task created offline arrives
  complete with its occurrences. Flipping Repeat on an existing task **adopts**
  that task as its own occurrence instead of duplicating it; a rule change
  rebuilds the future and never touches the past or anything completed; stopping
  a series keeps every occurrence that already happened.
  `tasks.repeat_rule` left the write path in the same change.

### Changed — Epic 19 in progress

- **The recurrence rule model is decided, and it clamps (OPH-204, docs only).**
  A sourced round across RFC 5545, RFC 7529, Google Calendar, Outlook, Todoist,
  TickTick and Apple Reminders settled the question the feature turns on: the same
  intent ("the 31st of every month") **skips** February in Google and RFC 5545 —
  where an invalid instance "MUST be ignored" — and **clamps** to the last day in
  Outlook. AllisWell clamps, because for a task "the 31st" means month end, and
  `byMonthDay: [-1]` ("the last day") is a first-class value rather than a
  workaround. Two more findings shaped the design: "the first Monday after the
  22nd" needs **no new field** (RFC 5545 makes `BYDAY` a limiter on `BYMONTHDAY`,
  and the spec's own example builds exactly this from a seven-day window), and a
  clamped rule **cannot be expressed to Google as a recurring event** at all —
  which independently justifies materializing occurrences as real rows and sending
  one event each. [ADR-0020](docs/adr/0020-recurring-tasks-and-materialization.md),
  DESIGN §25 (switch → auto-opening dialog, generated sentence, the "next 5"
  preview, scope defaults), tables and sources under OPH-204 in docs/TASKS.md.

### Planned — request rounds 11 + 12 (2026-07-29; Epic 18 shipped as 0.7.0 below)

- **Epic 19 — Recurring tasks, calendar always, flow fixes (OPH-204…214, toward
  v0.8.0; round 12, slotted in between at the owner's request).** Recurring tasks
  at last — the `repeat_rule` column has sat empty since v1: a structured rule
  model on an RFC 5545 subset with RFC 7529 clamping ("the 31st" lands on a short
  month's last day), Nth-weekday and after-day patterns ("the first Monday after
  the 22nd"), a config dialog that opens automatically with the Repeat switch, a
  live "next 5" preview, a **rolling 12-month window** of materialized real task
  rows kept fresh by a daily sweep, and Google-style edit scopes (default:
  this-and-future). Plus: the calendar mirror loses its opt-in switch (every dated
  task becomes a 30-minute block, 23:29–23:59 when timeless; dateless tasks land
  on their creation day; Google Tasks / Apple Reminders native-todo mapping
  evaluated); overdue tasks completed today stop haunting the Overdue group; the
  project-edit sheet stops opening under the popup menu; Home's view and calendar
  toggles move into the app bar; and the screen-on alarm's dead snooze button +
  tap-to-crash get a device investigation. BLUEPRINT §7.1/§12.2/§12.17,
  DESIGN §16/§20/§25, ADR-0020/0021 at implementation.
- **Epic 20 — AI (OPH-215…227, toward v0.9.0; renumbered from OPH-204…216 when
  round 12 slotted Epic 19 in).** Two tracks, because the researched
  reality is that no provider permits third-party use of consumer subscriptions in
  mid-2026: **Track A** — an AllisWell remote MCP server ("add AllisWell to your
  Claude/ChatGPT", where your subscription pays for the intelligence); **Track B** —
  embedded AI with your own API key (Anthropic / OpenAI / Gemini / OpenRouter /
  Ollama; thin fetch adapters, encrypted keys). In-app surfaces: an SSE-streamed AI
  bubble, a left-side hold-to-talk FAB (lift-to-lock), on-device speech recognition,
  single-schema task extraction with a **mandatory confirm card** committing through
  the local-first task store, an OS share target, per-provider consent screens, and
  an architectural injection defense (no model tools in v1; deletion permanently out
  of AI reach; red-team corpus in CI). [docs/AI.md](docs/AI.md),
  [ADR-0019](docs/adr/0019-ai-provider-architecture.md), BLUEPRINT §4.13/§12.16,
  DESIGN §24.

## [0.7.0] - 2026-07-29

The Quick Access release (Epic 18, OPH-196…203): the shortcuts you live in,
one list, on every surface — a section of the sidebar on desktop and web, a
popover on narrow windows, a draggable floating button on phones. It is also
the first thing in AllisWell that is **yours rather than the workspace's**:
`quick_link` is the sync protocol's first user-scoped entity, so two members of
a shared workspace never see each other's shortcuts.

### Added

- **Shortcuts you can recognise at a glance (OPH-202).** Give any shortcut an
  emoji (recents + a curated grid + type your own — the system keyboard is the
  real picker, so no new dependency), a colour from the project palette, or
  your own name. Clearing the emoji returns the row to its kind icon; clearing
  the name falls back to the target's current one, and when the target has
  been renamed the row says so and offers to match it in one tap.

- **Shortcuts are born where the thing lives (OPH-201).** Projects (list and
  detail), notes (list, grid and editor), tasks, folders and files all carry a
  ⚡ "Add to quick access" entry that flips to "Remove from quick access" once
  it is there — there is no "add again". The rail, the popover and the phone
  panel each grow a "+" for external links: a bare host becomes https, an
  address we cannot open is refused out loud, and an empty name falls back to
  the host. Hitting the 50-shortcut cap says so instead of failing quietly.

- **The floating quick-access button (OPH-200).** On phones a draggable ⚡
  button floats above the app — park it on either edge at any height, and it
  stays there across launches; after three idle seconds it half-recedes into
  the edge at 40 % (the platform's own AssistiveTouch default) and any touch
  brings it back. Tapping opens a panel with the same shortcuts the sidebar
  shows. It steps aside whenever a dialog or sheet is open, never appears on
  the sign-in screens, over the tour or over a ringing alarm, and can be
  switched off in Settings — in which case Home's app bar carries the ⚡ entry
  instead, because a feature must never depend on a gesture alone.

- **Quick access in the sidebar (OPH-199).** Wide layouts get a "Quick access"
  section under the navigation destinations: shortcut rows with their emoji or
  kind icon, the user's own name, a colour dot and — for external links — an
  explicit glyph, plus drag-to-reorder and a collapsible header. Between 800
  and 1160 px the rail shows a single ⚡ button that opens the same list in an
  anchored popover. Every row also offers "move up"/"move down" in its menu,
  because dragging is the one gesture a screen-reader user cannot aim.
  Clicking a shortcut navigates: projects, notes, tasks, folders (a new
  `/files/folder/:id` entry point) and files, with external links opening in
  the real browser.

- **Quick links on the device (OPH-198).** drift **v13** adds the `quick_links`
  replica and a `QuickAccessStore`: add, rename, emoji, colour, remove and a
  whole-rail reorder, each an optimistic local write plus one outbox mutation,
  so the rail works offline. Rows are joined to their targets in a single
  watched query, so renaming a project updates the rail live and a target that
  is gone reads as broken rather than vanishing. Deleting a task, project, note
  or folder drops its shortcut locally at once — the server's cascade is what
  the other devices see.

- **Quick links, server side (OPH-197).** `quick_links` is the sync protocol's
  first **user-scoped** entity: stored per workspace, handed out only to its
  owner. `GET/POST /workspaces/:id/quick-links`, `PATCH/DELETE /quick-links/:id`
  and `PUT /workspaces/:id/quick-links/order`, all revision-stamped, plus the
  push/pull registrations. Deleting a project, task (whole subtree), note,
  folder subtree or file removes every member's shortcut to it in the same
  transaction; archiving deliberately does not. 50 shortcuts per user, machine
  readable refusals (`QUICK_LINK_LIMIT`, `QUICK_LINK_DUPLICATE`,
  `QUICK_LINK_TARGET_NOT_FOUND`, `QUICK_LINK_NOT_YOURS`,
  `QUICK_LINK_ORDER_INCOMPLETE`).

### Changed

- **Quick Access design calibrated against the real idioms (OPH-196, docs only).**
  The floating button's idle dim moves from a guessed 55 % to the platform's own
  **40 %** (AssistiveTouch's documented default), the half-recede becomes a
  paint-only effect so the 44 px tap target survives, and the shortcut's colour
  dot gains a 1 px ring — because 5 of the 10 palette colours cannot clear 3:1 as
  a bare fill, and the palette is reused verbatim by design. Dragging is now
  explicitly never the only way to reorder (per-row move up/down actions).
  DESIGN §23 Q4/Q4a–Q4c/Q8a/Q9, ADR-0018 consequences, BLUEPRINT §4.12
  (`color` → `color_rgb`, emoji cap is graphemes-in-16-chars, not bytes).

### Notes

- **Version 0.7.0** across all four sources (pubspec, `kAppVersion`, both
  package.json files); drift schema **v13**; one new migration
  (`quick_links`), append-only as always.
- Nothing here needs a device: the whole epic is verified by the automated
  suites. App 603 tests, API 323 unit + 43 integration (including the
  two-member pull-isolation test that pins ADR-0018 forever).

## [0.6.0] - 2026-07-29

The round-10 release, and the theme is uncomfortable enough to say plainly:
**most of what was wrong was not missing code — it was code nobody could reach.**
Task deletion, subtasks, manual ordering and widget interactivity were all built,
wired and tested at the layers below the UI, and invisible above it.

### Highlights

- 🗑 **Delete, from the list.** Swipe a row from the trailing edge; it half-opens
  and waits, and the red **Delete** is what deletes — one careless flick can
  never destroy anything. Tasks, captures, notes, projects and files, plus the
  task detail screen, the row menus, the note card grid (which had no actions
  menu at all) and the board's move sheet. **Undo** works by not having written
  yet: if the app dies inside the window, nothing was deleted.
- ✅ **Completing a task stops being disappearance.** It stays in its group for
  the rest of the day, struck through and calm, then leaves at the next local
  midnight — on its own, without the app being reopened.
- 🗄 **Settings ▸ Completed** — everything you ever finished, newest first, day
  headers, paged as you scroll, sorted by the task's own date when it has one and
  by when you finished it when it does not. Read from the on-device replica, so
  it works offline.
- ⏰ **Editing a date keeps its time.** Changing the day of a 14:30 task used to
  move it to 23:59, silently. One input path now, everywhere.
- 🔗 **Tapping the widget goes somewhere.** `alliswell://` is registered with both
  operating systems and routed by a tested table; the router's error screen is
  ours and its way out works. Previously the tap produced `No route for
  alliswell://open/` and the recovery button produced a second error.
- 🔢 **The widget says how many tasks today actually holds** (overdue + due
  today), and iOS 17+/Android can tick one off **without opening the app** —
  through the same optimistic + outbox write the UI uses, so it syncs and works
  offline.
- 🎞 **Navigation stopped looking stuck.** The "ghost of the previous screen" was
  not a performance problem: every scaffold was ~50 % transparent over a single
  wash painted below the navigator, so both pages were visible through each
  other during a push. Each route carries its own background now, and one
  transition family replaces the three Flutter was handing out per platform.
- 🔊 **The alarm sound preview can be stopped** — its stop button did nothing,
  one playing sound disabled every other preview button, and closing the picker
  left it playing. Your own uploaded ringtones can be previewed now too.
- 🧹 **Two things that leaked at the user:** the project status picker (edit-only,
  printing raw English enum values, and a second route around the archive flow's
  cascade question) and the mystery "planned date" field — which is now an
  explanation that appears **only** when a calendar drag actually happened.

### Known limitations

- **Widget interactivity is not device-verified.** The code compiles and the Dart
  side is tested, but "tick a task off the home screen without opening the app"
  has not been run on real hardware yet (OPH-188).
- **Round 9's AlarmKit device matrix is still open** — unchanged by this release.
- Subtasks, recurring tasks, manual ordering and task color remain schema-only,
  now with written decisions rather than silence (docs/TASKS.md OPH-195).

### Added

- **The widget shows today's open count** and, on iOS 17+/Android, its circles
  complete a task in the background (OPH-187/188) — through `TaskStore`, the same
  optimistic + outbox write the UI uses, so a completion from the home screen
  syncs and works offline. Its date header is also drawn identically on both
  platforms now; iOS had been baseline-aligning a 34 pt number to a 14 pt label.
- **Delete, from the list** (OPH-184). Swipe a row from the trailing edge and it
  half-opens to reveal a red **Delete** — the button is what deletes, so one
  careless flick can never destroy anything. It is on tasks, captures, notes,
  projects and files, plus the task detail screen, the notes and projects row
  menus, the note card grid (which had no actions menu at all) and the board's
  move sheet. Deleting a task or a note shows an **Undo** that works by not
  having written anything yet: nothing reaches the database or the outbox until
  the undo window closes, so if the app dies in between, nothing was deleted.
  Deletes that cascade — projects, folders, files — keep their confirmation
  dialog; the swipe is a shortcut *to* that question, never past it.
  ([ADR-0017](docs/adr/0017-swipe-to-delete-package.md), DESIGN §19.)
- **Settings ▸ Completed** (OPH-186): everything you have ever finished, newest
  first, grouped by day and paged as you scroll — sorted by the task's own date
  when it has one and by when you finished it when it does not. It reads the
  local replica, so it works offline, and each row can be reopened or deleted.

### Changed

- **Editing a date keeps its time** (OPH-191). The detail screen used to ask
  only for a day and then stamp your default task time on it, so changing the
  date of a 14:30 task silently moved it to 23:59. Every task date field now
  goes through one input path — date, then time, starting from the value you
  are editing.
- **"Planned date" is gone from the task detail** (OPH-192) — it was a third
  date nobody asked for and it was never in the spec's field list. It exists for
  one real reason: dragging a task's event in Google Calendar writes it (moving
  a block means "I'll do it then", not "the deadline moved"). So instead of
  deleting it and pinning the event forever with no way to see it, the row now
  appears **only when that has actually happened**, says so — "Moved in your
  calendar — …" — and offers Reset.
- **Project editing no longer has a status picker** (OPH-193). It appeared only
  when editing, printed the raw server enum (`active`, `paused`) at you in
  whatever language you were reading, and offered a second way to change a
  project's state that skipped the archive flow's cascade question. A project is
  open or archived; archiving is its own flow. Existing `paused`/`completed`
  rows are untouched and behave as open — no migration, nothing lost.
- **Completing a task no longer makes it vanish** (OPH-185). It stays in its own
  group for the rest of the day — filled circle, struck through, calmly muted —
  and drops off at the next local midnight, which now happens on its own instead
  of waiting for the app to be reopened. The row is its own undo: tap the circle
  again. Alarm chips (urgent, snoozed, silenced) disappear once a task is done,
  because a finished task has no alarms and showing them was a false claim. The
  home-screen widget follows the same rule, and calendar dots ignore finished
  work. The muted look is built from tokens rather than an opacity wrapper, so
  its contrast is measured like everything else (eight new pairs in the guard).
- The projects list no longer prints a raw English status (`paused`) into a
  Turkish UI; the only state a person recognises is archived, and it has a
  localized label. The rest of that cleanup is OPH-193.

### Fixed

- **Navigation no longer leaves a ghost of the previous screen** (OPH-194). It
  read as lag and was not: every scaffold is ~50 % transparent and the wash was
  painted once below the navigator, so during a push both routes were visible
  through each other. Each route paints its own background now, and one
  transition family (220 ms) replaces the three Flutter handed out per platform.
- **Tapping the home-screen widget lands somewhere** (OPH-189). `alliswell://`
  was registered with neither operating system and the app had no resolver, so
  the tap produced `No route for alliswell://open/` — and the error screen's own
  "Home" button pointed at `/`, which was not a route either. Both are fixed, and
  the routing table is a tested pure function that refuses malformed ids.
- **The alarm sound preview can be stopped** (OPH-190). Its stop button did not
  stop — the icon changed but the control was disabled — and while one sound
  played every other preview button was disabled too, so tapping a second sound
  did nothing until the first ran out. Closing the picker left the sound
  playing. All three came from the same shape: the player was created inside the
  method that started it, where nothing else could reach it. Your own uploaded
  ringtones can be previewed now as well; they never could before.
- A deferred delete could silently never happen: the commit closure captured a
  widget's `WidgetRef`, and by the time the timer fired the row had left the
  list and its element was disposed. Found by a test, not by a user.

## [0.5.0] - 2026-07-28

The alarm release. Round 9 was the first time AllisWell was used *as an alarm
clock*, and it failed the way only a real user can reveal — so this version is
mostly about a reminder that behaves like one.

### Highlights

- ⏰ **A real alarm on iOS 26.** Urgent tasks ring through the silent switch and
  through a Focus, full-screen on the Lock Screen, using the phone's own alarm
  interface (Apple's AlarmKit — no special entitlement). This lane had been
  written weeks ago and had **never run once**: its Swift file was in no Xcode
  target, so the app built green while the only path that can outrun a hardware
  mute switch was dead. It is wired now.
- 🎯 **A task's deadline is its own alarm.** A reminder no longer swallows the
  due time — "warn me at 22:42 **and** hold me to 22:45" is two alarms, and both
  ring.
- 🎛 **You own the nagging.** Reminder system settings let you build the re-alert
  chain (Calm · Standard · Insistent, or your own steps), pick your snooze
  buttons and their order, and see on screen how many alarms your chain actually
  covers.
- 🔊 **Pick your alarm sound, or upload your own** — a small library plus your
  own files, honest about which formats iOS notifications can and cannot play.
  The in-app ring screen now makes noise too, which on desktop and web is the
  first alarm sound there has ever been.
- 🤫 **Silence a task's alarms without lying about it.** "Snooze indefinitely"
  keeps the task open instead of forcing you to complete it to make it stop.
- 🧾 **An alarm log.** The device keeps a local record of what was scheduled,
  with which sound, on which lane, and what you pressed — so "it didn't go off"
  is answerable instead of a memory exercise.
- 💬 **A snooze says what it will do** ("5 dk · 22:47'de çalar") and the task row
  shows "Snoozed — 22:52" afterwards.
- 🔄 **Pull to refresh** in all five sections, and Home stops pinning half the
  phone screen — only the app bar stays put.
- 📅 **One date formatter, and your choice of format** in Settings; the task
  sheet's date pickers open on tomorrow.

### Known limitations

- **The iOS 26 AlarmKit device matrix is not yet verified.** The lane compiles
  and links against the iOS 26.2 SDK and is wired into both targets, but the
  silent-switch + Focus + locked-screen pass on real hardware is still pending
  (OPH-182). If AlarmKit is unavailable or you decline its permission, urgent
  alarms fall back to time-sensitive notifications, which a mute switch silences.
- **Apple Watch** is documented, not measured — mirroring is free and needs no
  watchOS app, but the companion-target decision waits for a real watch (OPH-183).
- On Android, an **uploaded** sound cannot be a notification-channel sound
  without a FileProvider, so it plays in the in-app alarm instead — stated in the
  picker rather than hidden.
- **Widget interactivity** and the **macOS widget** are still not shipped.
- Desktop and web have no OS-level alarm guarantee; the in-app ring screen is the
  surface there.

### Development log

### Changed

- **Dates look the way you want them to** (OPH-174): every date and time in the
  app now comes from one formatter, so the broken `2026-07-31 23:59:00` in the
  task sheet is gone. Settings → **Date format** lets you pin the shape you
  prefer — 31.12.2026 23:59, 31/12/2026, 2026-12-31, 31 Aralık 2026, or the US
  12-hour form — each option previewed with the same sample date, so you pick a
  result rather than a pattern. The factory setting follows the app language, and
  your choice reaches the home-screen widget too, so the two never disagree.
- **The detailed task sheet lines up, and its date picker opens on tomorrow**
  (OPH-173): project and priority sit on the same line again — the "No projects
  yet" helper line under the project field was pushing them out of alignment, and
  it is gone (the picker still offers "+ Add project", and an empty list explains
  itself). Picking a deadline now opens on **tomorrow** rather than today: you tap
  for today, you plan for tomorrow. A reminder opens on its task's due day
  instead, because a nudge belongs next to its deadline.

### Added

- **On iOS 26, an urgent alarm is now a real alarm** (OPH-182). Urgent tasks ring
  through the silent switch and through a Focus, full-screen on the Lock Screen,
  with the phone's own alarm interface — Apple's AlarmKit, no special entitlement.
  This is the answer to "nothing came through while my screen was off". The
  alert's buttons are in your language, its snooze is whichever one you put first
  in your snooze order (and says so), and it plays the ringtone you chose.
  Acknowledging or snoozing from the Lock Screen reaches your other devices even
  if the app was not running. On iOS below 26, or if you decline the permission,
  urgent alarms keep the notification chain exactly as before.

  The honest part of the story: this lane was written weeks ago and had **never
  run once** — the Swift file was in no Xcode target, so the app built green
  while the one path that can outrun the mute switch was dead. It is wired now,
  and verified from the built app rather than from the source tree.
- **Apple Watch, explained rather than built** (OPH-183). Reminder system settings
  now say what a paired watch already does — alerts mirror to it while your phone
  is locked, no extra app — and where its sound and haptics live (Watch → Sounds
  & Haptics), which is a watch setting rather than one of ours.
- **Choose your alarm's sound — or upload your own** (OPH-181). Reminder system
  settings now has an Alarm sound and a Reminder sound row: the system's own
  sound, the 28-second alarm bed, or two new short tones (Chime, Ping), each with
  a play button so you pick by hearing. **Upload a sound** puts your own file in a
  "Zil sesleri" folder — an ordinary, synced, deletable file — and selecting it
  installs it for notifications. The rules are stated where you choose, not
  discovered at 3 a.m.: a notification sound has to be under 30 seconds and a
  .caf/.wav/.aiff file (mp3 and m4a play in the in-app alarm instead), and on
  Android an uploaded sound plays in the in-app alarm while notifications keep a
  built-in one. If an installed sound ever goes missing, the app records it and
  falls back audibly rather than letting the system swap in a quiet default.
- **The in-app alarm actually makes a sound** (OPH-180). When an urgent alarm
  comes due while the app is open, the ring screen now loops the 28-second alarm
  bed with a haptic pulse instead of buzzing silently — and on desktop and web,
  where there is no OS alarm at all, this is finally a real alarm. On iPhone it
  plays through the audio category that is audible even with the mute switch on,
  while you are looking at the screen. If a platform refuses to play (a browser
  blocking autoplay), the screen says so and offers a "Start the sound" button
  rather than looking like it is ringing.
- **You decide how insistent an alarm is** (OPH-179). Settings → **Reminder
  system** is one place for the whole chain: pick Calm (one alert), Standard
  (five) or Insistent (ten), or build your own — each alert has a minute stepper,
  and a live timeline shows exactly when a 22:42 alarm would ring. The limits are
  stated rather than silently applied: alerts stay at least a minute apart, up to
  twenty, and the screen tells you how many alarms the chain fully covers at once
  (iOS only keeps the 64 soonest, and we refuse to trim yours quietly). You can
  also turn off "repeat the whole chain after a snooze", and drag the snooze
  buttons into the order you actually use — the ringing alarm follows it.
- **Silence an alarm without pretending the task is done** (OPH-178). "Silence
  indefinitely" is now a real option — on the ringing alarm, on the notification
  itself, and as a switch in the task detail. The task stays open with its dates
  intact; the row says "Alarm silenced" and offers to turn them back on, so a
  quiet task can never masquerade as an armed one. Turning them back on is honest
  too: if the time has already passed, it says so instead of restoring an alarm
  that will never ring.
- **Snoozing tells you what it will do, and shows that it did it** (OPH-177). Each
  snooze option on the alarm screen now says the time it will ring at ("5 min ·
  rings at 22:47"), snoozing confirms it ("Rings again at 22:52"), and the task row
  and detail carry a "Snoozed — 22:52" line — until now a silenced task looked
  exactly like an armed one. The ring after a snooze names its round instead of
  impersonating a first alert, and there is finally a **custom snooze**: pick the
  exact time instead of choosing from four presets.
- **An alarm log, and one loudness rule** (OPH-176). Every alert of an urgent
  alarm — the first, each repeat, and every ring after a snooze — now asks for the
  same alarm sound and the same alarm-grade delivery; there is no quieter first
  alert, and a post-snooze ring says it is one instead of pretending to be a fresh
  alarm. And Settings → **Alarm log** finally answers "why didn't it go off?": it
  lists what this device scheduled, what it took back, what you touched and when
  the in-app alarm screen rang, with the sound and priority it asked for, ready to
  copy into a bug report. It is honest about its limits — iOS reports nothing about
  a notification you never touch, so the log never claims one was delivered.

### Fixed

- **An urgent task's own deadline rings again** (OPH-175). Setting a reminder used
  to REPLACE the deadline alarm: a task due at 22:45 with a 22:42 nudge alerted at
  22:42 and then let 22:45 pass in silence. A reminder is a nudge *before* the
  deadline, never a substitute for it — so an urgent task now carries both alarms
  independently, each with its own text ("the time you set is here" vs "waiting for
  acknowledgement"), and both at alarm loudness. Identical times still ring once.
  Answering one no longer silences the other, while a plain "not now" snoozes the
  whole task — previously it silenced one alarm and left the other to fire minutes
  later.

### Added

- **Home stops reserving the top of your phone screen** (OPH-172): the only
  thing pinned is the app bar. The view switch, the quick-add field, the search
  box and the month calendar now scroll away with the list instead of squeezing
  it — and what you had half-typed into quick add is still there when you scroll
  back. The board keeps its Liste | Pano switch in place (a sideways pager can't
  scroll it away without stranding you), and wide screens keep their pinned
  header and side calendar, where there's room for both.
- **Pull to refresh, everywhere it belongs** (OPH-171): drag down on Home (list
  and board), Ideas, Projects, Notes or Files and the app syncs — the spinner
  appears right under that screen's filters, holds long enough to be seen, and
  slides away. Empty screens are pullable too (a fresh install could not refresh
  before), the list is never re-mounted or scrolled under you, your search and
  filters survive, and a refresh that fails says so instead of pretending. On
  desktop and web — where a mouse wheel cannot overscroll — the same capability
  is a Refresh button in the section bar.

### Planned

- **Feedback round 9 → Epic 16 (OPH-171…183, toward v0.5.0)** — planning only, no
  behaviour change yet. The binding documents were written first, as the project
  requires: pull to refresh in all five sections; Home pinning nothing but its app
  bar on phones; aligned create-sheet fields with a **tomorrow** default date; one
  date formatter with a user-selectable display format; and the alarm backbone v2 —
  a task's own due time as its own alarm, one loudness contract for every repeat and
  post-snooze ring, honest snooze feedback, indefinite silencing that never fakes
  completion, a user-owned reminder profile, a ringtone library including uploaded
  sounds, sound in the in-app ring screen, a local alarm log, **iOS 26 AlarmKit
  actually wired into the build** (it had been in no Xcode target since round 6, so
  the mute-switch-proof lane had never once run), and a verified Apple Watch answer.
  See [ADR-0015](docs/adr/0015-alarm-delivery-and-reminder-profiles.md),
  `docs/NOTIFICATIONS.md` §2b/§5/§6, `docs/DESIGN.md` §15–§18, `docs/TASKS.md` Epic 16.

## [0.4.1] - 2026-07-26

### Fixed

- **The mobile app could not reach any server.** The API address was a
  compile-time constant defaulting to `http://localhost:3000`, and an Xcode
  archive passes no `--dart-define` — so the first TestFlight build shipped
  pointing at the tester's own phone. Release builds now default to
  `https://api.alliswell.space` (debug keeps localhost, so local development
  needs no flags).

### Added

- **Choose your own server.** AllisWell is self-hostable, so the address is now
  a setting rather than a fact baked into the binary: tap it on the sign-in
  screen — before you have an account — or in Settings. Typing a bare host is
  enough (`my.server.com` becomes `https://my.server.com`), paths are allowed,
  plain `http` is kept for LAN installs, and the choice survives restarts.
  Changing servers signs you out, because tokens belong to the server that
  issued them.

## [0.4.0] - 2026-07-26

The first release since the MVP — everything from Phases 5 through 9, plus a
self-hosting story that fits in one command.

### Highlights

- 🐳 **Self-hosting in one command.** Two published multi-arch images
  (`alliswell-api`, `alliswell-web`) and a ready compose file: `docker compose
up -d` installs, `pull` + `up -d` upgrades, and your data never leaves its
  volumes. The web image takes your API address at container start, so one
  prebuilt bundle serves any domain — [docs/SELF-HOSTING.md](docs/SELF-HOSTING.md).
- 🔔 **The alarm backbone.** Urgent tasks ring **at their deadline**, with a real
  28-second alarm bed, time-sensitive delivery that breaks through Focus, a
  re-alert chain until you acknowledge, an in-app ring screen on every platform,
  and honest banners when the OS is holding delivery back. On iOS 26 the urgent
  lane moves to **AlarmKit**, which rings through the mute switch with no
  entitlement.
- 🔎 **Search that speaks Turkish.** Case- and accent-insensitive across Home,
  Notes and Projects ("cay" finds Çay, "isi" finds ısı), ranked title > tag >
  body, running locally over the on-device replica — so it works offline.
- 🗂 **Board view + a real Files section.** Home flips between the chronological
  list and a **Kanban board** with your own status columns; the retired Calendar
  tab became a workspace-wide **Files** manager with nestable folders.
- 📎 **Attachments anywhere.** Files on tasks, notes and projects, inline images
  and video in notes, per-project Files tabs — stored in Cloudflare R2 or any
  S3, with bytes going straight between client and bucket via presigned URLs.
- 📅 **Calendar sync that just connects.** Linking Google now picks your primary
  calendar and syncs immediately; the hidden second step is gone.
- 🌍 **English + Turkish**, auto-detected, switchable in Settings — adding a
  language is dropping in one JSON file.
- 🖥 **Home-screen widgets** for iOS and Android, mirroring Home's buckets.
- ✨ **"Liquid Glass v2"** visual refresh, WCAG-verified in light and dark.
- 🐬 **MySQL 8 _or_ MariaDB 10.11+** — the schema picks a compatible collation
  per server, and CI proves both on every commit.

### Known limitations

- The **iOS 26 AlarmKit** Swift bridge is written but awaits its on-device
  build; until then urgent alarms use time-sensitive notifications, which a
  hardware mute switch can still silence.
- **Widget interactivity** (complete/quick-add without opening the app) and the
  **macOS widget** are not shipped yet.
- Desktop and web have no OS-level alarm guarantee: the in-app ring screen is
  the surface there.
- Attachments are single-PUT (≤ 5 GB, configurable per-file cap); multipart,
  thumbnails and quotas are v2.

### Development log

### Added

- **Self-hosting with Docker** — every release now publishes two multi-arch
  images (`ghcr.io/mahirozdin/alliswell-api` and `-web`, amd64 + arm64) plus a
  ready `docker-compose.selfhost.yml`. `docker compose up -d` is the whole
  install: the API applies its own migrations on start, and an upgrade is
  `pull` + `up -d` with data untouched in named volumes. Guide:
  [docs/SELF-HOSTING.md](docs/SELF-HOSTING.md).
- **Runtime API address for the web build** — the published web image reads
  `ALLISWELL_API_URL` at _container start_ (`web/alliswell-config.js` →
  `window.ALLISWELL_API_URL`), so one prebuilt bundle serves any domain without
  recompiling Flutter. The compile-time `--dart-define` remains the fallback and
  the only mechanism on mobile/desktop.
- **Tag-triggered deployment** — pushing `vX.Y.Z` now runs the full test suite,
  publishes the release and the images, then (when configured) deploys to the
  maintainer's server: database backup → migrate → restart → health check, and
  the job fails if `/health/ready` does not come back `ok`.
- **iOS 26 AlarmKit lane for urgent alarms (OPH-141)** — on iOS 26+, urgent
  task alarms ring through the mute switch and the current Focus via AlarmKit,
  with no critical-alerts entitlement. A pure lane (`planAlarmKitAlarms`) routes
  urgent alarms to a fakeable `AlarmKitHost`; the scheduler's set-diff cancels
  them on acknowledge/complete/snooze exactly like notifications; iOS < 26 and
  non-urgent reminders stay on time-sensitive delivery, and a declined/absent
  AlarmKit falls back to the notification chain (never dropped). Dart lane
  tested (app 377/377); the Swift bridge (`ios/Runner/AlarmKitBridge.swift`)
  awaits its iOS 26 device build.

- **MariaDB support** — the schema now resolves its utf8mb4 collation per server
  instead of hardcoding MySQL 8's `utf8mb4_0900_ai_ci`, which MariaDB does not
  have (it failed `CREATE TABLE` outright). MySQL keeps the same collation it
  always had; MariaDB gets `utf8mb4_unicode_ci`; `DATABASE_COLLATION` pins it
  explicitly. Verified on MySQL 8.4 **and** MariaDB 10.11 + 11.4 (migrations,
  rollback, and the full 37-test integration suite on each), and CI now runs a
  dedicated MariaDB job so it stays that way.

### Fixed

- **macOS signing** aligned to the publishing team — iOS and macOS now share
  `WWRZ5CG3DW`, unblocking the macOS build and the macOS widget (OPH-134).

### Planned (docs)

- **Feedback round 8 → Epic 15 (Phase 9, v0.4.0) designed and documented**
  (2026-07-20): auto-selected primary calendar with an immediate first sync on
  Google connect (the hidden "pick a calendar" step dies — root cause traced),
  a configurable default task time (23:59), the Calendar tab replaced by a
  global **Files** section with folders (ADR-0014: `workspace` file target,
  push-pull `folder` sync entity, counted recursive deletes), inline "+ New
  project" in project pickers, an editable task description with tappable
  links, a tag system you can actually type (`#tag` chip-input with
  auto-create and a manage sheet), Turkish-fold local search ranked
  title > tag > body (ADR-0013 — verified: neither SQLite FTS5 nor MySQL's
  ai_ci collation folds `ı→i`, so folding is app-owned with a cross-stack
  parity fixture), and a Home **Board** (Kanban) view with user-managed
  columns and a mandatory non-drag "change status" path (researched against
  Trello/Jira/GitHub mobile + NN/g). BLUEPRINT §12.10-12.12 + Phase 9 +
  Risk 8, DESIGN §10 F7-F9 + §12/§13/§14, ARCHITECTURE §6c, ATTACHMENTS §14,
  TASKS Epic 15 (OPH-160…170).

### Changed (round 8)

- **The Calendar tab is gone** (OPH-162): Home already carries the month grid
  and the chronological list, so a second calendar screen was dead weight.
  Picking any day in the grid — even far beyond the 30-day flow horizon — now
  shows that day's tasks and meetings in the highlighted selected-day group.
  The onboarding tour is one card shorter. (The freed nav slot goes to the
  upcoming global **Files** section.)

### Added

- **A Files section in the main nav** (OPH-170): the whole workspace's files
  in one place, Finder-simple. **My folders** holds standalone uploads
  organized into nestable folders — browse by breadcrumb, create, rename,
  move (folders and files alike, via a tree picker), and delete with the
  blast radius spelled out before anything dies. **Sources** lists every file
  attached to a project, task or note with a source badge and one-tap
  "go to source". Browsing works fully offline; the onboarding tour gained a
  Files card.

- **Folders and standalone workspace files — API** (OPH-169, ADR-0014):
  files can now belong directly to the workspace (no project/task/note), and
  nestable folders (≤10 deep, cycle-safe moves, Finder-style name rules that
  even fold Turkish ı/İ) organize them. Folder deletion is recursive and
  counted — the response tells you how many folders and files went — with
  every object removal riding the GC queue, so the no-orphaned-bytes
  guarantee holds. Folders sync offline like projects and tags; the app
  surface lands next (OPH-170).

- **Home gains a Board view** (OPH-168): a List | Board toggle at the top of
  Home. The board lays your tasks out as status columns — including
  completed/cancelled columns the chronological list deliberately hides — with
  drag-and-drop between columns (long-press to lift on phones, edge-hover
  advances the column pager) AND an always-visible "change status" button on
  every card, so moving never requires a drag. Hide and reorder columns from
  "Edit view"; every move is undoable from the snackbar. Your view choice and
  column setup persist on the device.

- **Search that speaks Turkish** (OPH-167, ADR-0013): every content screen
  can now search — Home covers tasks, captures AND your connected calendar;
  Notes searches titles and full note bodies; Projects filters as you type.
  Matching is case- and accent-insensitive the way Turkish actually needs:
  "cay" finds Çay, "isi" finds ısı, "ULKU" finds ülkü — folding no database
  engine performs (verified against SQLite and MySQL), done by one app-owned
  fold mirrored byte-for-byte on the API and guarded by a cross-stack parity
  fixture. Results rank title hits above tag hits above body hits, with the
  match context shown honestly; everything runs on-device over the replica —
  instant and offline. The API's task list gains a matching `?q=` for
  integrations.

- **Attach files while creating a task** (OPH-166): the new-task sheet takes
  file selections up front — they list as removable pending rows and upload
  the moment the task is saved. No more create-first-then-hunt-for-the-
  attachments-section.

- **Tags you can actually type** (OPH-165): a chip-input on the new-task sheet
  and the task detail — type a name, hit Enter/Tab/comma, it becomes a `#tag`
  chip. Existing tags are suggested case- and Turkish-accent-insensitively
  ("cay" finds #Çay); unknown names create the tag right there via an explicit
  "Create: #x" suggestion. Task rows show up to two inline tags plus "+N", and
  a "Manage tags" sheet renames, recolors (palette only) and deletes — the
  delete confirm tells you how many tasks lose the tag.

- **Tasks have a real description now** (OPH-164): a description field in the
  new-task sheet, and an edit-in-place description on task detail that
  autosaves like the title. URLs in it are detected and tappable — paste a
  link, tap it later. This is the task's own context, separate from linked
  Notes; rich formatting and link previews stay deliberate v2 items.

- **Create a project without leaving the task you're writing** (OPH-163): the
  project picker — in the new-task sheet and on task detail — now ends with
  "+ Add project". It opens the usual project sheet on top; the new project
  comes back already selected.

- **Default task time is yours now** (OPH-161): tasks created for a day
  without an explicit time — quick-add on a selected calendar day, the FAB's
  prefill, date-picker fallbacks — land at a configurable default time
  instead of a hardcoded 09:00. Factory default is **23:59** ("due by the end
  of that day"); change it in Settings → Default task time.

### Fixed

- **Connecting Google Calendar now actually starts syncing** (OPH-160): the
  OAuth callback auto-selects your primary calendar and immediately enqueues
  the first inbound sync and the push channel — previously the account sat on
  a hidden "pick a calendar" step and nothing was ever fetched, so Home stayed
  empty even after a reload. The app also pulls the moment you return from the
  browser or choose a different calendar (no more waiting for the next 60 s
  cycle). Reconnects keep your chosen calendar and refresh the feed.

### Changed

- **"Liquid Glass v2" visual refresh** (design round 8, ADR-0012): the whole
  app moved to an authentic Apple Liquid Glass look — vivid azure/indigo
  palette with Apple-red/green semantic colors (all 50 pairs still
  WCAG-verified, `FAILURES: 0`), navigation that floats as a glass capsule
  bar (phones) / glass panel rail (desktop) with blur + saturation boost,
  lensing edge, catchlight and soft shadow, a colorful azure/violet/mint
  aurora, capsule buttons, circular FAB, iOS-green switches, and rounder
  concentric radii (12/16/20/28/pill 32). Android home-screen widget colors
  moved with the tokens (W1). New reproducible screenshot harness
  (`design_screenshots_test.dart`) renders light+dark, phone+desktop with
  real fonts/shadows for the DESIGN §5 review; month-header and dropdown
  labels hardened against narrow-width overflow found by it.

### Added

- **Urgent alarms now ring inside the open app** (OPH-143, Epic 13): when an
  urgent task comes due while AllisWell is open, a full-screen alarm takes over
  with the task, an Acknowledge button and snooze presets (5/30 min, 1 hour) —
  it must be answered, not swiped away. This is the _only_ alarm surface on
  desktop and web, and the foreground companion to the phone's OS notification.
  A haptic pulse carries the insistence today (a looping sound is a follow-up;
  on mobile the OS alarm already plays it). Home also shows an honest banner
  when the OS can't ring alarms reliably — notifications turned off, or Android
  "Alarms & reminders" not granted — with a one-tap fix, so alarms never fail
  silently.
  "N files · X MB used" line under the project file manager. Attachment setup
  is now documented for self-hosters (README + docs/ATTACHMENTS.md — including
  the one-time R2 CORS rule web browsers need) and the security model is spelled
  out in SECURITY.md.
- **Notes carry images and videos inline** (OPH-156, Epic 14): the note editor
  gained insert-image / insert-video buttons — the file uploads to the note and
  drops into the text right where your cursor is. Images render inline (tap for
  full screen), videos show as a named tile that opens on tap, and the project
  README shows them too. Offline or missing media degrades to a labeled
  placeholder, never a broken-image icon. Embedded media also appears in the
  project's Files tab, and markdown exports reference it with stable links.
- **Every project has a Files tab now** (OPH-155, Epic 14): a simple file
  manager on project detail — one list of everything in the project (its own
  files plus its tasks' and notes'), each row labeled with where it lives,
  filterable by source, sortable by date/name/size, uploads straight into the
  project, and the same open/rename/delete actions as task attachments. Works
  offline for browsing; empty and "storage not set up" states say the truth.
- **Attach files to tasks** (OPH-154, Epic 14): task detail gained an
  Attachments section — add images, videos or any file from the picker, watch
  real upload progress (cancelable), tap an image for a full-screen viewer,
  and open/download, rename or delete anything from its action sheet (delete
  always confirms with the filename). If the server has no file storage
  configured, the section says so plainly instead of showing a dead button.
- **The app now speaks attachments** (OPH-153, Epic 14): every device keeps a
  local, offline-capable copy of attachment metadata (the lists render without
  a network; the bytes fetch on demand), and the upload machinery is in place —
  visible progress, cancel, honest failure with retry. Large videos stream from
  disk during upload instead of loading into memory. UI surfaces (task
  attachments, the project Files tab, note media) land next.
- **Files are fully readable, synced and cleaned up** (OPH-152, Epic 14): every
  device now learns about attachments through normal sync (metadata only — the
  bytes stay in storage and download links are minted fresh on demand, with the
  file's current name, Turkish characters intact). A project can list ALL of its
  files — its own plus its tasks' and notes' — each row saying where it came
  from. Files can be renamed (the stored object never moves). And deleting a
  task (subtree included), note or project deletes its files everywhere: other
  devices drop them on the next sync and the storage objects are cleaned up in
  the background. Note exports now include embedded images/videos as markdown
  links labeled with the file's name.
- **File uploads live on the API** (OPH-151, Epic 14): the full attachment
  lifecycle — declare a file on a project/task/note, PUT the bytes straight to
  storage with a presigned URL, and a verification step that only publishes
  files whose bytes actually match what was declared (liars get deleted).
  Abandoned uploads are swept after 24 h; deleting a file queues the object
  cleanup with retries so nothing orphans in the bucket.
- **File attachments are coming — storage foundation shipped** (OPH-150, Epic 14):
  the API can now talk to Cloudflare R2 (or any S3-compatible store — MinIO ships
  in docker-compose for local dev/CI). Bytes will never pass through the API
  server: it mints short-lived presigned upload/download URLs instead. Fully
  optional — without `STORAGE_S3_*` config everything answers honestly that
  storage is off. `GET /api/v1/storage` reports availability + limits to the app.
  Full design (incl. the R2 CORS setup web browsers need):
  [docs/ATTACHMENTS.md](docs/ATTACHMENTS.md).

- **Urgent tasks now alarm at their deadline** (OPH-138, Epic 13): an urgent
  task with a due time rings AT that time even if you never set a separate
  reminder — the deadline itself is the alarm (an explicit "Remind" time still
  wins when you set one). Works offline too: the device arms the alarm straight
  from the task and hands over to the synced reminder seamlessly.
- **Urgent alarms actually sound like alarms** (OPH-139, Epic 13): a real 28-second
  alarm ring (not the default ding) that repeats at +2/+5/+10/+30 minutes until
  acknowledged. On iPhone, alarms and reminders are now **Time Sensitive** — they
  break through Sleep and Focus modes (the old level was silently buried by any
  Focus). On Android the alarm plays on the **alarm channel**: it rings at alarm
  volume even when the ringer is muted, gets through default Do Not Disturb, and
  loops until you open it. A Critical-Alerts path (rings even on a muted iPhone)
  ships ready behind Apple's special approval — and the honest plan for muted
  iPhones is the new iOS 26 AlarmKit task
  ([docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md)).
- **Settings → "Urgent alarms" status row** (OPH-139): plain-language answer to
  "can the alarm actually ring on this device?" — flags notifications being off
  or Android's exact-alarm access missing, and a tap re-runs the permission flow.

- **Home-screen widgets — taking shape** (OPH-130/131/133, Epic 12): the app
  projects your open tasks into a compact, bucketed snapshot (Overdue / No date /
  Today / This week / This month) with a localized date header and publishes it
  through the `home_widget` bridge on every change. The **Android** widget that
  renders it — a scrollable bucketed list with a date header, light/dark — is
  written and compiles; the **iOS** widget (SwiftUI) is written and ready to wire
  up in Xcode ([ios/AllisWellWidget/SETUP.md](apps/app/ios/AllisWellWidget/SETUP.md)).
  Tapping opens the app; in-widget complete/add and the on-device visual pass come
  next. (See [ADR-0010](docs/adr/0010-home-screen-widgets-architecture.md) /
  [docs/WIDGETS.md](docs/WIDGETS.md).)
- **The app is fully bilingual — English + Türkçe** (OPH-122…128, Epic 11 done):
  every screen is now translated — sign-in/sign-up, navigation, Home and the whole
  task surface (bucket headers, locale-aware dates, quick-add, create/detail
  sheets, the Inbox), projects, notes, the Google/Apple calendar cards, the
  onboarding tour, Settings, and error messages. Switch languages in **Settings →
  Language** and the entire interface flips instantly. Bonus: status/priority
  dropdowns show proper names instead of `in_progress`; the picked language is
  saved to your account too (so it can follow you), and on the web the page
  `lang` reflects the active language for screen readers. Adding a new language
  needs no code — drop a JSON file (see
  [CONTRIBUTING](CONTRIBUTING.md#translating-adding-a-language)); a CI check keeps
  the UI free of hardcoded strings.
- **Language picker in Settings** (OPH-121): Settings → **Language** lets you
  pick a language — **System default** (follow the device/browser) or any shipped
  language shown in its own name (English, Türkçe). The choice applies instantly,
  persists across restarts, and the current one is checkmarked.
- **Localization foundation** (OPH-120, Epic 11): the app now has an
  internationalization layer — a small, app-owned synchronous store that reads
  JSON locale files (`assets/i18n/en.json` + `tr.json`), auto-detects the device
  or browser language, falls back to English per key, and rebuilds the UI when
  the language changes. No third-party i18n package. Strings are still English in
  this task; the extraction and the Settings language picker follow. Adding a
  language is dropping a JSON file. (See [ADR-0009](docs/adr/0009-localization-i18n-architecture.md).)
- **First-run onboarding tour** (OPH-111): a spotlight walkthrough of the main
  navigation that starts once for a new device and can be replayed anytime from
  Settings → App tour. Skippable, keyboard/back-friendly, and adapts to the
  phone bottom bar and the desktop rail.
- **Project archiving** (OPH-110): projects can be archived (and unarchived) with
  an optional cascade that also archives their tasks and notes — reminders on
  cascaded tasks deactivate and revive correctly. Archived projects are hidden
  behind an Active/Archived filter and show a banner with an Unarchive action.

### Changed

- **The Inbox is now "Fikirler" in Turkish** (OPH-137): the tab, the task status
  and the tour all follow — and the bottom-bar label no longer wraps when
  selected.
- **Today never looks disabled** (OPH-137): picking a calendar day used to fade
  every other group — including Today and Overdue, which read as "done/inactive".
  Now only future groups dim, and collapsing the calendar clears the day
  selection so an invisible filter can't keep dimming Home.
- Notification texts, action buttons and Android channel names are localized
  (English + Türkçe) — they were Turkish-only before (OPH-139).
- **README notes stay in their project** (OPH-109): creating or editing a
  project's README opens full-screen and returns to the project's Overview
  instead of jumping to the Notes tab, and README notes no longer clutter the
  notes list — a new "READMEs" filter surfaces them on demand.
- **Inbox is now a capture box** (OPH-107): the Inbox is for jotting thoughts
  fast — captures stay OUT of Home until you triage them. Each row offers Plan
  (opens a planning sheet), Convert-to-note, or Delete instead of a completion
  checkbox; giving a capture a date or project promotes it to a real task
  automatically.
- **Clearer status icons** (OPH-105): an open task now shows a pending
  hourglass instead of a bare circle (which collided with the completion
  checkbox); "waiting" takes a pause icon.
- **Project picker everywhere** (OPH-106): the task detail screen gained a
  project dropdown, and the create sheet now explains itself when you have no
  projects yet instead of showing an empty-looking picker.
- **Home rework** (OPH-102/103/104): the task list now spans a **30-day
  horizon** (Today / Tomorrow / This week / Next 30 days) so recurring calendar
  events past a month no longer bury real work; **dateless tasks sit at the top**
  (under Overdue, above Today) and never dim; on phones the **month calendar
  scrolls away with the list** instead of staying pinned; and every task row now
  shows a **colored project badge** with the project's name (its ink is computed
  for legibility on any project color).

### Fixed

- **Feedback round 5** (user testing on web): the onboarding tour now
  spotlights the specific navigation item at each step (it was highlighting the
  whole side rail); the task-row status icon sits consistently at the far right
  with the project badge and flags to its left; the project badge renders as a
  compact pill instead of a stretched bar; and a project's README overview shows
  its title as a heading and refreshes its content after an edit.
- **Web sign-out crash** (OPH-100): signing out on the web build threw a
  `TypeError` because a `204 No Content` response body arrives as an empty
  string on dio-web; the app now type-checks the response and always clears the
  local session even if the server call fails.
- **Mobile create buttons unreachable** (OPH-101): the floating action buttons
  on Home, Projects and Notes were painted behind the glass bottom navigation
  bar and could not be tapped on phones. The FAB is now rendered by the app
  shell so it always sits above the bar. Also fixed a Notes filter-chip row
  that overflowed on narrow screens.

### Planned (docs, 2026-07-17)

- **Epic 10 — feedback round 4** (OPH-100…OPH-111), from the first hands-on user-testing
  session: web sign-out crash fix, FABs unblocked from the glass nav, Home reworked to a
  30-day horizon (Today/Tomorrow/This Week/Next 30 Days, dateless on top, calendar scrolls
  with the list, project badges on rows), clearer status icons, project picker in create +
  detail, tabs returning to their root, README notes kept inside their project (+ a
  READMEs notes filter), Inbox reworked as a true capture box, project archiving with an
  optional cascade, and a first-run onboarding tour. BLUEPRINT §4.2/§4.3/§12.2–§12.7 and
  DESIGN §4 revised to match; details in [docs/TASKS.md](docs/TASKS.md).

## [0.1.0] - 2026-07-16

First release: the MVP is complete through Phase 4 (calendar sync). AllisWell is
a self-hosted, offline-first productivity hub — tasks, projects, notes,
reminders, and two-way Google Calendar sync, across all six Flutter platforms.

### Highlights

- **Accounts & workspaces** — argon2id passwords, 15-minute JWTs with rotating
  refresh tokens and reuse detection; a personal workspace per user.
- **Tasks, projects, notes** — subtasks, checklists, tags, priorities, urgent
  flags and reminders; projects with a README-note overview; Delta-canonical
  notes with FULLTEXT search and markdown export.
- **Offline-first sync** — a local SQLite replica is the source the UI reads;
  writes queue in an outbox and push idempotently with field-level
  last-write-wins; Socket.IO fans changes out live. Works fully offline.
- **Exact reminders** — local notifications scheduled from the replica, snooze
  presets, and urgent alarms that re-alert until acknowledged; a lock-screen
  privacy mode.
- **Calendar sync** — Google (server-side): OAuth, task→event mirror, webhook +
  incremental sync, two-way conflict handling, and your own events flowing back
  into Home and the Calendar tab. Apple (device-side): an EventKit task→event
  mirror. CalDAV is designed (v2).
- **"AllisWell Glass" design system** — hand-tuned light/dark, WCAG-verified in
  both themes.

### Known limitations

- Device passes pending for exact notification delivery and the Apple EventKit
  write round-trip (logic is unit-tested; hardware observation remains).
- macOS desktop build needs a local signing certificate (iOS builds today).
- Web builds keep tokens in memory only (signed out after a reload); the
  httpOnly refresh-cookie flow is planned hardening.
- Single active workspace in the UI (multi-workspace sharing is schema-ready, v2).

### Development log

The detailed, session-by-session record of how 0.1.0 was built follows.

### Added (2026-07-16, OPH-077/078 — Apple Calendar)

- **Your tasks can now mirror into your Apple Calendar** (iOS/macOS), the device-side twin of
  the Google mirror. Turn it on in Settings → Apple Calendar (request access, pick a
  calendar); tasks with "Show in calendar" then appear as `[Task] …` events, kept in step by
  a reconcile that runs in the app itself — Apple has no server API, so the device is the
  worker. One-way in v1 (task → event); the same §7.1 derivation as Google, so a task lands
  at the same time whichever calendar it reaches. Ships as a self-contained Flutter plugin
  package (`alliswell_eventkit`) that wires iOS **and** macOS with no Xcode project surgery.
  Hides itself entirely on non-Apple platforms.

### Fixed (2026-07-16)

- **The OPH-077 Swift plugin shipped empty.** The prior session's `git stash` recovery
  corrupted `AlliswellEventkitPlugin.swift` to zero bytes after the iOS build passed but
  before the commit, so the method channel had no native handler. `flutter analyze` never
  caught it (it does not compile Swift). Restored and re-verified with a real
  `flutter build ios`.

### Added (2026-07-16, OPH-084)

- **Your meetings now sit in Home's chronological list, beside your tasks** — a 10:00 meeting
  above a 16:00 task, in one stream, which is what §12 means by "the single chronological view
  where everything shows". The month grid marks days that carry only a meeting too.
  Two rules keep it honest: a meeting that already happened never lands in **Overdue** (that
  means "you still owe this" — a past meeting is history, not a debt), and an ongoing
  multi-day event belongs to **Today**, once, rather than repeating into every bucket it spans.

### Added (your calendar, in AllisWell — 2026-07-16, OPH-082/083)

- **Google Calendar events now show up in AllisWell** (ADR-0008). Connecting an account used
  to do nothing visible unless you mirrored a task: your meetings were deliberately ignored
  ("none of our business"), which made the Calendar tab a calendar without your calendar in
  it. They now sync into the replica as a read-only entity and appear on the month grid and
  in the day list, offline like everything else. Found by the product lead connecting his
  real account and asking where his events were — the spec never mentioned external events
  at all.
- The data was already in hand: the OPH-075 worker fetched the whole event feed every pass
  and dropped the foreign half. It now keeps it — one extra request per sync, not per event.
- Events are **read-only by construction**: no write path in the store, and absence from the
  push registry is the enforcement. A meeting has no checkbox — you cannot complete a
  wedding, and the row does not pretend otherwise.
- Migrations: `calendar_external_events` + `calendar_accounts.external_sync_token` (server);
  replica schema v3 (`external_events`).

### Added (Epic 08 app side — 2026-07-15, OPH-079…081)

- **You can finally connect Google Calendar from the app.** Settings gains a Calendar card
  (`features/integrations/`): connect (consent opens in a real browser), pick which calendar
  to use, see the account, disconnect. Honest about every state — a server without an OAuth
  client says so plainly rather than erroring (the integration is optional), an account
  Google signed out of asks to be reconnected instead of decaying silently, and a connected
  account with no calendar chosen is amber, not green, because it mirrors nothing yet.
  The API for all of this shipped in OPH-070…076; nothing could reach it until now.
- **Per-task "Show in calendar" toggle** (BLUEPRINT §12) and a **Scheduled row** on the task
  detail. `calendarMirrorEnabled` and `scheduled_*` now flow through the replica (drift
  schema v2 + the project's first `MigrationStrategy`), so a calendar event you drag in
  Google is finally visible in the app — that was OPH-076's whole point.
- [docs/CALDAV.md](docs/CALDAV.md) (OPH-079): the v2 iCloud connector design, written now
  because the decision it documents — asking users for an app-specific password, which is
  unscoped, never expires and cannot be revoked from our side — deserved writing down before
  anyone starts coding. 9 references.
- New dependency: `url_launcher` (opens the OAuth consent page).

### Fixed (app — 2026-07-15)

- **Every failed request retried for ~38 seconds behind a spinner.** Riverpod 3 retries any
  failed provider by default (10×, 200 ms → 6.4 s) and reports `AsyncLoading` while it does,
  so error states were effectively unreachable — including errors no retry can fix. Found by
  driving the real app: a dead Google credential was asked eleven times and the user never
  saw the message. `core/retry.dart` now retries only what a retry could fix (not reaching
  the server); everything else surfaces immediately. Affected every `FutureProvider` in the
  app.
- `desiredEventForTask` could derive a backwards calendar block from a `scheduled_end_at`
  left behind by a moved start — Google rejects `end <= start` with a 400 the mirror queue
  could never retry away. It now falls back to the default 30-minute slot.

### Added (Epic 08 inbound — 2026-07-15, OPH-074…076)

- **Google Calendar changes now flow back into tasks** (ADR-0007, BLUEPRINT §7.2 steps 6-10).
  `POST /api/v1/integrations/google/webhook` receives Google's push notifications, gated by
  the channel token it echoes back — minted by us, stored only as an HMAC, compared in
  constant time (`401 GOOGLE_WEBHOOK_INVALID_TOKEN` for a forged one; `200` for an unknown
  channel so Google stops retrying; the `sync` handshake marks nothing dirty). Notifications
  mark the account dirty and hand off to a queue.
- **Incremental sync worker** (`src/plugins/calendar-sync.js`): `syncToken` fetch with
  pagination, full resync on `410`, compare-and-clear of the dirty marker so a notification
  arriving mid-sync keeps its own pass. Channels are renewed a day before they lapse — the
  replacement goes live before the old one is stopped, so no change slips through the gap.
- **Two-way conflict handling** (`src/lib/inbound.js`, a pure decision function): our own
  writes are recognised by etag and ignored (this is what stops mirror ⇄ sync from looping);
  a foreign move lands on the task's `scheduled_*` fields; disagreements are recorded in
  `calendar_event_links.conflict_status`. Deleting our event in Google now **stops mirroring
  that task** instead of resurrecting the event or deleting the task; a recurring series or
  unusable times are flagged `time_conflict` and neither side is touched; both-changed races
  resolve by §6.5 last-write-wins. All-day events map to midnight in the task's timezone.
- `GOOGLE_WEBHOOK_URL` (optional — Google requires public HTTPS), `CALENDAR_WATCH_TTL_SEC`,
  `CALENDAR_SYNC_SWEEP_SEC`. **Without a public webhook address inbound sync still works**:
  the sweep polls those accounts instead, so localhost/NAT self-hosters are not left out.
- Migration `20260715180000_add_calendar_webhook_state`: `webhook_channel_token_hash`,
  `sync_dirty_at`, a unique index on `webhook_channel_id` and one on `webhook_expires_at`.

### Fixed

- **Two AllisWell deployments sharing one Redis consumed each other's queue jobs.** Both
  used the default BullMQ keyspace (`bull:calendar-mirror`), so a job could be executed by
  the wrong instance — which, having its own MySQL, found no such task and dropped the job
  silently: the calendar simply never updated. The keyspace is now namespaced per
  deployment (`REDIS_KEY_PREFIX`, default `alliswell`). Surfaced as a flaky integration
  suite once a second queue-driven test file existed.

### Changed (design round 1 — 2026-07-15)

- **"AllisWell Glass" design system** (ADR-0005, spec in `docs/DESIGN.md`, binding via
  AGENTS.md hard rule 11): full visual refresh of every screen. Liquid-Glass-inspired but
  UX-first — frosted-glass navigation chrome over a static aurora wash, while all content,
  forms and sheets stay on solid, WCAG-verified surfaces (text ≥ 4.5:1, icons/borders ≥ 3:1
  in BOTH themes; guard script `scripts/design/contrast.py`).
- Hand-tuned light/dark `ColorScheme`s + `AwTokens` design tokens replace the default
  `fromSeed` theme; components (inputs, buttons, cards, sheets, dialogs, chips, nav, snackbar,
  pickers) are themed centrally. Lists became rounded card rows; checkboxes are circular;
  sheets gained drag handles and width caps on desktop.
- **Accessibility/UX fixes shipped with the restyle:** priority flags and favorite/pin stars
  now use per-theme colors with ≥ 3:1 contrast (old amber-on-white was ~2:1); inputs always
  show a visible border + 2 px focus ring; password fields gained show/hide toggles; form
  errors render as icon + text banners (never color-only); overdue dates are flagged in red
  with the word "Overdue"; empty/error states are shared widgets with a Retry path; all
  icon actions have ≥ 44 px targets and tooltips.
- App test contract updated with the redesign: `taskPriorityColor(priority, brightness)`
  (hues fixed, lightness per theme) and scroll-aware widget-test finders.

### Fixed (feedback round 3 — 2026-07-15)

- **Web task edits never saved:** the API's CORS preflight only allowed GET/HEAD/POST, so
  every browser PATCH/PUT/DELETE (e.g. setting a due date) was blocked. All verbs are now
  allowed and covered by a regression test; failed writes in the app also surface as
  snackbars instead of silent console errors.

### Changed (feedback round 3 — 2026-07-15)

- **Task titles edit in place:** the detail screen title is a text field with debounced
  autosave.
- **Standard task visuals:** statuses show icons, priorities show colors (low=green,
  medium=amber, high=orange, urgent=red) — on list rows (colored flag + status icon) and in
  every status/priority dropdown; project pickers show the project's color dot before its
  name.

### Changed (feedback round 2 — 2026-07-15)

- **Home task entry:** a rapid-entry quick-add sits above the list — Enter clears the field
  and keeps focus so entries chain (type→Enter→type→Enter); with a calendar day selected the
  task lands on that day, otherwise dateless. A bottom-right FAB opens the full creation
  sheet (due/remind date-times, priority, project, urgent), prefilled with the selected day.
  Inbox and project quick-adds gained the same keep-focus behavior.

### Changed (feedback round 1 — 2026-07-14)

- **Home replaces Today/Upcoming:** the app opens on a Home dashboard — chronological task
  groups (overdue, today, tomorrow, this week, later, no date) beside an Apple-style month
  calendar; picking a day highlights its tasks and dims the rest. On phones the calendar
  collapses behind a persisted toggle. A dedicated Calendar tab shows the month + selected day.
- **Web sessions persist:** reloading the web app no longer signs you out (localStorage-backed
  session storage; httpOnly refresh-cookie flow remains planned hardening).
- **Projects:** Overview now opens on the project's README note (GitHub style,
  `readmeNoteId`); color picking is palette-only (hex codes hidden from end users, full color
  grid dialog); Tasks/Notes tabs are live lists with in-place quick adds.
- **Notes:** list ↔ A4-card grid views (persisted), edited/created dates + linked project in
  rows, one-tap star pinning, archive actions + Archive view, and the note title now renders
  as the document's fixed H1 first block (markdown exports lead with `# title`).

### Added

- Google Calendar — outbound mirroring (OPH-070…073, ADR-0006): connect a Google account
  over OAuth (offline access; tokens AES-256-GCM-encrypted at rest under
  `CALENDAR_TOKEN_KEY`, revoked and wiped on disconnect), pick a default calendar, and
  tasks opted in via `calendarMirrorEnabled` appear as `[Task] …` events — scheduled
  blocks verbatim, otherwise a 30-minute due/urgent-reminder slot. Every committed task
  write flows through a BullMQ queue (exponential-backoff retries; a deterministic inline
  runner without Redis) and converges the event: edits patch it, completing/cancelling/
  archiving/deleting removes it, reopening recreates it. Events carry the ADR-0003
  extended properties, and the worker re-links to an existing event instead of
  duplicating after a lost mapping row. The integration is optional
  (`GOOGLE_NOT_CONFIGURED` without credentials); mocked-Google tests cover the whole
  surface, plus a real-Redis BullMQ integration pass. Inbound sync (webhooks, incremental
  pulls, two-way conflicts) is next (OPH-074…076).
- Notifications (OPH-061…064) — Epic 07's client+server core: reminders now become real
  OS notifications scheduled from the local replica, exactly on time — urgent alarms ride
  Android's alarm-clock mode (never deferred, Doze-exempt) and iOS's time-sensitive
  interruption level, with a pre-scheduled re-alert chain (T, +2 m, +5 m, +10 m, +30 m)
  that keeps ringing until acknowledged on ANY device. Notification buttons complete,
  snooze (5 m/30 m/1 h/tomorrow) and acknowledge straight from the lock screen — all
  offline-safe outbox writes; the sync push gained `task.snoozedUntil` (snoozes the alarm
  in the same transaction, REST-parity) and a narrow `reminder {status: acknowledged}`
  mutation, plus `POST /api/v1/reminders/:id/acknowledge`. A new "Private notifications"
  setting hides task titles from the lock screen entirely. Exact-delivery behavior awaits
  a device verification pass (logic is fully unit-tested; see docs/NOTIFICATIONS.md).
- Live sync fanout (OPH-057) — Epic 06 complete: a Socket.IO server rides the API's HTTP
  listener; clients authenticate with their access token, join a room per workspace, and
  receive `sync:changed {workspaceId, toRevision}` the moment any write commits (REST and
  offline push batches alike, coalesced per workspace; Redis adapter fans out across API
  instances). The app opens one socket per session and pulls immediately on a matching
  event — edits from another device now appear within a round-trip, with the 60-second
  periodic pull demoted to a fallback. The socket never carries entity data.
- Notification device registry (OPH-060): `notification_devices` table plus
  `PUT/GET/DELETE /api/v1/notification-devices[/:id]` — registration doubles as a
  heartbeat (idempotent upsert), devices follow account switches, and unregistering is
  always a 204 so sign-out can't fail. Push tokens are optional: v1 notifications are
  local. Ships with [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) — the researched,
  11-reference plan for exactly-on-time urgent delivery (Android `setAlarmClock` +
  exact-alarm permission flows; iOS time-sensitive interruption level + 64-slot
  scheduling window; pre-scheduled re-alert chains).
- App — local-first (OPH-054…056): the app now reads and writes a local drift/SQLite
  replica of the workspace (native file storage; sqlite-wasm with OPFS/IndexedDB on web)
  and syncs in the background. Every edit lands instantly, works offline, and is queued in
  a durable outbox that pushes in order with exponential backoff; pulls apply batched
  snapshots and tombstones. Server-refused or newer-wins-trimmed writes surface as
  snackbars, and a note edited on two devices at once keeps your version as a
  "(çakışan kopya)" note instead of losing anything. Feature data now streams live from
  the replica everywhere (Home, Inbox, Calendar, Projects, Notes, tags, task detail).
- Sync protocol — server core (OPH-050…053): `GET /api/v1/sync/pull` streams batched,
  per-entity-coalesced snapshots and delete tombstones since a workspace revision;
  `POST /api/v1/sync/push` applies offline mutation batches (project/tag/task/note/checklist
  item) with per-mutation statuses, field-level last-write-wins for metadata — own pushes
  never conflict with themselves (attribution via recorded result revisions) and the newer
  wall clock wins field by field — plus document-level locking for note content
  (`NOTE_CONTENT_CONFLICT`). Full idempotency: every outcome is recorded in
  `client_mutations` (applied ones atomically with the entity write) and replays return the
  original result without re-applying. `withRevision(...)` joins `recordSyncWrite` as the
  blueprint-named transaction helper, with integration proof that concurrent writers produce
  gapless, monotonic revisions.
- Markdown export (OPH-045): `GET /notes/:id/export?format=md` streams the note as
  `text/markdown` (attachment, slugified filename), converted server-side from the canonical
  Quill delta by a converter mirroring the client one fixture-for-fixture — Epic 05 (Notes)
  is complete.
- App — notes (OPH-043, OPH-044): the Notes section is live — searchable (server FULLTEXT)
  list with All/Pinned chips, project detail Notes tab, and a flutter_quill rich-text editor
  with debounced delta autosave, client-side markdown generation with a preview sheet, pin
  and delete actions. New notes are created on their first autosave.
- Project notes (OPH-042): `GET /projects/:id/notes` lists a project's notes — both directly
  attached and link-attached.
- Note links (OPH-041): polymorphic note↔task/project links with workspace validation, and
  `POST /tasks/:id/notes` to spawn a note from a task — inheriting its project and linking
  back automatically.
- Notes API (OPH-040): workspace-scoped note CRUD storing Quill delta JSON as canonical
  content with markdown alongside and server-derived plain text; pinned/archived flags,
  FULLTEXT `?q=` search, cursor pagination and sync revisions.
- App — task screens (OPH-037): Inbox, Today and Upcoming are live lists from the API with a
  context-aware quick-add bar (Inbox captures, Today dues today, Upcoming dues tomorrow);
  checkbox complete/reopen; task detail screen with status/priority, urgent toggle, due/remind
  dates, tag chips and a checklist — completing Epic 04's end-to-end core-domain loop.
- App — project screens (OPH-036): the Projects section is now real — list with colors,
  favorites and status, create/edit bottom sheet with a color palette + free #RRGGBB input,
  and a project detail screen with the Overview/Tasks/Notes tab skeleton. The app resolves
  its current workspace via `GET /me`.
- Task snooze (OPH-035): `POST /tasks/:id/snooze` with an explicit time or the BLUEPRINT
  presets (5 min / 30 min / 1 hour / tomorrow morning — computed at 09:00 on the task's own
  timezone wall clock, DST-safe); task and live reminder snooze together, and unrelated task
  edits no longer wake a snoozed alarm.
- Reminder lifecycle (OPH-034): reminders now live in lockstep with their task inside the same
  transaction — setting `remindAt` schedules (or re-arms) the alarm, clearing it cancels,
  completing the task completes it, reopening re-arms, deleting cancels. Urgent tasks default
  to requiring acknowledgement; timezones are validated (`TASK_INVALID_TIMEZONE`).
- Task transitions (OPH-033): `POST /tasks/:id/complete` (idempotent) and `/reopen` with
  `completed_at` bookkeeping shared with status PATCHes; archived tasks are immutable on every
  write surface (`409 TASK_ARCHIVED`) except a lone unarchiving status change.
- Tasks API (OPH-032): task CRUD with rich filters (status/project/tag/due-range/urgent/parent)
  and ULID-cursor pagination; subtasks with cycle protection and subtree soft delete; checklist
  sub-resource; `PUT /tasks/:id/tags` replace-set semantics. Every write logs a sync revision;
  cross-workspace references are rejected with stable error codes.
- Tags API (OPH-031): workspace-scoped tag CRUD with slugs derived from names
  (Turkish-diacritic aware), per-workspace uniqueness (`409 TAG_SLUG_TAKEN`), slug release on
  soft delete so names can be recreated, and sync-revision logging on every write.
- Projects API (OPH-030): workspace-scoped project CRUD (`/api/v1/workspaces/:id/projects`,
  `/api/v1/projects/:id`) with color/status validation, soft delete (owner/admin), and the
  first building block of the sync engine: `recordSyncWrite()` bumps the workspace revision
  and appends the `sync_revisions` log row inside the same transaction as every entity write.
- App — secure token storage (OPH-025): sessions persist in the platform keystore
  (Keychain / Android Keystore / libsecret / DPAPI) via flutter_secure_storage and restore on
  app start; expired or corrupt blobs are dropped safely; logout wipes storage even offline.
  On web, tokens deliberately stay in memory (httpOnly refresh-cookie flow is the planned
  hardening).
- App — auth layer (OPH-024): dio API client (base URL via `--dart-define=ALLISWELL_API_URL`)
  with an auth interceptor that attaches the access token and transparently refreshes it once
  on a 401; auth repository with single-flight token rotation and forced sign-out when the
  session dies; login/register screens; router now guards the shell (splash while restoring,
  login when signed out) and Settings gained account info + sign out.
- Auth — middleware & `GET /api/v1/me` (OPH-023): `app.authenticate` route guard (JWT
  issuer/audience/expiry; expired tokens answer `AUTH_TOKEN_EXPIRED` so clients refresh instead
  of re-login), `request.user`, and a workspace-membership authorization helper. `GET /api/v1/me`
  returns the profile plus workspaces with roles — closing the Epic 03 acceptance: register,
  then immediately call an authenticated endpoint.
- Auth — refresh rotation & logout (OPH-022): `POST /api/v1/auth/refresh` rotates the opaque
  refresh token inside its family; replaying a retired token answers `401 AUTH_REFRESH_REUSED`
  and revokes the entire family (theft containment), with concurrent rotations settled by an
  atomic claim. `POST /api/v1/auth/logout` revokes the presented token — or the whole family
  with `?all=true` — and always answers 204.
- Auth — login (OPH-021): `POST /api/v1/auth/login` verifies argon2id credentials with a
  timing-safe unknown-email path (dummy verify) and answers `401 AUTH_INVALID_CREDENTIALS`
  without revealing which part failed; every login starts a fresh refresh-token family.
  All `/api/v1/auth/*` routes now share a stricter per-IP rate limit
  (`RATE_LIMIT_AUTH_MAX`, default 10/min vs the global 300/min).
- Auth — registration (OPH-020): `POST /api/v1/auth/register` creates the user, their personal
  workspace and owner membership in one transaction; passwords hashed with argon2id; returns a
  15-minute JWT access token and a 30-day opaque refresh token (stored only as a keyed hash).
  Duplicate emails answer `409 AUTH_EMAIL_TAKEN`. Production now refuses to boot with missing,
  placeholder, short or identical JWT secrets.
- Monorepo skeleton: npm workspaces, `apps/api` (Node.js/Fastify) and `apps/app` (Flutter).
- Project documentation set: `README.md`, `docs/BLUEPRINT.md`, `docs/ARCHITECTURE.md`, `docs/TASKS.md`, `docs/STATE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, ADRs 0001–0004.
- Docker Compose stack: MySQL 8.4 + Redis 8 (+ optional `api` and `adminer` profiles).
- API skeleton (`@alliswell/api`): Fastify 5 (ESM JavaScript), env config loader, request-id logging,
  security plugins (helmet/cors/rate-limit), MySQL (knex) and Redis (ioredis) plugins,
  `/health/live` and `/health/ready` endpoints with JSON-schema responses.
- Knex migration baseline for the full core schema: users, workspaces, workspace_members,
  refresh_tokens, projects, tags, tasks, task_tags, checklist_items, notes, note_tags, note_links,
  sync_revisions, client_mutations, calendar_accounts, calendar_event_links, reminders.
- Flutter multi-platform shell (iOS/Android/Web/macOS/Windows/Linux) with Riverpod + go_router and
  adaptive navigation (rail on desktop, bottom bar on mobile).
- CI pipeline (GitHub Actions): API lint + unit tests + migrations + integration tests against real
  MySQL/Redis services, Flutter analyze + test, TypeScript-ban guard.
