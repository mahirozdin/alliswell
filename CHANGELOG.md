# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

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
