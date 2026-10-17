# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Added

- **Your tasks can go to an iCloud or any CalDAV calendar (Nextcloud, Radicale…) from the
  server, two-way, on every platform** — off until the server admin turns on `CALDAV_ENABLED`.
  Settings › Integrations › iCloud or CalDAV calendar: on the web, Android, Windows and Linux
  connect iCloud with an app-specific password; any device can connect another CalDAV server.
  Moving an event in the calendar moves the task's block, deleting it stops mirroring that
  task, and your own events show next to your tasks until you disconnect. The password is checked before it is
  kept, stored encrypted and never shown again. On an iPhone or Mac whose server already
  writes to iCloud, the on-device Apple Calendar mirror steps aside so nothing appears twice.
- **Enterprise: automation and routing rules can be created, ordered, tested and edited in the app.**
- **Enterprise desk: transfer a request to another service or unit.**
- **Ask the AI about a note or file.** Type @ in the AI chat to attach a note, a text file, a
  task or a project; only what you pick is sent, and long items are shortened with a notice.
  PDFs, images and Office files cannot be attached.
- **Add tasks by voice with Siri and Shortcuts on iPhone and Mac.** "Hey Siri, add a task in
  AllisWell" (TR "AllisWell'e görev ekle"), the Shortcuts app and Spotlight add a task; dates
  in what you say are understood ("yarın 9'da kira"), and it works offline. "Show today" opens
  Home on today. Android: long-press the app icon for New task and Today.
- **Repeat a task N days, weeks or months after you complete it.** In the Repeat dialog choose
  "After completion": change the water filter 90 days after you last changed it, late or early.
  Completing it creates the next one at the same time of day (a month after Jan 31 is Feb 28);
  reopening takes it back; deleting the open one ends the repeat. A completion made offline now keeps the moment you tapped it. Also
  on MCP (`set_task_repeat`, `get_task.repeat`, `complete_task.next`) and the API
  (`basis: "completion"` on `/task-series`).
- **Search everywhere: ⌘K / Ctrl+K, or the search button.** One box finds tasks, projects,
  notes, tags and file names, offline, grouped by kind; arrows and Enter open a result, and an
  empty box lists what you opened last. On phones the search button sits beside the bottom bar.
  A tag opens Home filtered by it; "Create task" takes the text you typed. Also in the MCP
  `search` tool (tags and file names).
- **Quick add understands what you type, offline, in Turkish and English.** "Yarın 9'da kira
  #ev" or "pay rent tomorrow 9am #home" becomes a task due tomorrow at 9, tagged, with no AI key.
  Dates, times, weekdays, repeats ("her pazartesi", "every weekday"), `+Project`, `p1`..`p4`,
  and deadline vs When ("başla pazartesi son cuma", "start mon due fri"). The recognized words
  are highlighted and shown as chips you can undo; the ? next to the bar lists the syntax.
- **When and Duration on tasks.** Pick the day you plan to do a task. It shows in Today from
  that day while the deadline and alarm stay put. Add how long it takes, and its Google/Apple
  calendar block uses that length instead of 30 minutes. Also on MCP
  (`create_task`/`update_task`) and the API.
- **Import from Todoist or TickTick: Settings › Data › Import.** Choose a Todoist backup or
  project CSV, or a TickTick backup; the wizard shows what will come in (tasks, repeats,
  sub-items as checklist items, projects, tags, and anything it could not carry over exactly)
  before writing anything. Importing the same file again creates no duplicates. Also one API
  call (`POST /workspaces/:id/import/apps`).
- **Windows and Linux desktop apps on every release.** A Windows zip and a Linux tar.gz are
  attached to each GitHub release; download links are in the README and on alliswell.space.
- **Apple Calendar on iPhone and Mac: moving or resizing a task's event now reschedules the
  task; deleting the event stops mirroring that task into that calendar.** The task itself is
  never deleted.
