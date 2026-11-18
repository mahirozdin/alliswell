# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.22.1] — 2026-11-18

### Fixed

- **The AI assistant understands what "this" means.** Send a link and then write "remind me to
  read this news in 2 hours": the task is now named after the article (from the link's own words),
  the link goes into its description, and the reminder is set two hours from now. It used to
  read only your last message, so the task was titled with the request itself and the link was lost.
- **The review card shows everything it will save.** Next to the title you now see the
  description (with the link, editable) and the reminder, which you can clear; a time that has
  already passed is marked. Before, a reminder was saved without being shown.
- **Short follow-ups work.** "Yes, save it" after the assistant offers to save something creates
  that task, and the conversation records that the review card was opened.
- **The assistant reads links it cannot open.** Instead of only "I can't open links", it says what
  the page appears to be from its address and offers to save it as a task or reminder.
