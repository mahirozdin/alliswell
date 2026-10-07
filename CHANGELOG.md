# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Fixed

- **Signing out removes your data from the device (OPH-355).** The local copy — tasks, notes,
  requests, notifications and anything not yet sent — and your cached account details are deleted
  when you sign out; if changes have not reached the server yet, the app tells you how many and
  asks first. Signing in as a different person on the same device or browser starts from a clean
  copy, and the notification centre only ever lists your own notifications. Device settings
  (server address, language, theme) stay.
- **A busy or briefly failing server no longer blanks Home (OPH-355).** When the account lookup is
  rate-limited, fails on the server or times out, Home and the workspace switcher carry on with
  the last known list.

## [1.15.0] — 2026-09-30

### Changed

- **In an organisation's workspaces, Home is your own work (EE-296, ADR-0044).** Home lists the
  tasks you are on and the ones you made that nobody took, from every workspace you are in —
  each row names its workspace when there are several — never a colleague's. Notes, projects
  and files show the workspace selected in the switcher; a task added from Home lands there and
  is assigned to you. Every one of those workspaces now stays in sync on the device, the
  notification centre gathers them all, alarms and reminder pushes ring only for your own work,
  and calendars are not connected there. "Assigned to me" moved into Home (its address opens
  Home). Using the app on your own, nothing changes.
- **A request you are put on is a task on your list (EE-297).** Its row names the request and
  opens it; finishing the task resolves the request, reopening it takes the request back. The
  task cannot be deleted — "Give the request back" does that — and its title, priority and date
  follow the request unless you change them yourself. A refused change now says what happened
  ("this request is closed") instead of showing a code.
- **For extensions and API clients (ADR-0044).** `/me` marks the workspace the account `owned`
  and is ordered; tasks carry `createdBy`. An extension can refuse a write from inside its
  transaction — REST answers 409 with the code, the push records a rejection with the row to
  rebase on, instead of failing the whole push — and it is now told about task deletions and
  `PATCH` edits too. Due-reminder pushes can be narrowed per task by an extension.
- **Approvals are in the navigation, with a count (EE-294).** The approvals screen left
  Settings, where only a team's owner and admins could find it: on a wide screen it sits in
  the rail directly under Requests, on a phone it is pinned at the top of Quick Access (it
  cannot be edited or removed, and the floating button appears for it even with no
  shortcuts), for anybody the server says has approval authority. A red count — what is
  waiting on you by name plus what is waiting on your role — rides on the entry, the button
  and each of the screen's two tabs ("Mine", "Team"); every row now says who asked, when,
  for which service and desk, and the first lines of what they wrote. The old
  `/settings/team/approvals` address still opens it. One count badge for the whole app
  (`AwCountBadge`); DESIGN §23 Q10 and §32 S7 amended.
- **An approval opens onto the whole request (EE-295).** Every row, and the approval's
  notification, opens one page with what a decision needs: who asked and when, the
  description, the form's answers, every file and the conversation — internal notes included
  and marked — and who else signs. Before deciding, the approver can correct the subject, the
  description or the answers; the correction lands in the request's history under their name.
  Somebody who was not asked reads a summary only.

### Fixed

- **Every list keeps the same gap between its rows (OPH-353).** Card rows stacked with no space
  of their own sat border on border — the request queue among them — because a card's own
  margin is zero on purpose. One constant now spaces every card row 6 px apart (DESIGN §4), and
  the few lists that drew full-width rows or divider lines instead use the same card rows.

- **After a release the web app loads the new version on the next visit (OPH-273).** The
  edge in front of the site kept the app's code for four hours whatever the server said, so a
  browser that had opened the app shortly before a release went on running the old one —
  About showed the previous version. Every file under `/app` now reaches the browser with the
  server's own `no-cache, must-revalidate`.