- **Connect Claude or ChatGPT with Google or Apple sign-in.** The AllisWell sign-in page that
  opens when you add the connector now offers "Continue with Google" and "Continue with Apple",
  so accounts made with Google or Apple sign-in can connect too.

### Fixed

- **Search results show a clean line around the match.** In notes and descriptions with line
  breaks, the preview under a result could start or end on a stray letter ("…r"); it is now
  cut on whole words, on one line.

- **Quick add forgets a ✕ once you empty the field.** After you dismissed a recognized
  date or tag and then deleted the text by hand, the same words stayed plain text in the next
  task you typed; now only sending the task or clearing the field starts fresh.

- **The page that connects an AI app (Claude, ChatGPT) fits a phone screen.** On a narrow phone
  its card was a little wider than the screen and scrolled sideways.

- **The AI chat answers in the web app again.** Its streamed reply left out the header that
  lets the browser read it, so the web app waited forever while phones and desktops worked.

- **Editing a repeating task no longer deletes its future tasks.** Renaming a daily repeat, or
  changing its days so that some of the old days stay (every day → weekdays), removed every
  upcoming task and created none. Now the tasks on days the repeat still has stay as they are —
  with their own edits, subtasks and links — and only the days it dropped go.

- **Windows: reminders now reach the notification centre** (they failed to initialise), and the
  Google sign-in button is hidden on Windows and Linux, where it could not work.

- **Security: the connector sign-in page now asks for your authenticator code when two-factor
  authentication is on.** Before, the password alone was enough to connect an AI app.

- **Security: signing in with Google or Apple now asks for your authenticator code when
  two-factor authentication is on.** Before, the Google or Apple account alone was enough. The
  app now shows a code prompt after the password or after Google / Apple — an authenticator
  code or a recovery code works, a wrong one can be retyped — so accounts with two-factor
  authentication can sign in to the app at all.

- **Honest Apple Calendar wording.** The website, README and store texts no longer call Apple
  Calendar sync two-way. Google Calendar syncs both ways; on iPhone and Mac your tasks are
  mirrored into Apple Calendar, one way for now.

- **The enterprise page now lists what the desk does today.** Files on desk replies, SLA target
  times and customer records with portal invitations are shown as in the app; bulk asset import
  and supplier targets are marked API only.

### Changed

- **README and comparison, straight to the point.** The README now opens with what AllisWell is,
  one thing you can check in two minutes and the links to get it; `docs/COMPARISON.md` adds an
  honest side-by-side with the self-hosted alternatives (Vikunja, Super Productivity, Tasks.org,
  Nextcloud Tasks), including where they beat us.

## [1.17.0] — 2026-10-15

### Added

- **Export a note as Markdown or Word.** Next to "Export as PDF", the note's ⋮ menu and the notes
  list's row menu now offer "Export as Markdown" (.md) and "Export as Word (DOCX)". The Word file
  looks like the PDF — same page, type sizes, colours, lists, checkboxes, callouts, tables,
  pictures and diagrams — as a standard .docx you can keep editing. Share, save to Files or
  download it like the PDF. Callout boxes in the PDF now print with their light tint
  instead of a solid colour block.

- **Your calendar in the home-screen widget.** On Android and iOS (and the macOS widget), the
  events Home shows from your connected calendar now appear in the widget's list too, between
  your tasks by time — today's with their time range or "All day". An event row has a calendar
  icon instead of a tick circle, and tapping it opens the app on Home with that day selected.
  "Private widget" hides event titles as well.

- **"Delete note" in the note editor's ⋮ menu.** A saved note can now be deleted from the editor's
  overflow menu as well as the app-bar trash. Both ask first with the same confirmation, which
  says the note will be deleted from all your devices.

### Fixed

- **Android widget taps after the app was closed in the background.** Tapping a task or event
  row after Android had stopped the app (while it stayed in recents) opened plain Home instead of
  the task or the day. The link is now kept and opened once the app is up.
