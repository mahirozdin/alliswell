# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Added

- **"Forgot password?" on the sign-in screen**: enter your email and a reset link arrives that
  works once, for an hour; setting the new password signs you out everywhere. A self-hosted
  server without email says so, and its admin can create the link with one command
  (`password-reset-link`, see SELF-HOSTING). The link can also be pasted into the app.
- **A team's service can be opened to customer companies** from its setup screen with an "Open to
  customer companies" switch, off by default, with one line saying what it does.

### Fixed

- **The demo workspace (`npm run seed:demo`) shows every surface and can be run again**: files are
  real (previews work), a note has a version history finished from Claude over MCP, and an AI
  provider, an API key and a Todoist import are set up; a second run no longer uploads the files
  and the project overview notes again.
- **Team screens use a desktop's width**: from 1200 px the requests list is one aligned line per
  request, a request opens beside the list (Esc closes, ↑/↓ moves, also through the All units
  list, opening each request in its own unit), the workload report is one
  table you can sort by any column, and team forms stay 720 px wide.
- **Team request lists answer "what, whose, how many" at a glance**: the requests list opens on
  all your units instead of an empty "choose a unit", a row names who opened it and who has it,
  every count says what it counts ("open now" apart from all time, and which unit a strip leaves
  out), and a share of nothing reads "—". Home shows your open requests, or what is late in your
  units. Opening a request keeps the All units list behind it, a CSV downloaded from All units
  holds every unit you work in, and the unassigned figure on Home no longer leaves an old search
  showing on the requests screen.
- **Dates and numbers read the way your region writes them**: "13:47", "Yarın 11:00", "7 Kas,
  13:47" instead of "07.11.2026 17:00"; an English app on a German phone shows "7 Nov, 13:47";
  amounts, percentages, file sizes ("6,3 MB") and durations ("2 gün 12 saat") follow the same rules
  on every screen, and an amount in a currency that shares your own's symbol is named by its code
  ("CAD 100" next to "$100"); a number typed into a form keeps every decimal ("0,001"). A date format picked in Settings still wins.
- **One voice in Turkish, one word for one thing**: the personal app says "sen" everywhere and
  team screens say "siz"; due dates read "Son tarih", notes switch between "Düzenle" and "Oku", and
  labels such as "Standart" or a project's "Özet" tab are no longer cut in the middle of a word.
  Notifications say "SLA missed" ("SLA aşıldı") and "SLA due soon", the same words as the e-mails.
- **Signing out works again**, and changing the server now signs you out of the old one first:
  nothing of the previous account, its team or its sync stays on screen.
- **Pushed screens use the whole screen again** (task detail, settings, a note): no empty band
  at the bottom. The status bar stays readable in the light theme, and on an iPhone in Turkish
  the microphone, speech, camera, photos, calendar and alarm permission prompts are in Turkish.
- **A task link opened in a fresh web tab opens the task**, instead of spinning forever; a link to
  a task that is gone, or a mistyped one, says so. "Continue with Google" appears only when your
  server supports it, and a phone now says when it can't reach the server.
- **Notification warnings are calmer and can be closed**: an amber strip with one short sentence
  and a button that says what it does, hidden for a week with "×". A server without browser-push
  keys now says so as a note for its admin instead of blaming you, the strip no longer appears
  behind the permission prompt, and the alarm screen only says "you set this browser to Silent"
  when you did.
- **Home's numbers match what you see**: a group header no longer counts finished tasks, and a task
  whose time passed today moves to Overdue. Subtasks are listed in their task's detail instead of
  as separate Home rows, the Board shows a repeating task once with "+N next", and search shows its
  total under the field with "Show N more" under each group, so notes are reachable.
- **The web app no longer contacts Google for fonts or its renderer**, emoji and Chinese, Japanese
  or Korean text included (the build serves those fonts itself), the new-task sheet closes
  with a tap above it even with the keyboard up, the alarm log reads in words with the raw line
  under "Details", a connector address on localhost carries a warning, and the app calls itself
  source-available rather than open source.
