# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Added

- **Choose which devices ring urgent alarms**
  ([#48](https://github.com/mahirozdin/alliswell/issues/48)). Settings › Devices lists every device
  signed in to your account, with its name, platform and when it was last seen, and a switch for
  urgent alarms. A new device starts off when another device already rings; the others show the
  alarm as a normal notification. After this update your account's first-added device rings, and
  any other device shows a one-time card with "Ring here too". You can rename a device, or remove
  it, which signs it out and removes its local data the next time it reaches the server (changes it
  has not sent yet are kept for your next sign-in there). Home warns when
  no device rings urgent alarms. On Android, acknowledging or snoozing an alarm on another device
  also stops the one ringing on the phone. A ringing iPhone can only be silenced on the iPhone.

### Fixed

- **Every button on the urgent alarm screen stops the sound at once**
  ([#46](https://github.com/mahirozdin/alliswell/issues/46)). The screen closes, a second alarm
  in the same minute stays fully usable, a snoozed alarm rings again on time, and a save that
  fails says so with Try again. On iOS 26 and later the system alarm goes quiet too, and the app no
  longer plays a second sound over it. The snooze choices are one even grid at the bottom, each
  saying when it will ring, with a full-width Acknowledge below; short screens and large text keep
  every action visible. Turkish times take the right suffix ("09:05’te çalar").
- **Snooze on the iPhone's alarm alert works**
  ([#49](https://github.com/mahirozdin/alliswell/issues/49)). It silences the alarm at once, even
  with the app closed, and the alarm rings again after the snooze time. If the new alarm cannot be
  set, a reminder notification takes its place. The task and your other devices show the snooze
  once the app next opens on the iPhone; Snooze and Stop pressed while the app was closed are
  applied exactly once, at the time you pressed them.
- **Urgent alarms in the same minute ring once, together**
  ([#47](https://github.com/mahirozdin/alliswell/issues/47)). They give one alert ("3 urgent
  alarms") and one sound instead of overlapping alerts. The alarm screen lists them all: answer
  each one, or all at once with Snooze all and Acknowledge all. Creating or editing an urgent task
  at a minute that already rings says both will ring together, with a Change time shortcut; saving
  is never blocked. Snoozing the group from the iPhone alert moves all of them together.
- **The iPhone widget shows the new day after midnight**
  ([#50](https://github.com/mahirozdin/alliswell/issues/50)). The Today list, the counter and the
  lock-screen next task change at midnight without opening the app, and after three days without
  the app the widget says the list is out of date instead of showing an old one. Widgets show the
  newest list as soon as you leave the app, and Android widgets refresh after a change made on
  another device. Keeping the iPhone widget current while the app is swiped away comes with the
  next update.

## [1.19.2] — 2026-11-09

### Fixed

- **Text in a note can be selected and copied in Reading mode and in the split view's preview**
  ([#43](https://github.com/mahirozdin/alliswell/issues/43)). Drag with the mouse or long-press
  on a touch screen, then copy. Select-all copies the whole note, also the part below the screen.
  The copy keeps the note's shape: paragraphs stay apart, list items and table rows stay on their
  own lines. Links, checkboxes, images and the outline work as before (markdown_forge 0.1.1).
