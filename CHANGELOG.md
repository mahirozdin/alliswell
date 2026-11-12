# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.21.0] — 2026-11-12

### Added

- **The iPhone widget keeps itself current while the app is swiped away**
  ([#50](https://github.com/mahirozdin/alliswell/issues/50)). The widget asks your server for the
  latest list itself, with a read-only key that opens nothing but the widget's view, so a change
  made on another device shows within one of iOS's widget refreshes, typically 15 to 60 minutes.
  iOS sets that timing, so there is no minute guarantee. A change made on the phone that has not
  synced yet is never undone, offline or before the first unlock the widget keeps its last list,
  and with Private widget on no task title leaves the server; turning it on or off shows on the
  widget at once. The widget gets its key within seconds of signing in. Signing out or removing
  the phone turns the key off and leaves the widget empty. A tap on a circle shows the task done
  at once without moving the other rows, a task added on another device opens in the app when
  tapped, and two widgets on one screen show the same list. Each day's list stays right across a
  daylight-saving change that skips midnight.
