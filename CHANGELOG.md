# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.19.2] — 2026-11-09

### Fixed

- **Text in a note can be selected and copied in Reading mode and in the split view's preview**
  ([#43](https://github.com/mahirozdin/alliswell/issues/43)). Drag with the mouse or long-press
  on a touch screen, then copy. Select-all copies the whole note, also the part below the screen.
  The copy keeps the note's shape: paragraphs stay apart, list items and table rows stay on their
  own lines. Links, checkboxes, images and the outline work as before (markdown_forge 0.1.1).
