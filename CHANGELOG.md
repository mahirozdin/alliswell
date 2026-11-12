# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.20.0] — 2026-11-12

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
- **Urgent alarms and device removal hold up in the edge cases**
  ([#46](https://github.com/mahirozdin/alliswell/issues/46)–[#49](https://github.com/mahirozdin/alliswell/issues/49)).
  Snoozing one alarm of a ringing list counts from your choice, and cancelling "Pick a time"
  snoozes nothing. Acknowledging a ringing task also answers its deadline alarm. An offline-created
  alarm keeps ringing on Android when the app syncs, and a replan never rings a grouped minute
  twice. An alarm handled from the iPhone alert no longer stops later changes from syncing, and a
  widget completion made at the same moment is kept. Android remote stop retries a brief push
  failure. A device removed elsewhere also stops an alarm already ringing, and drops its alarms at
  its next background sync without losing an edit you just made; signing in right after such a
  removal keeps the new account's alarms and data.
- **The iPhone widget shows the new day after midnight**
  ([#50](https://github.com/mahirozdin/alliswell/issues/50)). The Today list, the counter and the
  lock-screen next task change at midnight without opening the app, and after three days without
  the app the widget says the list is out of date instead of showing an old one. Widgets show the
  newest list as soon as you leave the app, and Android widgets refresh after a change made on
  another device. Keeping the iPhone widget current while the app is swiped away comes with the
  next update.
- **The alarm screens and Settings › Devices are finished off**
  ([#46](https://github.com/mahirozdin/alliswell/issues/46)–[#48](https://github.com/mahirozdin/alliswell/issues/48)).
  Answering several alarms at once no longer stops later changes from syncing until a reload, and
  urgent alarms due in the same minute open as one list at the first one's second; an alarm the
  app shows late says how late it is. One Acknowledge answers an urgent task whose reminder and
  deadline fall in the same minute, and Acknowledge all on a list spanning two minutes acknowledges
  every alarm it showed. Snooze times stay right as the minute changes, every time
  follows your 12/24-hour setting, Acknowledge and Complete confirm, and small phones keep
  Acknowledge, Complete and Open on screen. The list of ringing alarms is laid out like the single
  alarm screen and fades where more alarms lie below. Devices always has a way back, even after a
  page reload, shows the current list each time you open it, and a switched-off browser tab shows
  one hint. Switching off the last ringing device offers "Vazgeç" and marks "Yine de kapat" as
  destructive.
- **Alarms keep up when they move between devices, and read well**
  ([#46](https://github.com/mahirozdin/alliswell/issues/46)–[#49](https://github.com/mahirozdin/alliswell/issues/49)).
  An open app or browser tab stops ringing urgent alarms within about a minute after they move to
  another device, and Home shows where they ring now; that card lines up with the other notices,
  with "Ring here too" as its main button, and Settings › Devices explains once, under its intro,
  what ringing on several devices means. Back from the system Settings app, the "alarm permission
  is off" notice and the Settings alarm row update at once, and urgent alarms move to the system
  alarm without a relaunch. The alarm screen fits small browser windows without hiding "Start
  sound", and screen readers read it in order, one button per snooze option. When alarms from
  different minutes ring together the list no longer shows one misleading time, and a row's snooze
  options say when they would ring with another alarm. Screen readers name each action in the list
  of ringing alarms and every option of a row's snooze sheet as a button, Enter and the number keys
  work again after that sheet closes, and the alarm screen no longer covers its text with a tooltip
  that repeats a title already shown in full.
- **Completing a task from the iPhone widget shows at once**
  ([#50](https://github.com/mahirozdin/alliswell/issues/50)). The row, the counts and the lock
  screen's next task update right away, and a day's count is its open tasks. The medium widget
  draws only whole rows, the circle is read aloud with the task's name, and the widget gallery text
  is in the phone's language. The "+N" line under the rows counts only the open tasks the widget
  does not show, and disappears when every open task is shown.
- **Typing a time in the time picker keeps the hour you typed.** In a 24-hour language such as
  Turkish, 05:25 no longer saves as 17:25, and 13:00 to 23:59 can be typed.
- **Sync recovers by itself after a request that never answers.** Sync and the device list run
  again on their own after a stalled connection, without reloading the app. On the web, an edit
  made offline is no longer lost when the page is reloaded.
- **A slow or briefly failing server no longer signs you out.** The app keeps your session and
  syncs again once the server answers.