- **The phone's bottom bar names every tab** and no longer shifts when you pick one: five equal
  tabs that stay inside the bar at every phone width, a "More" tab when there is a sixth section,
  a light bulb for Inbox and a paperclip for Files. With very large text, press and hold a tab to
  see its name. On a phone the floating Quick Access button is now off unless you turn it on in
  Settings; the ⚡ in the Home bar opens Quick Access.
- **Nothing floating covers your tasks any more** on a phone: the microphone sits beside "+" on
  the right, both step down while you scroll, the bar and the buttons share one margin, and the
  list fades out under the bar instead of running under it. Quick Access also opens from the
  search screen's "Shortcuts" or a long press on Home; turned on, its button stays fully on screen
  and only shows on the main screens. On an iPad mini Home keeps one column under the phone bar.
- **Home's top bar on a phone has three buttons**: ⚡, "View" and Settings. "View" holds list or
  board, the calendar and the sort order in one menu. To filter Home's list, pull the list down;
  the search button beside the tab bar still searches everything. The title no longer gets cut off.
- **Text on iPhone and Mac reads like the system's own**: letter spacing now follows Apple's
  tables instead of Android's, so titles are tighter and fit more per line. Dates, times and
  counts keep their width as they change, and the red "Overdue" heading and the favourite star
  are easier to read.
- **Task rows are calmer and shorter**: a title takes at most two lines (the task itself shows all
  of it), the check circle lines up with the first line, and everything else sits on one small line
  under the title. Icons appear only when something is out of the ordinary, such as a high
  priority, a status other than open, or a reminder that will not ring through Silent. A pasted
  link reads as "site › path", and with large text the row stacks instead of squeezing the title;
  a long "Snoozed" time wraps rather than running off the card.
- **Home shows more of your day on a phone**: the calendar opens as one week, with the month one
  tap away (your choice is kept). Section headings are bolder, show their count apart, and fold
  with a tap. The quick-add box stays plain until you type, shows examples when you tap it, and
  after adding says "Added: … · Undo", highlights the new task and scrolls to it, up or down.
- **The microphone adds tasks by voice even without an AI provider**: say it, check the words in
  the quick-add box and add it; with no date it goes to your Inbox. While the phone asks for the
  microphone, the screen says so, and the assistant's "no provider" screen now has "Connect a
  provider" and "Save to Inbox" buttons.
- **The new-task form has Cancel and Add at the top**, so you never scroll to save; the keyboard's
  Done adds the task too. On a computer it opens as a dialog and Ctrl/⌘+Enter adds it, and
  swiping the form away asks before throwing away what you typed.
- **On a desktop, a task opens beside the list** instead of covering it: Escape closes it and the
  arrow keys move to the previous or next task, and every task opened there shows up in search's
  recent items. The side bar now stays on Settings and every
  other page, the board fits four columns and scrolls sideways for more, N adds a task and /
  opens search.
- **The first-run tour is four short steps** — typing a task with its time and tag, adding by
  voice, the urgent alarm and search — each pointing at its own button. A new account's empty
  Home now offers "Add your first task" and a way to move in from Todoist or TickTick.
- **The first-run tour no longer shows an error screen**: it waits for Home, spotlights the
  quick-add field and keeps its voice and Requests steps on a slow first start.
- **Quick add, links and sign-in behave**: the date question says "Add without date" instead of
  "Cancel", the keyboard closes after adding on a phone and Undo stays for 5 seconds; a link to a
  deleted or mistyped note says "not found" with a way home; a new device shows a loading
  placeholder instead of briefly claiming you have no tasks; signing in with another account opens
  Home, not the page the previous one signed out from; on a phone the web app's loading screen is
  shown at full size.
- **Menus, large text and dictation**: the close area of a menu (or "Dismiss menu" for a screen
  reader) only closes it instead of choosing an item; at the largest text sizes Settings no longer
  splits words or your e-mail mid-word and the calendar month and the new-task sheet's title are
  whole; on a device without a microphone dictation says so and lets you type instead of closing
  the app.
- **Team requests read straight**: "New request" and the microphone stand side by side with the
  label whole; the All units list shows the newest first ("SLA alerts only" keeps the most overdue
  first); opening another unit's request from All units no longer switches Home's unit; the
  workload note is translated and the bar names your team once; a member without a unit who opens
  the knowledge base is told answers are suggested while filing a request, with a button to open one.
