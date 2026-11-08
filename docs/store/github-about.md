# GitHub About, homepage and topics (OPH-411)

> Last updated: 2026-11-08 — proposed values; applying them is the owner's step (M-01, STATE
> "Kullanıcıdan bekleyen"). Nothing here has been written to the repository settings.

The About box is what a visitor reads before the README, and what search engines and link
previews quote. Today it says "Open-source", which the licence does not allow (ADR-0024: the
licence is PolyForm Noncommercial, **source-available**), and it still names Apple Calendar beside
Google as if both synced back; only Google does.

## Values

| Field | Today (2026-11-08) | Proposed |
| --- | --- | --- |
| Description | starts "Open-source, self-hosted productivity hub" and names Apple Calendar with Google | see below |
| Website | empty | `https://alliswell.space/?ref=github` |
| Topics | 16, including `fastify`, `mysql`, `project-management` | the 20 below |
| Social preview | GitHub's default card | `.github/social-preview.png` (1280×640, OPH-412; upload is M-02) |

**Description** (U-17, Ek A-71; 271 characters, GitHub allows 350):

```text
Source-available (PolyForm Noncommercial), self-hosted productivity hub: tasks, projects, notes, urgent reminders and two-way Google Calendar sync. Flutter app for iOS, Android, web, Windows, Linux and macOS; Node.js/MySQL backend. Free for personal use and self-hosting.
```

**Topics** (GitHub's limit is 20). Kept: `calendar-sync`, `cross-platform`, `flutter`,
`google-calendar`, `nodejs`, `notes-app`, `offline-first`, `productivity`, `reminders`,
`self-hosted`, `task-manager`, `todo-app`, `todoist-alternative`. Added: `alarm`, `caldav`,
`kanban`, `markdown`, `mcp`, `mcp-server`, `source-available`. Removed: `fastify` and `mysql`
(nobody looking for a to-do app searches for them) and `project-management` (team work is the
extension's, not this repository's).

The two most distinctive things, the alarm through Silent mode and the MCP connector, were in
no topic at all; `caldav` is there because calendar events go to any CalDAV calendar (tasks are
not served as CalDAV).

## Applying it

Settings → General, or in one command with the owner's GitHub login:

```bash
gh repo edit mahirozdin/alliswell \
  --description "Source-available (PolyForm Noncommercial), self-hosted productivity hub: tasks, projects, notes, urgent reminders and two-way Google Calendar sync. Flutter app for iOS, Android, web, Windows, Linux and macOS; Node.js/MySQL backend. Free for personal use and self-hosting." \
  --homepage "https://alliswell.space/?ref=github" \
  --remove-topic fastify --remove-topic mysql --remove-topic project-management \
  --add-topic alarm --add-topic caldav --add-topic kanban --add-topic markdown \
  --add-topic mcp --add-topic mcp-server --add-topic source-available
```

Afterwards `gh repo view mahirozdin/alliswell --json description,homepageUrl,repositoryTopics`
shows what GitHub stored.
