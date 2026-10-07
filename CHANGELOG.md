# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

### Fixed

- **Sync works on a MySQL that is not set to UTC.** A self-hosted database whose clock follows a
  non-UTC host stamped rows hours ahead, so every device's edit was turned away as stale; each
  connection now runs in UTC.
- **Extending a public link never shortens it (OPH-360).** "Extend…" asks how long — 1, 2, 7 or 30
  days — and shows the new end before anything is sent; validity is offered in days, not "720
  hours". Each link row names its services, its unit and the day it was made; revoking asks "Keep
  it" or "Revoke link" in red, and a copy the browser refuses says so instead of failing silently.
  Revoking an API key reads the same way and the list says which workspace its keys reach; the
  approval dialog's button says "Approve" or "Reject" (in red) instead of "Save".
- **Companies and their people have a screen (OPH-360).** Settings › Companies lists the companies
  you serve and their contacts; add someone and send the invitation, switch a contact off (their
  sessions end at once) or back on, rename or archive a company. An older server says it cannot do
  this yet.
- **SLA administration asks before deleting (OPH-360).** Policies, calendars and monitors ask first
  and say what changes; the default policy is replaced, not deleted; a calendar a policy uses names
  that policy. Typing a policy's name enables Save, and a policy has a target table — first reply
  and resolution per priority. A missed target with no deadline left says why.
- **The SLA dashboard counts what it judges (OPH-360).** Missed, close to the limit and kept are
  shown as numbers; the percentage says "of 191 judged"; a team without a default policy is warned;
  a missed-target row carries its number and opens the request. Figures read "%40,3" and
  "3 g 21 sa" in Turkish, on the performance board too.
- **CSV downloads (OPH-360).** "Download CSV" in the request queue's menu (with `tickets.export`)
  and on the audit log, with the filters on screen.
- **The audit log reads like a log (OPH-360).** It is called "Audit log" as in Settings, filters by
  every kind of record by name, and each row names its record (number, subject or name) and opens
  it. Permission descriptions are in your language; absences a year ahead are listed and removable;
  an empty unit says so; a form never published no longer reads "everything is published".

- **The phone shell stays out of the way (OPH-359).** The request queue's "New request" button sits
  above the bottom bar and opens the form; lists and empty states clear the floating buttons; the
  bar's labels no longer clip at the capsule's edges; the unit picker scrolls, so a person in ten
  units can choose every one; and the team and unit ride under the screen's title, by name.
- **Screen readers and keyboards reach the navigation (OPH-359).** The side rail — Home, Requests,
  Approvals — is in the accessibility tree and reachable with Tab; the AI button opens with a
  screen reader or Enter; checkboxes, the archive search, the SLA line, dialogs and colour swatches
  have names ("Blue", not "#2563EB").
- **Every unit list says whose it is (OPH-359).** Requests, the knowledge base, changes, problems
  and meetings show the unit's name and a unit switcher; on the team's general space they ask you to
  choose a unit instead of saying the list is empty, and the knowledge base only suggests writing an
  article to people who may.
- **Links and reloads land where you were (OPH-359).** Screens opened from menus and lists put
  their own address in the URL (the SLA dashboard, performance board and "My units" have one now);
  a screen opened by its address has a back or Home button; a request opened from a link opens
  instead of waiting forever.
- **Meetings say why they failed, and recordings can be uploaded (OPH-359).** A failed meeting
  explains the reason in your language, with a way to the team's AI keys when a key is missing; a
  meeting that does not exist says so; "Upload a recording" sends a recording into the pipeline.
- **Turkish where it was English (OPH-359).** Home's calendar ("Ekim 2026", "Pzt…"), "Görev
  geçmişi", "Fikirler" instead of "Inbox", "çalışma alanı" instead of "workspace"; the mail screen
  names missing fields as the form does, and webhook events are listed in words.

- **A request's conversation says who wrote each message (OPH-358).** Every reply names its author,
  and — once the server sends it — whether it came from the desk, the requester or a company
  contact, by e-mail or the portal, on its own side of the thread. Writing on your own request
  says "Write to the desk"; on a request that came by e-mail the box says the reply leaves as an
  e-mail; a company-linked request shows the company and that its portal shows the replies.
- **Files on new requests and replies (OPH-358).** Desk members can attach files when filing a
  request and when writing a reply or an internal note; a note's files stay with the desk.
- **Linked requests (OPH-358).** A request lists the requests it is linked to (related, duplicate,
  parent/child) and opens them; the desk can link and unlink them, and "This came up again" opens
  the new request.
- **Request history, approvals, knowledge base and equipment read clearly (OPH-358).** History rows
  say what changed (status, priority, corrected form answers); a cancelled request says
  "cancelled on"; status notifications read "now In progress", not "in_progress"; a withdrawn
  approval says so; a change whose window has passed says "Window passed"; retiring an article
  asks first; articles can be linked to a service and show how often they prevented a request;
  equipment shows the changes planned on it, and dates, money and worked time ("45 min",
  "1 h 15 min") in your format. Without a personal space offline the new-request form no longer
  promises a draft it cannot keep, and a form opened by its address returns to My requests after
  sending.

- **People behind one office address no longer lock each other out (OPH-357).** Rate limits now
  count each signed-in person on their own, and sign-in counts per account: a whole shift can sign
  in from the same network at once, while one account's repeated wrong passwords are still stopped.
  When a limit is reached the app says how long to wait ("Too many requests — try again in 42 s")
  in your language, instead of "Unexpected server response".
- **Errors read in your language, with a way to try again (OPH-357).** A busy server, a missing
  page or a server failure shows a translated message on every screen; the performance and SLA
  dashboards offer Retry instead of printing an internal error. Parts of a request's page that
  fail to load (affected equipment, the known-error card, changes raised from it) say so with a
  Retry button instead of silently disappearing, and the Approvals entry no longer vanishes when
  one refresh fails.
- **A server failure no longer exposes internal details (OPH-357).** An unexpected error answers
  one generic message; the details stay in the server's log.
- **Workspace addresses keep the Turkish ı (OPH-357).** "Bakım" becomes `bakim`, not `bak-m`.

- **Team invitation links work (OPH-356).** Opening an invitation now shows the invitation itself
  — which team, which address, for which e-mail — on the team's own server: enter the code from
  the e-mail, choose a password if you have no account yet, and you are in. A link pointing
  anywhere other than a team of the server you use is refused, with the address named.
- **Signed in on the main address, a team member is shown the way to their team (OPH-356).** A
  banner on Home and one row in Settings name your team's address and switch to it without signing
  out. Requests, approvals and team screens opened from the wrong address say "Your team's address
  is needed" instead of an empty list, "you may not" or an error in English.
- **Team administration screens are locked for people they are not for (OPH-356).** Opening an
  admin address as a member shows one locked state, with no create button; controls wait until
  your permissions are known instead of appearing for a moment. The team chip shows the team's real
  name and colour, and the first-run tour of a team member includes Requests.
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
