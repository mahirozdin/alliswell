# Changelog

All notable changes to AllisWell are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) • Versioning: [SemVer](https://semver.org/).

This file holds the unreleased changes and the latest release; at each release the previous one moves to [docs/changelog/](docs/changelog/) (and every release's notes are on its GitHub Release).

## [Unreleased]

## [1.16.0] — 2026-10-12

### Added

- **Connecting AllisWell to Claude or ChatGPT is findable now (OPH-364).** The connector URL,
  `https://api.alliswell.space/mcp`, is on the homepage in a section of its own with a copy
  button and the steps for Claude, Claude Team and Enterprise, and ChatGPT; on a new guide page at
  alliswell.space/docs/mcp that reads without JavaScript; in `llms.txt` for AI agents; and at the
  top of the README. `alliswell.space/mcp`, the address people guess, forwards to the API instead
  of quietly serving the homepage. In the app the URL is under Settings → Integrations, and it is
  shown even on servers that have the in-app AI switched off — alliswell.space among them, where
  it was hidden until now.
- **Claude's default connector option works (OPH-364, ADR-0047).** "Use Claude's published
  identity" no longer fails with "Couldn't register with AllisWell's sign-in service": the sign-in
  server accepts clients that name themselves by an https metadata URL, beside the automatic
  registration it already supported. The approval page shows where such a client comes from
  ("Claude (claude.ai)"). Self-hosters can turn it off with `MCP_CIMD_ENABLED=false`.

### Fixed

- **The "new" button no longer covers a list's last row (OPH-363).** On a phone, Units, a unit's
  members, Webhooks, Public links, Roles, Invitations, Companies, API keys, SLA and the other
  screens with their own round button now scroll their last row clear of it, so its ⋮ menu opens
  instead of the "new" dialog. The Quick Access button reads to a screen reader as one button,
  not a region the size of the screen. "Sent — your request is below" gives way as soon as the
  request shows up in the list, and can be closed.
- **The Quick Access button no longer sits on anything (OPH-362).** On a phone it rests in the
  bottom bar's row, beside a slightly shorter bar, and every page outside the main sections ends
  above it — a member's ⋮, the second approval's "Approve" or a "Save" button are reachable the
  moment the page opens, without scrolling. Drag it elsewhere and the page takes its full height
  back; it steps aside while the keyboard is up.
- **A request sent from an offline draft leaves the drafts at once (OPH-362).** It reads "Sent —
  your request is below" as soon as the desk files it, instead of "waiting to become a request"
  beside the request itself for the rest of the session.
- **The audit log says what was revoked (OPH-362).** A withdrawn invitation, webhook, public link,
  share, chat channel or mailbox is named as such instead of "ended a session"; ending a member's
  sessions still says so. The SLA policy editor's priority headings no longer overlap their
  fields' labels.

- **A request drafted offline survives a reload and goes on its own (OPH-361).** In the browser
  the draft is written to disk the moment it is saved, and it is sent as soon as the connection
  is back — from "My requests" too — without pressing "Try again". The new-request form offers
  "Attach file" only to people who work the request's unit, so nobody is told afterwards that
  their file could not be added.
- **Small fixes from the second audit pass (OPH-361).** Writing on your own request says "Write
  to the desk…" and "Send to the desk"; a change's calendar names a draft in the same window
  instead of saying nothing else is there; audit rows are dated in your date format and named by
  the server when it can; the scheduled saved-view report has a name among webhook events; two
  links made for the same service show the minute they were made and, when even that matches, a
  short reference. Approvals in the side rail is reachable with Tab and opens with Enter; on a
  phone every list and form can be scrolled out from under the Quick Access button.

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