- **Very large text keeps every control whole**: above 1.3x text the phone's bottom bar becomes one
  button with the open section's name that opens a list of every section in large type; Home's
  calendar shows the whole month and year with its arrows on a second row; task rows show a
  project's full name (a long one under the title with its colour dot) and a silenced task's
  "Sesi aç" button is never cut off.
- **Calmer, tidier controls**: the microphone is a quieter button with a visible edge in light mode
  and no longer covers the figures on the requests screen's read-only tabs; Home's fold arrows line
  up on the cards' right edge and the whole heading folds a section; the task detail's Urgent alarm
  row has its icon, lines up with the other switches and says it rings until you dismiss it; the
  new-task sheet uses one field style and picks project, priority and files from rows instead of
  drop-down menus; in the desktop sidebar's Quick access list the row menu and the drag handle are
  separate controls; with a screen reader, a drop-down list's close area only closes it.
- **Team request figures agree**: Home's unit summary shows past-SLA and due-soon requests apart,
  in the same words and numbers as the SLA board, and both stay current; with many open requests
  the All units list shows the newest first across the whole list; leaving it while another unit's
  request is opening no longer leaves Home on that unit.
- **The website says what it means**: the self-hosting section says the install is four steps and
  labels the compose command as the last one; the enterprise page footer reads "BubiApps ·
  Registered name: …" and the Turkish page names its cloud packages Başlangıç, İşletme and Kurumsal.
- **The buttons and guides get out of your way**: the microphone and "+" shrink away while you
  scroll down a list or type and come back when you scroll up or stop; the AI sheet opens with a
  short guide and three starter suggestions, and its Close button and handle close it; the app
  tour's alarm step points at a task that will ring (or the quick-add field), and on a phone the
  search step names the search button instead of Ctrl+K.
- **A deleted note says so**: a link to a deleted note says "Note not found", and a note deleted
  on another device while open becomes read-only with a "This note was deleted" notice instead of
  staying editable.
- **Large text and screen readers read it whole**: at large text sizes dates, your e-mail address,
  unit names and request subjects wrap instead of being cut, and Priority is as large as Status;
  screen readers hear task rows, the unmute button, the View menu's current choice and the
  large-text section list the way they read on screen; on desktop, Quick access names in the
  sidebar show in full again and the drag handle appears only on hover.
- **All units rows name the people**: in Requests > All units, each row shows who opened it and who
  has it once the server sends those names.

### Changed

- **The web app opens on a branded screen and "Start free" opens sign-up**: /app shows the app's
  icon and a progress bar while it loads instead of a white page, and the website's "Start free"
  button lands on the sign-up form. The enterprise page reads complete without scripts, no longer
  leaves blank space while you scroll, and is less than half as long.
- **The alliswell.space homepage leads with the alarm**: "Reminders that ring through Silent
  mode", with your own server and Claude or ChatGPT in the line below; a phone gets its store
  button, a computer the browser; a line under it counts the releases on GitHub; the bar links
  the source; the FAQ says what the licence is; the comparison is now Todoist, TickTick and
  Vikunja. New Terms of Service (`/terms`, `/terms/tr`), and a mistyped address now gets a real
  "page not found" instead of the homepage.
- **A shorter README**: one sentence on what AllisWell is, three ways in (web, your own server,
  download), one picture, and a comparison with Todoist, TickTick and Vikunja; building from
  source moved to `docs/development/README.md`, and its images weigh a quarter of what they did.

## [1.18.2] — 2026-10-30

### Changed

- **A new alliswell.space homepage** — rebuilt from scratch in English and Turkish: the real app
  moving in short loops, a one-minute film with captions, the connector for Claude and ChatGPT
  in three steps, self-hosting in one command, an honest comparison and every way to get the
  app. The whole page now reads without JavaScript, so search engines and link previews see it.
- **A new README** with animated tours of tasks, notes, alarms, repeats, the Claude connector and
  self-hosting, and the film one click away.
