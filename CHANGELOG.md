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

## [1.18.2] — 2026-10-30

### Changed

- **A new alliswell.space homepage** — rebuilt from scratch in English and Turkish: the real app
  moving in short loops, a one-minute film with captions, the connector for Claude and ChatGPT
  in three steps, self-hosting in one command, an honest comparison and every way to get the
  app. The whole page now reads without JavaScript, so search engines and link previews see it.
- **A new README** with animated tours of tasks, notes, alarms, repeats, the Claude connector and
  self-hosting, and the film one click away.
