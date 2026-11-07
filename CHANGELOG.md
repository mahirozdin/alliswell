# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Fixed

- **Signing out works again**, and changing the server now signs you out of the old one first:
  nothing of the previous account, its team or its sync stays on screen.
- **Pushed screens use the whole screen again** (task detail, settings, a note): no empty band
  at the bottom. The status bar stays readable in the light theme, and on an iPhone in Turkish
  the microphone, speech, camera, photos, calendar and alarm permission prompts are in Turkish.
- **A task link opened in a fresh web tab opens the task**, instead of spinning forever; a link to
  a task that is gone says so. "Continue with Google" appears only when your server supports it, and
  a phone now says when it can't reach the server.
- **Notification warnings are calmer and can be closed**: an amber strip with one short sentence
  and a button that says what it does, hidden for a week with "×". A server without browser-push
  keys now says so as a note for its admin instead of blaming you, the strip no longer appears
  behind the permission prompt, and the alarm screen only says "you set this browser to Silent"
  when you did.
- **Home's numbers match what you see**: a group header no longer counts finished tasks, and a task
  whose time passed today moves to Overdue. Subtasks are listed in their task's detail instead of
  as separate Home rows, the Board shows a repeating task once with "+N next", and search shows its
  total under the field with "Show N more" under each group, so notes are reachable.
- **The web app no longer contacts Google for fonts or its renderer**, the new-task sheet closes
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
  link reads as "site › path", and with large text the row stacks instead of squeezing the title.
- **Home shows more of your day on a phone**: the calendar opens as one week, with the month one
  tap away (your choice is kept). Section headings are bolder, show their count apart, and fold
  with a tap. The quick-add box stays plain until you type, shows examples when you tap it, and
  after adding says "Added: … · Undo", highlights the new task and scrolls to it.
- **The microphone adds tasks by voice even without an AI provider**: say it, check the words in
  the quick-add box and add it; with no date it goes to your Inbox. While the phone asks for the
  microphone, the screen says so, and the assistant's "no provider" screen now has "Connect a
  provider" and "Save to Inbox" buttons.
- **The new-task form has Cancel and Add at the top**, so you never scroll to save; the keyboard's
  Done adds the task too. On a computer it opens as a dialog and Ctrl/⌘+Enter adds it, and
  swiping the form away asks before throwing away what you typed.
- **On a desktop, a task opens beside the list** instead of covering it: Escape closes it and the
  arrow keys move to the previous or next task. The side bar now stays on Settings and every
  other page, the board fits four columns and scrolls sideways for more, N adds a task and /
  opens search.
- **The first-run tour is four short steps** — typing a task with its time and tag, adding by
  voice, the urgent alarm and search — each pointing at its own button. A new account's empty
  Home now offers "Add your first task" and a way to move in from Todoist or TickTick.

## [1.18.2] — 2026-10-30

### Changed

- **A new alliswell.space homepage** — rebuilt from scratch in English and Turkish: the real app
  moving in short loops, a one-minute film with captions, the connector for Claude and ChatGPT
  in three steps, self-hosting in one command, an honest comparison and every way to get the
  app. The whole page now reads without JavaScript, so search engines and link previews see it.
- **A new README** with animated tours of tasks, notes, alarms, repeats, the Claude connector and
  self-hosting, and the film one click away.
