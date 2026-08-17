# Add AllisWell to Claude or ChatGPT

AllisWell ships a **remote MCP server** — a connector you add to your *own*
Claude or ChatGPT account. The AI then reads and updates your AllisWell
workspace using **your** subscription; AllisWell spends nothing on model calls.
This is Track A of the AI design ([AI.md](AI.md); [ADR-0022](adr/0022-remote-mcp-server.md)).

Every self-hosted instance is its own connector at `https://<your-instance>/mcp`.

Writing a script rather than asking an assistant? That is the REST API and a
personal key instead: [API.md](API.md).

## Add it to Claude

1. In Claude (Free ×1 / Pro / Max) open **Settings → Connectors → Add custom connector**.
2. Paste your instance's MCP URL: `https://api.your-instance.example/mcp`.
3. Claude opens AllisWell's sign-in page. Log in with your AllisWell account,
   pick a workspace, and approve the scopes.
4. The connector's tools now appear in Claude.

## Add it to ChatGPT

1. In ChatGPT (Plus / Pro) enable **Settings → Connectors → Advanced → Developer mode**.
2. **Add a connector** and paste the same `https://…/mcp` URL.
3. Sign in and approve, exactly as above.

## What the AI can do

Twenty-four tools, no delete tool — by design (loosening it needs a new ADR):

**Tasks**

| Tool | What it does |
| --- | --- |
| `list_tasks` | Filtered list, plus `today` / `overdue` in your timezone |
| `get_task` | One task in full — checklist, tags, project, alarms and its notes |
| `create_task` | Create a task; an unknown/ambiguous project creates nothing and asks |
| `update_task` | Change title, description, status, priority, dates, urgency, project or tags |
| `complete_task` / `reopen_task` | Mark a task done, or put a finished one back to open |
| `snooze_task` | Push a task's alarms out (5 min / 30 min / 1 hour / tomorrow morning, or a time you name) |
| `add_checklist_item` / `set_checklist_item` | Add a checklist item, tick it, or rename it |
| `acknowledge_reminder` | Answer an urgent alarm that is waiting for you |

**Notes, projects, tags, files**

| Tool | What it does |
| --- | --- |
| `search` | Find tasks, notes and projects (Turkish-aware folding) |
| `list_notes` / `get_note` | Notes with a short summary; one note in full, with its tags and what it is attached to |
| `create_note` | Write a note — standalone, filed under a project, or attached to a task in the same write |
| `update_note` | Retitle, rewrite, pin or archive a note (see the rich-text note below) |
| `link_note` / `unlink_note` | Attach a note to a task or project, or detach it |
| `list_projects` / `get_project` | Projects with their open-task counts |
| `create_project` / `update_project` | Make a project, change its name, description, status or due date |
| `list_tags` / `create_tag` | See the tags you use; add a new one |
| `list_files` | Attachment names, types and sizes — **never** the file contents |

Plus three read-only resources: **today**, **overdue** and **inbox** task views.

Write tools are annotated so Claude/ChatGPT show you an approval prompt before
they run, and every AI-made change is recorded in AllisWell's action log. The
ones that can overwrite text you wrote — `update_task`, `update_note`,
`update_project`, `set_checklist_item` — say so in their annotations, so hosts
treat them with more ceremony than a status change. Tools that create
something accept an idempotency key, so a host's retry never gives you the same
note or task twice.

Deliberate limits, so nothing here surprises you:

- **Nothing can be deleted.** There is no delete tool and there never will be
  one without a new architecture decision. `unlink_note` detaches a note; it
  does not remove it.
- **Any note's body can be rewritten, and nothing is lost when it is.** Every
  note is a markdown document ([ADR-0033](adr/0033-markdown-is-the-only-note-format.md)),
  and the body being replaced is kept as a version you can restore. Until
  2026-08-18 a note written in the app's rich editor answered
  `NOTE_NOT_MARKDOWN` — the assistant could rename a note it was not allowed
  to edit — because writing markdown onto a Delta would have left the body and
  the canonical source disagreeing.
- **Archiving a project stays in the app**, because it cascades over that
  project's tasks and notes and deserves your confirmation.
- **File contents never leave through the connector** — no download links, no
  bytes, only metadata.
- Colours and icons are not settable by the AI: those are yours to pick.

## Self-hosting notes

- Set **`API_PUBLIC_URL`** to your instance's public origin (e.g.
  `https://api.your-instance.example`) — it is the OAuth issuer and the MCP
  resource identity. In production it must be **HTTPS**.
- **`MCP_ENABLED=false`** withdraws the connector entirely (every `/mcp` and
  `/oauth/*` route answers 404). It is **independent of `AI_ENABLED`** — the
  MCP track spends no model money and stores no provider keys.
- One connection maps to **one workspace**; connect twice to reach two.
- Disconnect from Claude/ChatGPT, or revoke server-side, and the tokens die
  (opaque, hashed, family-revoked on reuse).
- Data the AI reads flows into **your** Claude/ChatGPT account under *your*
  consumer terms with that provider.

## Verifying with the MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

Choose **Streamable HTTP**, enter `http://localhost:3000/mcp`, and Connect —
the Inspector registers itself (dynamic client registration), opens the
sign-in/consent page in your browser (loopback redirect), and then lets you
call every tool and read both resources. This is the standing conformance
check (ADR-0022 consequences).
