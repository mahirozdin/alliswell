# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.22.0] — 2026-11-18

### Fixed

- **A note you type on one device no longer says "edited on another device too", and no typed
  text goes missing.** A new note saved before its first sync finished was refused as a conflict
  with itself, and text typed while a save was still on its way could be dropped without a trace.
  Both are fixed on the server and in the app; text typed right before closing a note is saved,
  moving the cursor no longer saves, "Use the other one" now really shows the other text, and a
  conflict is no longer announced twice.

### Added

- **Version history and conflicts name the device and the exact time.** Each version shows what
  happened (edited, merged, restored…), which of your devices wrote it by the name in your device
  list ("This device" for the one you hold), and when, to the second. The conflict banner says
  which device and when for both sides, and the difference view names both sides too.
